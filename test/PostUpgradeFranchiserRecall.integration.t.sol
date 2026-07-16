// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {Franchiser} from "franchiser-expiry/src/Franchiser.sol";
import {FranchiserExpiryFactory} from "franchiser-expiry/src/FranchiserExpiryFactory.sol";
import {FranchiserLens} from "franchiser-expiry/src/FranchiserLens.sol";
import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";
import {PostUpgradeFranchiserTestBase} from "test/helpers/PostUpgradeFranchiserTestBase.sol";
import {
  ProposeFranchiserRecallTestConfig
} from "test/helpers/ProposeFranchiserRecallTestConfig.sol";

// Exercises early recalls after the Governor upgrade: proposals submitted with the real recall
// script that unwind live Franchiser positions before they expire, what that does to the
// delegatee's voting weight, and the limits of who can move the delegated tokens.
abstract contract PostUpgradeFranchiserRecallTest is PostUpgradeFranchiserTestBase {
  function test_PassedRecallProposalReturnsDelegatedTokensAndRemovesTheDelegateesWeight() external {
    address _delegatee = makeAddr("recalledDelegatee");
    uint256 _amount = 500_000e18;
    uint256 _initialTimelockBalance = GTC_TOKEN.balanceOf(address(TIMELOCK));
    _delegateViaProposal(_delegatee, _amount, _safeExpiration());
    if (GTC_TOKEN.getCurrentVotes(_delegatee) != _amount) {
      revert(
        "Test scaffolding: the arranged delegation did not confer the expected weight; the "
        "recall scenario cannot proceed"
      );
    }

    // The DAO unwinds the position early through a full governance proposal.
    _recallViaProposal(_delegatee);

    // The tokens are back in the treasury and the delegatee's conferred weight is gone.
    assertEq(GTC_TOKEN.balanceOf(address(TIMELOCK)), _initialTimelockBalance);
    assertEq(GTC_TOKEN.balanceOf(address(_franchiserFor(_delegatee))), 0);
    assertEq(GTC_TOKEN.getCurrentVotes(_delegatee), 0);
  }

  function test_RecalledDelegateeStillVotesWithSnapshotWeightOnAProposalInFlightDuringTheRecall()
    external
  {
    address _delegatee = makeAddr("rogueDelegatee");
    uint256 _amount = 400_000e18;
    _delegateViaProposal(_delegatee, _amount, _safeExpiration());

    // The recall is submitted first, and an unrelated proposal a few blocks later — timed so the
    // proposal's snapshot lands before the recall executes but its deadline lands after (the
    // Timelock delay passes in timestamps, not blocks).
    ProposalDetails memory _recallRound =
      _submitRecallRound(_asArray(_delegatee), _asArray(address(TIMELOCK)));
    vm.roll(block.number + 10);
    ProposalDetails memory _proposal = _buildGtcSendProposal(
      makeAddr("receiver"), 1000e18, "A proposal in flight while the recall executes"
    );
    _submitProposal(_proposal);

    _passQueueAndExecuteSubmittedProposal(_recallRound);
    _guardProposalState(
      governor.state(_proposal.id),
      IGovernor.ProposalState.Active,
      "the unrelated proposal must still be in its voting window when the recall executes"
    );
    if (GTC_TOKEN.getCurrentVotes(_delegatee) != 0) {
      revert(
        "Test scaffolding: the recall executed but the delegatee still holds current weight; "
        "the arranged recall did not complete"
      );
    }

    // The recall cannot reach weight already snapshotted: the recalled delegatee still votes
    // with the full delegated weight on the in-flight proposal. The DAO's early-recall lever
    // stops future proposals, not ones already underway.
    _castVote(_delegatee, _proposal.id, FOR);
    (, uint256 _forVotes,) = governor.proposalVotes(_proposal.id);
    assertEq(_forVotes, _amount);
  }

  function test_RecallClawsBackTokensTheDelegateeSubDelegated() external {
    address _delegatee = makeAddr("subDelegatingDelegatee");
    address _subDelegatee = makeAddr("subDelegatee");
    uint256 _amount = 600_000e18;
    uint256 _subDelegatedAmount = 200_000e18;
    uint256 _initialTimelockBalance = GTC_TOKEN.balanceOf(address(TIMELOCK));
    _delegateViaProposal(_delegatee, _amount, _safeExpiration());

    // The delegatee sub-delegates part of their position, splitting the voting weight.
    Franchiser _franchiser = _franchiserFor(_delegatee);
    vm.prank(_delegatee);
    Franchiser _subFranchiser = _franchiser.subDelegate(_subDelegatee, _subDelegatedAmount);
    if (
      GTC_TOKEN.getCurrentVotes(_delegatee) != _amount - _subDelegatedAmount
        || GTC_TOKEN.getCurrentVotes(_subDelegatee) != _subDelegatedAmount
        || GTC_TOKEN.balanceOf(address(_subFranchiser)) != _subDelegatedAmount
    ) {
      revert(
        "Test scaffolding: the arranged sub-delegation did not split the position as expected; "
        "the claw-back scenario cannot proceed"
      );
    }

    // The DAO's recall claws back the entire tree, not just the top-level position.
    _recallViaProposal(_delegatee);

    assertEq(GTC_TOKEN.balanceOf(address(TIMELOCK)), _initialTimelockBalance);
    assertEq(GTC_TOKEN.balanceOf(address(_franchiser)), 0);
    assertEq(GTC_TOKEN.balanceOf(address(_subFranchiser)), 0);
    assertEq(GTC_TOKEN.getCurrentVotes(_delegatee), 0);
    assertEq(GTC_TOKEN.getCurrentVotes(_subDelegatee), 0);
  }

  function test_DelegateeCannotPullTokensOutOfTheirFranchiser() external {
    address _delegatee = makeAddr("greedyDelegatee");
    uint256 _amount = 500_000e18;
    _delegateViaProposal(_delegatee, _amount, _safeExpiration());
    Franchiser _franchiser = _franchiserFor(_delegatee);

    // The franchiser's owner is the factory, so even the delegatee cannot recall its tokens to
    // themselves. Sub-delegation is the only power they hold, and it can only move tokens into
    // another franchiser — never out of the system.
    vm.prank(_delegatee);
    vm.expectRevert(bytes("UNAUTHORIZED"));
    _franchiser.recall(_delegatee);

    assertEq(GTC_TOKEN.balanceOf(address(_franchiser)), _amount);
    assertEq(GTC_TOKEN.balanceOf(_delegatee), 0);
  }

  function test_ThirdPartyCannotRecallTheTimelocksPositions() external {
    address _delegatee = makeAddr("stableDelegatee");
    address _attacker = makeAddr("attacker");
    uint256 _amount = 500_000e18;
    _delegateViaProposal(_delegatee, _amount, _safeExpiration());

    // Recall through the factory is keyed to the caller, so an attacker's recall targets their
    // own (nonexistent) position and silently does nothing to the Timelock's.
    vm.prank(_attacker);
    factory.recall(_delegatee, _attacker);

    assertEq(GTC_TOKEN.balanceOf(address(_franchiserFor(_delegatee))), _amount);
    assertEq(GTC_TOKEN.getCurrentVotes(_delegatee), _amount);
    assertEq(GTC_TOKEN.balanceOf(_attacker), 0);
  }

  function test_RecallRoundToANonTimelockRecipientCountsAnOffTreasuryWarning() external {
    address _delegatee = makeAddr("redirectedDelegatee");
    address _offTreasuryRecipient = makeAddr("offTreasuryRecipient");
    _delegateViaProposal(_delegatee, 500_000e18, _safeExpiration());

    // A recipient other than the Timelock is legal, but the script warns the proposer that the
    // recalled tokens leave the treasury. Tests silence logging, so the warning is observed
    // through the script's public counter.
    ProposeFranchiserRecallTestConfig _proposeScript = new ProposeFranchiserRecallTestConfig(
      governor,
      factory,
      PROPOSER,
      _asArray(_delegatee),
      _asArray(_offTreasuryRecipient),
      RECALL_PROPOSAL_DESCRIPTION
    );
    _proposeScript.disableLogging();
    _proposeScript.run();

    assertEq(_proposeScript.offTreasuryRecipientCount(), 1);
  }

  function test_RecallRoundToTheTimelockCountsNoOffTreasuryWarning() external {
    address _delegatee = makeAddr("standardDelegatee");
    _delegateViaProposal(_delegatee, 500_000e18, _safeExpiration());

    ProposeFranchiserRecallTestConfig _proposeScript = new ProposeFranchiserRecallTestConfig(
      governor,
      factory,
      PROPOSER,
      _asArray(_delegatee),
      _asArray(address(TIMELOCK)),
      RECALL_PROPOSAL_DESCRIPTION
    );
    _proposeScript.disableLogging();
    _proposeScript.run();

    assertEq(_proposeScript.offTreasuryRecipientCount(), 0);
  }

  function test_RevertIf_RecallRoundTargetsADelegateeWithNoPosition() external {
    address _delegatee = makeAddr("neverFundedDelegatee");
    ProposeFranchiserRecallTestConfig _proposeScript = new ProposeFranchiserRecallTestConfig(
      governor,
      factory,
      PROPOSER,
      _asArray(_delegatee),
      _asArray(address(TIMELOCK)),
      RECALL_PROPOSAL_DESCRIPTION
    );
    _proposeScript.disableLogging();

    vm.expectRevert(
      bytes(
        string.concat(
          "ProposeFranchiserRecall: no position exists for delegatee ",
          vm.toString(_delegatee),
          "; recalling it would silently do nothing, so remove the entry"
        )
      )
    );
    _proposeScript.run();
  }
}

contract PostUpgradeFranchiserRecallMainnetScript is PostUpgradeFranchiserRecallTest {
  function _setUpNetwork() internal override {
    _createMainnetFork();
  }

  function _fetchOrDeploySystem() internal override returns (GitcoinGovernorWithGuardian) {
    return _deployGovernorWithMainnetScript();
  }

  function _fetchOrDeployFranchiser()
    internal
    override
    returns (FranchiserExpiryFactory, FranchiserLens)
  {
    return _deployFranchiserWithMainnetScript();
  }
}
