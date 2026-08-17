// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";
import {GitcoinGovernorPostUpgradeTestBase} from "test/helpers/GitcoinGovernorUpgradeTestBase.sol";

// Exercises the new Governor's quorum machinery after the upgrade: the DAO adjusting its own
// quorum via proposal (GovernorSettableFixedQuorum) and the late-quorum voting extension
// (GovernorPreventLateQuorum). Quorum targets are derived from the electorate's live weights so
// the scenarios stay valid as delegate weights drift across fork-block bumps.
abstract contract PostUpgradeQuorumBehaviorTest is GitcoinGovernorPostUpgradeTestBase {
  uint256 constant LOWERED_QUORUM = 1_000_000e18;

  function setUp() public virtual override {
    super.setUp();

    // The weight-shape assumptions behind this suite's quorum-boundary scenarios. These revert
    // rather than assert: a failure here means a fork-block bump reshaped delegate weights and
    // the scenarios need rebalancing — not that Governor behavior regressed. Each message points
    // the future developer at the scenario to fix.
    if (totalDelegateWeight - _votingWeightOf(CERV1) < QUORUM) {
      revert(
        "The electorate minus cerv1 no longer clears the original quorum; "
        "rebalance the raised-quorum scenarios"
      );
    }
    uint256 _blocWeight = _votingWeightOf(PROPOSER) + _votingWeightOf(ANON_GNOSIS_SAFE)
      + _votingWeightOf(EVENT_HORIZON);
    if (_blocWeight < LOWERED_QUORUM) {
      revert(
        "The sniping bloc no longer clears the lowered quorum; rebalance the late-quorum scenario"
      );
    }
    if (_blocWeight >= QUORUM) {
      revert(
        "The sniping bloc now clears the original quorum; rebalance the lowered-quorum scenario"
      );
    }
    if (_votingWeightOf(KEV) <= _blocWeight) {
      revert("kev.eth no longer out-weighs the sniping bloc; rebalance the late-quorum scenario");
    }
  }

  // Walks a setQuorum proposal through the full governance journey.
  function _setQuorumViaProposal(uint256 _newQuorum) internal {
    ProposalDetails memory _proposal = _buildProposal(
      address(governor),
      0,
      abi.encodeCall(governor.setQuorum, (_newQuorum)),
      string.concat("Set the quorum to ", vm.toString(_newQuorum))
    );
    _submitPassQueueAndExecuteProposal(_proposal);
    if (governor.quorum(block.number) != _newQuorum) {
      revert(
        "Test scaffolding: the setQuorum proposal executed but the quorum did not change to the "
        "requested value; the quorum-adjustment step this suite builds on is broken"
      );
    }
  }

  function test_ProposalMeetingOnlyTheOldQuorumIsDefeatedAfterTheQuorumIsRaised() external {
    // The DAO raises the quorum to the electorate's full combined weight.
    _setQuorumViaProposal(totalDelegateWeight);

    // Everyone but cerv1 votes FOR: a tally that clears the original quorum (guarded in setUp)
    // but falls short of the raised one.
    ProposalDetails memory _proposal =
      _buildGtcSendProposal(makeAddr("receiver"), 1000e18, "Send GTC under the raised quorum");
    _submitProposal(_proposal);
    _jumpToProposalActive(_proposal.id);
    _delegatesCastVotesExcept(_proposal.id, FOR, CERV1);
    _jumpPastProposalDeadline(_proposal.id);

    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Defeated);
    vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
    _queueProposal(_proposal);
  }

  function test_ProposalMeetingTheRaisedQuorumSucceedsAndExecutes() external {
    _setQuorumViaProposal(totalDelegateWeight);

    address _receiver = makeAddr("receiver");
    ProposalDetails memory _proposal =
      _buildGtcSendProposal(_receiver, 1000e18, "Send GTC meeting the raised quorum");
    _submitProposal(_proposal);
    _jumpToProposalActive(_proposal.id);
    // The full electorate votes FOR, meeting the raised quorum exactly.
    _delegatesCastVotes(_proposal.id, FOR);
    _jumpPastProposalDeadline(_proposal.id);

    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Succeeded);
    _queueProposal(_proposal);
    _jumpPastProposalEta(_proposal.id);
    _executeProposal(_proposal);
    assertEq(GTC_TOKEN.balanceOf(_receiver), 1000e18);
  }

  function test_ProposalMeetingOnlyTheLoweredQuorumSucceedsAndExecutes() external {
    _setQuorumViaProposal(LOWERED_QUORUM);

    // The minority bloc clears the lowered quorum but falls short of the original one (guarded in
    // setUp).
    address _receiver = makeAddr("receiver");
    ProposalDetails memory _proposal =
      _buildGtcSendProposal(_receiver, 1000e18, "Send GTC under the lowered quorum");
    _submitProposal(_proposal);
    _jumpToProposalActive(_proposal.id);
    _castVote(PROPOSER, _proposal.id, FOR);
    _castVote(ANON_GNOSIS_SAFE, _proposal.id, FOR);
    _castVote(EVENT_HORIZON, _proposal.id, FOR);
    _jumpPastProposalDeadline(_proposal.id);

    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Succeeded);
    _queueProposal(_proposal);
    _jumpPastProposalEta(_proposal.id);
    _executeProposal(_proposal);
    assertEq(GTC_TOKEN.balanceOf(_receiver), 1000e18);
  }

  function test_InFlightProposalKeepsTheQuorumCheckpointedAtItsSnapshot() external {
    // A quorum-raise proposal passes and sits queued in the Timelock.
    ProposalDetails memory _quorumRaise = _buildProposal(
      address(governor),
      0,
      abi.encodeCall(governor.setQuorum, (totalDelegateWeight)),
      "Raise the quorum"
    );
    _submitAndPassProposal(_quorumRaise);
    _queueProposal(_quorumRaise);

    // Meanwhile a send proposal is created and voted on with a tally (everyone but cerv1) that
    // clears the current quorum but not the pending raised one.
    address _receiver = makeAddr("receiver");
    ProposalDetails memory _inFlight =
      _buildGtcSendProposal(_receiver, 1000e18, "Send GTC while the quorum changes");
    _submitProposal(_inFlight);
    _jumpToProposalActive(_inFlight.id);
    _delegatesCastVotesExcept(_inFlight.id, FOR, CERV1);

    // The quorum raise executes while the send proposal is still in flight.
    _jumpPastProposalEta(_quorumRaise.id);
    _executeProposal(_quorumRaise);
    assertEq(governor.quorum(block.number), totalDelegateWeight);

    // The in-flight proposal is still judged by the quorum checkpointed at its snapshot.
    assertEq(governor.quorum(governor.proposalSnapshot(_inFlight.id)), QUORUM);
    _jumpPastProposalDeadline(_inFlight.id);
    assertEq(governor.state(_inFlight.id), IGovernor.ProposalState.Succeeded);
    _queueProposal(_inFlight);
    _jumpPastProposalEta(_inFlight.id);
    _executeProposal(_inFlight);
    assertEq(GTC_TOKEN.balanceOf(_receiver), 1000e18);
  }

  function test_QuorumReachedNearTheDeadlineExtendsTheVotingPeriod() external {
    ProposalDetails memory _proposal =
      _buildGtcSendProposal(makeAddr("receiver"), 1000e18, "A proposal reaching quorum late");
    _submitProposal(_proposal);
    _jumpToProposalActive(_proposal.id);
    uint256 _originalDeadline = governor.proposalDeadline(_proposal.id);

    // The electorate pushes the proposal over quorum 100 blocks before the deadline — within
    // the vote extension window — so the deadline extends to a full extension period from the
    // quorum-reaching vote.
    vm.roll(_originalDeadline - 100);
    _delegatesCastVotes(_proposal.id, FOR);
    assertEq(governor.proposalDeadline(_proposal.id), block.number + VOTE_EXTENSION);
    assertGt(governor.proposalDeadline(_proposal.id), _originalDeadline);
  }

  function test_LateOpposersDefeatTheProposalDuringTheQuorumExtension() external {
    // Under a lowered quorum, a minority bloc can trigger quorum at the last minute — exactly
    // the sniping scenario the extension defends against. kev.eth out-weighs the bloc (guarded
    // in setUp), and the extension gives them time to respond.
    _setQuorumViaProposal(LOWERED_QUORUM);

    ProposalDetails memory _proposal =
      _buildGtcSendProposal(makeAddr("receiver"), 1000e18, "A quorum-sniping attempt");
    _submitProposal(_proposal);
    _jumpToProposalActive(_proposal.id);
    uint256 _originalDeadline = governor.proposalDeadline(_proposal.id);

    // The bloc pushes the proposal over quorum just before voting would have closed.
    vm.roll(_originalDeadline - 100);
    _castVote(PROPOSER, _proposal.id, FOR);
    _castVote(ANON_GNOSIS_SAFE, _proposal.id, FOR);
    _castVote(EVENT_HORIZON, _proposal.id, FOR);
    assertEq(governor.proposalDeadline(_proposal.id), block.number + VOTE_EXTENSION);

    // Thanks to the extension, opposition arriving after the original deadline still counts.
    vm.roll(_originalDeadline + 10);
    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Active);
    _castVote(KEV, _proposal.id, AGAINST);

    vm.roll(governor.proposalDeadline(_proposal.id) + 1);
    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Defeated);
  }

  function test_ProposalSurvivingTheQuorumExtensionSucceedsAndExecutes() external {
    address _receiver = makeAddr("receiver");
    ProposalDetails memory _proposal =
      _buildGtcSendProposal(_receiver, 1000e18, "A proposal surviving its extension");
    _submitProposal(_proposal);
    _jumpToProposalActive(_proposal.id);
    uint256 _originalDeadline = governor.proposalDeadline(_proposal.id);

    vm.roll(_originalDeadline - 100);
    _delegatesCastVotes(_proposal.id, FOR);

    // During the extension the proposal is still Active, so it cannot be queued early.
    vm.roll(_originalDeadline + 10);
    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Active);
    vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
    _queueProposal(_proposal);

    // No opposition materializes, and the proposal completes its journey.
    vm.roll(governor.proposalDeadline(_proposal.id) + 1);
    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Succeeded);
    _queueProposal(_proposal);
    _jumpPastProposalEta(_proposal.id);
    _executeProposal(_proposal);
    assertEq(GTC_TOKEN.balanceOf(_receiver), 1000e18);
  }

  function test_QuorumReachedEarlyDoesNotExtendTheDeadline() external {
    ProposalDetails memory _proposal =
      _buildGtcSendProposal(makeAddr("receiver"), 1000e18, "A proposal reaching quorum early");
    _submitProposal(_proposal);
    _jumpToProposalActive(_proposal.id);
    uint256 _originalDeadline = governor.proposalDeadline(_proposal.id);

    // Quorum is reached at the very start of the voting period, leaving far more than the
    // extension window before the deadline — so the deadline does not move.
    _delegatesCastVotes(_proposal.id, FOR);
    assertEq(governor.proposalDeadline(_proposal.id), _originalDeadline);
  }
}

contract PostUpgradeQuorumBehaviorMainnetScript is PostUpgradeQuorumBehaviorTest {
  function _setUpNetwork() internal override {
    _createMainnetFork();
  }

  function _fetchOrDeploySystem() internal override returns (GitcoinGovernorWithGuardian) {
    return _deployGovernorWithMainnetScript();
  }
}

contract PostUpgradeQuorumBehaviorMainnetDeployed is PostUpgradeQuorumBehaviorTest {
  function _setUpNetwork() internal override {
    _createMainnetGovernorPostDeploymentFork();
  }

  function _fetchOrDeploySystem() internal view override returns (GitcoinGovernorWithGuardian) {
    return _fetchDeployedGovernor();
  }
}
