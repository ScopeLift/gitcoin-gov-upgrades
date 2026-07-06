// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";
import {GitcoinGovernorUpgradeTestBase} from "test/helpers/GitcoinGovernorUpgradeTestBase.sol";

// Exercises the upgrade itself: the new Governor is deployed by the real deploy script, and the
// upgrade proposal — submitted to the old Governor by the real proposal script — is walked
// through passing, failing, and post-upgrade outcomes for control of the Timelock.
abstract contract GovernorUpgradeProposalTest is GitcoinGovernorUpgradeTestBase {
  function test_DeploysTheNewGovernorWithTheMainnetConfiguration() external view {
    assertEq(governor.name(), "GTC Governor Bravo");
    assertEq(address(governor.token()), address(GTC_TOKEN));
    assertEq(governor.timelock(), address(TIMELOCK));
    // These values mirror the active Governor, read from mainnet when the tests were written.
    assertEq(governor.votingDelay(), 13_140);
    assertEq(governor.votingPeriod(), 40_320);
    assertEq(governor.proposalThreshold(), 150_000e18);
    assertEq(governor.quorum(block.number), QUORUM);
    assertEq(governor.lateQuorumVoteExtension(), VOTE_EXTENSION);
    // The placeholder guardian from the mainnet deploy config; update this assertion when the
    // security-council guardian address is confirmed.
    assertEq(governor.proposalGuardian(), address(TIMELOCK));
    assertEq(
      governor.COUNTING_MODE(), "support=bravo,fractional&quorum=for,abstain&params=fractional"
    );
    assertEq(governor.CLOCK_MODE(), "mode=blocknumber&from=default");
    assertEq(governor.clock(), block.number);
  }

  function test_GivenProposalRequiresQueuingThroughTheTimelock() external {
    // The new Governor executes exclusively through the Compound Timelock, so every proposal
    // reports that it needs queuing. The Governor's proposalNeedsQueuing override exists only to
    // resolve inheritance ambiguity; this pins the behavior it preserves.
    ProposalDetails memory _proposal =
      _buildGtcSendProposal(makeAddr("receiver"), 1000e18, "A proposal that must be queued");
    _submitProposal(_proposal);
    assertTrue(governor.proposalNeedsQueuing(_proposal.id));

    // The answer is structural rather than per-proposal: it holds even for ids no proposal has.
    assertTrue(governor.proposalNeedsQueuing(type(uint256).max));
  }

  function test_SubmitsTheUpgradeProposalWithTheExpectedActions() external {
    _submitUpgradeProposal();

    // The id the old Governor assigned matches the id computed from the actions the proposal is
    // expected to carry, proving the script proposed exactly the setPendingAdmin + __acceptAdmin
    // pair targeting this deployment.
    assertEq(upgradeProposalId, _upgradeProposalDetails().id);
    assertEq(OLD_GOVERNOR.state(upgradeProposalId), IGovernor.ProposalState.Pending);
    assertGt(OLD_GOVERNOR.proposalSnapshot(upgradeProposalId), block.number);
  }

  function test_PassedUpgradeProposalTransfersTimelockControlToTheNewGovernor() external {
    _submitUpgradeProposal();

    // The electorate passes the proposal.
    _passUpgradeProposal();
    assertEq(OLD_GOVERNOR.state(upgradeProposalId), IGovernor.ProposalState.Succeeded);

    // Queuing places both upgrade actions in the Timelock.
    _queueUpgradeProposal();
    assertEq(OLD_GOVERNOR.state(upgradeProposalId), IGovernor.ProposalState.Queued);
    ProposalDetails memory _proposal = _upgradeProposalDetails();
    uint256 _eta = OLD_GOVERNOR.proposalEta(upgradeProposalId);
    for (uint256 _index = 0; _index < _proposal.targets.length; _index += 1) {
      assertTrue(
        TIMELOCK.queuedTransactions(
          _timelockTransactionHash(
            _proposal.targets[_index], _proposal.values[_index], _proposal.calldatas[_index], _eta
          )
        )
      );
    }

    // After the Timelock delay elapses, execution hands the admin role to the new Governor.
    _jumpPastUpgradeProposalEta();
    _executeUpgradeProposal();
    assertEq(OLD_GOVERNOR.state(upgradeProposalId), IGovernor.ProposalState.Executed);
    assertEq(TIMELOCK.admin(), address(governor));
    assertEq(TIMELOCK.pendingAdmin(), address(0));
  }

  function test_DefeatedUpgradeProposalLeavesTheOldGovernorGoverning() external {
    _submitUpgradeProposal();

    // The electorate votes the upgrade down.
    _defeatUpgradeProposal();
    assertEq(OLD_GOVERNOR.state(upgradeProposalId), IGovernor.ProposalState.Defeated);
    vm.expectRevert("Governor: proposal not successful");
    _queueUpgradeProposal();
    assertEq(TIMELOCK.admin(), address(OLD_GOVERNOR));

    // The old Governor still governs: a follow-up proposal moves ETH the Timelock really holds.
    address _receiver = makeAddr("receiver");
    uint256 _amount = 1 ether;
    uint256 _initialTimelockBalance = address(TIMELOCK).balance;
    ProposalDetails memory _ethSend =
      _buildProposal(_receiver, _amount, "", "Send ETH via the old Governor");
    _submitAndPassProposalOnOldGovernor(_ethSend);
    _queueAndExecuteProposalOnOldGovernor(_ethSend);
    assertEq(_receiver.balance, _amount);
    assertEq(address(TIMELOCK).balance, _initialTimelockBalance - _amount);
  }

  function test_OldGovernorCannotQueueProposalsAfterTheUpgradeExecutes() external {
    _upgradeToNewGovernor();

    // A proposal still passes a vote on the old Governor, but the Timelock no longer accepts its
    // instructions.
    ProposalDetails memory _proposal =
      _buildGtcSendProposal(makeAddr("receiver"), 1000e18, "Send GTC via the deposed Governor");
    _submitAndPassProposalOnOldGovernor(_proposal);
    vm.expectRevert("Timelock::queueTransaction: Call must come from admin.");
    OLD_GOVERNOR.queue(
      _proposal.targets,
      _proposal.values,
      _proposal.calldatas,
      keccak256(bytes(_proposal.description))
    );
  }

  function test_VotesOnTheOldGovernorDoNotCarryToTheNewGovernor() external {
    _upgradeToNewGovernor();

    // The same action is proposed on both governors. Their proposal ids are computed identically,
    // so this exercises that state is fully separate between the two contracts.
    address _receiver = makeAddr("receiver");
    ProposalDetails memory _proposal =
      _buildGtcSendProposal(_receiver, 1000e18, "Send GTC after the upgrade");
    _submitProposalToOldGovernor(_proposal);
    _submitProposal(_proposal);

    // Pass the proposal on the old Governor while defeating it on the new one.
    _jumpToProposalActive(_proposal.id);
    _delegatesCastVotesOnOldGovernor(_proposal.id, FOR);
    _delegatesCastVotes(_proposal.id, AGAINST);
    _jumpPastProposalDeadline(_proposal.id);

    // The new Governor's proposal is defeated by its own tally, unaffected by the old one's.
    assertEq(OLD_GOVERNOR.state(_proposal.id), IGovernor.ProposalState.Succeeded);
    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Defeated);
    vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
    _queueProposal(_proposal);
    assertEq(GTC_TOKEN.balanceOf(_receiver), 0);
  }
}

contract GovernorUpgradeProposalMainnetScript is GovernorUpgradeProposalTest {
  function _setUpNetwork() internal override {
    _createMainnetFork();
  }

  function _fetchOrDeploySystem() internal override returns (GitcoinGovernorWithGuardian) {
    return _deployGovernorWithMainnetScript();
  }
}
