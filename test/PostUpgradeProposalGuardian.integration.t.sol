// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";
import {GitcoinGovernorPostUpgradeTestBase} from "test/helpers/GitcoinGovernorUpgradeTestBase.sol";

// Exercises the Proposal Guardian after the upgrade: the guardian cancelling proposals at every
// cancelable stage of their lifecycle, the boundaries of that power, and the DAO replacing the
// guardian by governance.
abstract contract PostUpgradeProposalGuardianTest is GitcoinGovernorPostUpgradeTestBase {
  address receiver;

  function setUp() public virtual override {
    super.setUp();
    receiver = makeAddr("receiver");
  }

  // The send amount draws on GTC the Timelock genuinely holds (floor-guarded in the base setUp).
  function _submitGtcSendProposal() internal returns (ProposalDetails memory _proposal) {
    _proposal = _buildGtcSendProposal(receiver, 1000e18, "A proposal the guardian assesses");
    _submitProposal(_proposal);
  }

  function _guardianCancels(ProposalDetails memory _proposal) internal {
    vm.prank(governor.proposalGuardian());
    governor.cancel(
      _proposal.targets,
      _proposal.values,
      _proposal.calldatas,
      keccak256(bytes(_proposal.description))
    );
  }

  function test_GuardianCancelsAPendingProposal() external {
    ProposalDetails memory _proposal = _submitGtcSendProposal();

    _guardianCancels(_proposal);

    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Canceled);
    // The canceled proposal is dead: voting never opens and it cannot be queued.
    vm.roll(governor.proposalSnapshot(_proposal.id) + 1);
    vm.prank(delegates[0]);
    vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
    governor.castVote(_proposal.id, FOR);
    vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
    _queueProposal(_proposal);
  }

  function test_GuardianCancelsAnActiveProposalMidVote() external {
    ProposalDetails memory _proposal = _submitGtcSendProposal();
    _jumpToProposalActive(_proposal.id);
    _delegatesCastVotes(_proposal.id, FOR);

    _guardianCancels(_proposal);

    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Canceled);
    _jumpPastProposalDeadline(_proposal.id);
    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Canceled);
    vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
    _queueProposal(_proposal);
  }

  function test_GuardianCancelsASucceededProposalBeforeItIsQueued() external {
    ProposalDetails memory _proposal = _submitGtcSendProposal();
    _passSubmittedProposal(_proposal);

    _guardianCancels(_proposal);

    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Canceled);
    vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
    _queueProposal(_proposal);
  }

  function test_GuardianCancelsADefeatedProposal() external {
    ProposalDetails memory _proposal = _submitGtcSendProposal();
    _jumpToProposalActive(_proposal.id);
    _delegatesCastVotes(_proposal.id, AGAINST);
    _jumpPastProposalDeadline(_proposal.id);
    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Defeated);

    _guardianCancels(_proposal);

    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Canceled);
  }

  function test_GuardianCancelsAQueuedProposalAndItsTimelockTransactionsAreRemoved() external {
    ProposalDetails memory _proposal = _submitGtcSendProposal();
    _passSubmittedProposal(_proposal);
    _queueProposal(_proposal);
    uint256 _eta = governor.proposalEta(_proposal.id);
    bytes32 _timelockHash = _timelockTransactionHash(
      _proposal.targets[0], _proposal.values[0], _proposal.calldatas[0], _eta
    );
    assertTrue(TIMELOCK.queuedTransactions(_timelockHash));

    _guardianCancels(_proposal);

    // Cancellation reaches through the Governor into the Timelock: the queued transaction is
    // gone and the proposal can no longer be executed.
    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Canceled);
    assertFalse(TIMELOCK.queuedTransactions(_timelockHash));
    _jumpPastProposalEta(_proposal.id);
    vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
    _executeProposal(_proposal);
    assertEq(GTC_TOKEN.balanceOf(receiver), 0);
  }

  function test_GuardianCannotCancelAnExecutedProposal() external {
    ProposalDetails memory _proposal = _submitGtcSendProposal();
    _passSubmittedProposal(_proposal);
    _queueProposal(_proposal);
    _jumpPastProposalEta(_proposal.id);
    _executeProposal(_proposal);
    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Executed);

    vm.prank(governor.proposalGuardian());
    vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
    governor.cancel(
      _proposal.targets,
      _proposal.values,
      _proposal.calldatas,
      keccak256(bytes(_proposal.description))
    );
    assertEq(GTC_TOKEN.balanceOf(receiver), 1000e18);
  }

  function test_AccountThatIsNeitherGuardianNorProposerCannotCancel() external {
    ProposalDetails memory _proposal = _submitGtcSendProposal();

    vm.prank(makeAddr("rando"));
    vm.expectPartialRevert(IGovernor.GovernorUnableToCancel.selector);
    governor.cancel(
      _proposal.targets,
      _proposal.values,
      _proposal.calldatas,
      keccak256(bytes(_proposal.description))
    );
  }

  function test_ProposerCancelsTheirOwnProposalWhilePending() external {
    ProposalDetails memory _proposal = _submitGtcSendProposal();

    vm.prank(PROPOSER);
    governor.cancel(
      _proposal.targets,
      _proposal.values,
      _proposal.calldatas,
      keccak256(bytes(_proposal.description))
    );

    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Canceled);
  }

  function test_ProposerCannotCancelTheirOwnProposalOnceVotingStarts() external {
    ProposalDetails memory _proposal = _submitGtcSendProposal();
    _jumpToProposalActive(_proposal.id);

    // With a guardian configured, the proposer's cancel power is limited to the Pending state.
    vm.prank(PROPOSER);
    vm.expectPartialRevert(IGovernor.GovernorUnableToCancel.selector);
    governor.cancel(
      _proposal.targets,
      _proposal.values,
      _proposal.calldatas,
      keccak256(bytes(_proposal.description))
    );
  }

  function test_DaoReplacesTheProposalGuardianViaProposal() external {
    address _oldGuardian = governor.proposalGuardian();
    address _newGuardian = makeAddr("newGuardian");
    ProposalDetails memory _replaceGuardian = _buildProposal(
      address(governor),
      0,
      abi.encodeCall(governor.setProposalGuardian, (_newGuardian)),
      "Hand the guardian role to a new address"
    );
    _submitPassQueueAndExecuteProposal(_replaceGuardian);
    assertEq(governor.proposalGuardian(), _newGuardian);

    // The deposed guardian has no cancel power over new proposals; the new guardian does.
    ProposalDetails memory _proposal = _submitGtcSendProposal();
    vm.prank(_oldGuardian);
    vm.expectPartialRevert(IGovernor.GovernorUnableToCancel.selector);
    governor.cancel(
      _proposal.targets,
      _proposal.values,
      _proposal.calldatas,
      keccak256(bytes(_proposal.description))
    );

    vm.prank(_newGuardian);
    governor.cancel(
      _proposal.targets,
      _proposal.values,
      _proposal.calldatas,
      keccak256(bytes(_proposal.description))
    );
    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Canceled);
  }

  // Advances an already-submitted proposal to Succeeded (the base's _submitAndPassProposal
  // helper both submits and passes, which would double-submit here).
  function _passSubmittedProposal(ProposalDetails memory _proposal) internal {
    _jumpToProposalActive(_proposal.id);
    _delegatesCastVotes(_proposal.id, FOR);
    _jumpPastProposalDeadline(_proposal.id);
    _guardProposalState(
      governor.state(_proposal.id),
      IGovernor.ProposalState.Succeeded,
      "after the electorate voted the guardian-assessed proposal through"
    );
  }
}

contract PostUpgradeProposalGuardianMainnetScript is PostUpgradeProposalGuardianTest {
  function _setUpNetwork() internal override {
    _createMainnetFork();
  }

  function _fetchOrDeploySystem() internal override returns (GitcoinGovernorWithGuardian) {
    return _deployGovernorWithMainnetScript();
  }
}
