// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {Franchiser} from "franchiser-expiry/src/Franchiser.sol";
import {FranchiserExpiryFactory} from "franchiser-expiry/src/FranchiserExpiryFactory.sol";
import {FranchiserLens} from "franchiser-expiry/src/FranchiserLens.sol";
import {IFranchiserLens} from "franchiser-expiry/src/interfaces/IFranchiserLens.sol";
import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";
import {PostUpgradeFranchiserTestBase} from "test/helpers/PostUpgradeFranchiserTestBase.sol";
import {
  ProposeFranchiserDelegationTestConfig
} from "test/helpers/ProposeFranchiserDelegationTestConfig.sol";

// Exercises delegation rounds after the Governor upgrade: proposals submitted with the real
// delegation script that move treasury GTC from the Timelock into Franchiser positions, and the
// voting weight those positions confer on their delegatees.
abstract contract PostUpgradeFranchiserDelegationTest is PostUpgradeFranchiserTestBase {
  function test_PassedDelegationProposalFundsAFreshDelegateeWhoVotesWithTheDelegatedWeight()
    external
  {
    address _delegatee = makeAddr("freshDelegatee");
    uint256 _amount = 500_000e18;
    uint256 _expiration = _safeExpiration();
    uint256 _initialTimelockBalance = GTC_TOKEN.balanceOf(address(TIMELOCK));
    if (GTC_TOKEN.getCurrentVotes(_delegatee) != 0) {
      revert(
        "Test scaffolding: the fresh delegatee already has voting weight; the fresh-funding "
        "scenario needs a delegatee with none"
      );
    }

    // The DAO delegates treasury GTC to the fresh delegatee through a full governance proposal.
    _delegateViaProposal(_delegatee, _amount, _expiration);

    // The tokens sit in the delegatee's Franchiser, delegated to them, and the Timelock's
    // one-proposal approval of the factory is fully consumed.
    Franchiser _franchiser = _franchiserFor(_delegatee);
    assertEq(GTC_TOKEN.balanceOf(address(_franchiser)), _amount);
    assertEq(GTC_TOKEN.balanceOf(address(TIMELOCK)), _initialTimelockBalance - _amount);
    assertEq(GTC_TOKEN.allowance(address(TIMELOCK), address(factory)), 0);
    assertEq(GTC_TOKEN.getCurrentVotes(_delegatee), _amount);
    assertEq(factory.expirations(_franchiser), _expiration);

    // The delegatee votes on a new proposal, and the tally reflects the delegated weight.
    ProposalDetails memory _proposal = _buildGtcSendProposal(
      makeAddr("receiver"), 1000e18, "A proposal the newly franchised delegate votes on"
    );
    _submitProposal(_proposal);
    _jumpToProposalActive(_proposal.id);
    _castVote(_delegatee, _proposal.id, FOR);
    (, uint256 _forVotes,) = governor.proposalVotes(_proposal.id);
    assertEq(_forVotes, _amount);
  }

  /// forge-config: default.fuzz.runs = 25
  /// forge-config: ci.fuzz.runs = 25
  /// forge-config: lite.fuzz.runs = 5
  function testFuzz_PassedDelegationProposalFundsAFreshDelegateeWithAnyTreasuryAmount(
    uint256 _amount,
    uint256 _expiration
  ) external {
    // The round draws on the GTC the Timelock genuinely holds at the fork block, and any
    // expiration the delegation script accepts is exercised.
    _amount = bound(_amount, 1, GTC_TOKEN.balanceOf(address(TIMELOCK)));
    _expiration = bound(_expiration, _minimumExpiration(), _minimumExpiration() + 3650 days);
    address _delegatee = makeAddr("freshDelegatee");
    uint256 _initialTimelockBalance = GTC_TOKEN.balanceOf(address(TIMELOCK));

    _delegateViaProposal(_delegatee, _amount, _expiration);

    Franchiser _franchiser = _franchiserFor(_delegatee);
    assertEq(GTC_TOKEN.balanceOf(address(_franchiser)), _amount);
    assertEq(GTC_TOKEN.balanceOf(address(TIMELOCK)), _initialTimelockBalance - _amount);
    assertEq(GTC_TOKEN.getCurrentVotes(_delegatee), _amount);
    assertEq(factory.expirations(_franchiser), _expiration);
  }

  function test_PassedDelegationProposalStacksWeightOnADelegateeWithExistingTokenDelegation()
    external
  {
    // lefteris.eth already holds real delegated weight at the fork block; a Franchiser
    // delegation stacks on top of it.
    uint256 _initialWeight = GTC_TOKEN.getCurrentVotes(LEFTERIS);
    if (_initialWeight == 0) {
      revert(
        "Test scaffolding: lefteris.eth has no delegated weight at FORK_BLOCK; pick a delegate "
        "with existing weight for the stacking scenario"
      );
    }
    uint256 _amount = 250_000e18;

    _delegateViaProposal(LEFTERIS, _amount, _safeExpiration());

    assertEq(GTC_TOKEN.getCurrentVotes(LEFTERIS), _initialWeight + _amount);

    // Their vote on a new proposal carries the combined weight.
    ProposalDetails memory _proposal = _buildGtcSendProposal(
      makeAddr("receiver"), 1000e18, "A proposal an already-delegated delegate votes on"
    );
    _submitProposal(_proposal);
    _jumpToProposalActive(_proposal.id);
    _castVote(LEFTERIS, _proposal.id, FOR);
    (, uint256 _forVotes,) = governor.proposalVotes(_proposal.id);
    assertEq(_forVotes, _initialWeight + _amount);
  }

  function test_SingleDelegationProposalFundsMultipleDelegateesInOneRound() external {
    address[] memory _delegatees = new address[](3);
    uint256[] memory _amounts = new uint256[](3);
    _delegatees[0] = makeAddr("firstFreshDelegatee");
    _amounts[0] = 100_000e18;
    _delegatees[1] = makeAddr("secondFreshDelegatee");
    _amounts[1] = 200_000e18;
    _delegatees[2] = LEFTERIS;
    _amounts[2] = 50_000e18;
    uint256 _initialLefterisWeight = GTC_TOKEN.getCurrentVotes(LEFTERIS);
    uint256 _initialTimelockBalance = GTC_TOKEN.balanceOf(address(TIMELOCK));
    uint256 _expiration = _safeExpiration();

    _delegateViaProposal(_delegatees, _amounts, _expiration);

    // Every position is funded from the single round, fresh and existing delegatees alike.
    assertEq(GTC_TOKEN.getCurrentVotes(_delegatees[0]), _amounts[0]);
    assertEq(GTC_TOKEN.getCurrentVotes(_delegatees[1]), _amounts[1]);
    assertEq(GTC_TOKEN.getCurrentVotes(LEFTERIS), _initialLefterisWeight + _amounts[2]);
    for (uint256 _index = 0; _index < _delegatees.length; _index += 1) {
      Franchiser _franchiser = _franchiserFor(_delegatees[_index]);
      assertEq(GTC_TOKEN.balanceOf(address(_franchiser)), _amounts[_index]);
      assertEq(factory.expirations(_franchiser), _expiration);
    }
    assertEq(
      GTC_TOKEN.balanceOf(address(TIMELOCK)),
      _initialTimelockBalance - _amounts[0] - _amounts[1] - _amounts[2]
    );
    assertEq(GTC_TOKEN.allowance(address(TIMELOCK), address(factory)), 0);
  }

  function test_SecondDelegationRoundTopsUpAPositionAndReplacesItsExpirationWithAnEarlierOne()
    external
  {
    address _delegatee = makeAddr("renewedDelegatee");
    uint256 _firstAmount = 300_000e18;
    uint256 _firstExpiration = _safeExpiration() + 90 days;
    _delegateViaProposal(_delegatee, _firstAmount, _firstExpiration);
    Franchiser _franchiser = _franchiserFor(_delegatee);

    // The second round tops the position up with an expiration earlier than the first: funding
    // overwrites a live position's expiration in either direction.
    uint256 _secondAmount = 200_000e18;
    uint256 _secondExpiration = _safeExpiration();
    if (_secondExpiration >= _firstExpiration) {
      revert(
        "Test scaffolding: the second round's expiration no longer lands before the first's; "
        "the 90-day buffer no longer outruns the proposal pipeline, so widen it"
      );
    }
    _delegateViaProposal(_delegatee, _secondAmount, _secondExpiration);

    // The same clone is reused, the balances add, and the new (earlier) expiration governs.
    assertEq(address(_franchiserFor(_delegatee)), address(_franchiser));
    assertEq(GTC_TOKEN.balanceOf(address(_franchiser)), _firstAmount + _secondAmount);
    assertEq(GTC_TOKEN.getCurrentVotes(_delegatee), _firstAmount + _secondAmount);
    assertEq(factory.expirations(_franchiser), _secondExpiration);
  }

  function test_ZeroAmountDelegationRoundExtendsAPositionsExpirationWithoutMovingTokens() external {
    address _delegatee = makeAddr("extendedDelegatee");
    uint256 _amount = 400_000e18;
    uint256 _firstExpiration = _safeExpiration();
    _delegateViaProposal(_delegatee, _amount, _firstExpiration);
    Franchiser _franchiser = _franchiserFor(_delegatee);
    uint256 _timelockBalanceAfterFunding = GTC_TOKEN.balanceOf(address(TIMELOCK));

    // A zero-amount round against the live position adjusts its expiration alone.
    uint256 _secondExpiration = _firstExpiration + 365 days;
    _delegateViaProposal(_delegatee, 0, _secondExpiration);

    assertEq(factory.expirations(_franchiser), _secondExpiration);
    assertEq(GTC_TOKEN.balanceOf(address(_franchiser)), _amount);
    assertEq(GTC_TOKEN.getCurrentVotes(_delegatee), _amount);
    assertEq(GTC_TOKEN.balanceOf(address(TIMELOCK)), _timelockBalanceAfterFunding);
  }

  function test_DelegationExecutedAfterAProposalSnapshotDoesNotCountOnThatProposal() external {
    address _delegatee = makeAddr("lateDelegatee");
    uint256 _amount = 400_000e18;

    // The delegation round is submitted first, and an unrelated proposal a few blocks later —
    // timed so the proposal's snapshot lands before the round executes but its deadline lands
    // after (the Timelock delay passes in timestamps, not blocks).
    ProposalDetails memory _round =
      _submitDelegationRound(_asArray(_delegatee), _asArray(_amount), _safeExpiration());
    vm.roll(block.number + 10);
    ProposalDetails memory _proposal = _buildGtcSendProposal(
      makeAddr("receiver"), 1000e18, "A proposal snapshotted before the delegation lands"
    );
    _submitProposal(_proposal);

    _passQueueAndExecuteSubmittedProposal(_round);
    _guardProposalState(
      governor.state(_proposal.id),
      IGovernor.ProposalState.Active,
      "the unrelated proposal must still be in its voting window when the delegation round "
      "executes"
    );

    // The delegatee has the weight now, but had none at the proposal's snapshot...
    assertEq(GTC_TOKEN.getCurrentVotes(_delegatee), _amount);
    assertEq(GTC_TOKEN.getPriorVotes(_delegatee, governor.proposalSnapshot(_proposal.id)), 0);

    // ...so the Governor rejects their vote on it outright.
    vm.prank(_delegatee);
    vm.expectPartialRevert(IGovernor.GovernorAlreadyCastVote.selector);
    governor.castVote(_proposal.id, FOR);
  }

  function test_DefeatedDelegationProposalMovesNoTokensAndCreatesNoPosition() external {
    address _delegatee = makeAddr("rejectedDelegatee");
    uint256 _initialTimelockBalance = GTC_TOKEN.balanceOf(address(TIMELOCK));

    // The electorate votes the round down.
    ProposalDetails memory _round =
      _submitDelegationRound(_asArray(_delegatee), _asArray(500_000e18), _safeExpiration());
    _jumpToProposalActive(_round.id);
    _delegatesCastVotes(_round.id, AGAINST);
    _jumpPastProposalDeadline(_round.id);
    assertEq(governor.state(_round.id), IGovernor.ProposalState.Defeated);

    vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
    _queueProposal(_round);

    // Nothing moved: no position exists, no weight was conferred, no approval lingers.
    assertEq(address(_franchiserFor(_delegatee)).code.length, 0);
    assertEq(GTC_TOKEN.getCurrentVotes(_delegatee), 0);
    assertEq(GTC_TOKEN.balanceOf(address(TIMELOCK)), _initialTimelockBalance);
    assertEq(GTC_TOKEN.allowance(address(TIMELOCK), address(factory)), 0);
  }

  function test_LensReportsTheRootDelegationForAFundedPosition() external {
    address _delegatee = makeAddr("observedDelegatee");
    _delegateViaProposal(_delegatee, 100_000e18, _safeExpiration());

    Franchiser _franchiser = _franchiserFor(_delegatee);
    IFranchiserLens.Delegation memory _delegation = lens.getRootDelegation(_franchiser);
    assertEq(_delegation.delegator, address(TIMELOCK));
    assertEq(_delegation.delegatee, _delegatee);
    assertEq(address(_delegation.franchiser), address(_franchiser));
  }

  function test_RevertIf_DelegationRoundExpirationDoesNotOutliveTheProposalPipeline() external {
    uint256 _expiration = _minimumExpiration() - 1;
    ProposeFranchiserDelegationTestConfig _proposeScript = new ProposeFranchiserDelegationTestConfig(
      governor,
      factory,
      PROPOSER,
      _asArray(makeAddr("delegatee")),
      _asArray(uint256(100_000e18)),
      _expiration,
      DELEGATION_PROPOSAL_DESCRIPTION
    );
    _proposeScript.disableLogging();

    vm.expectRevert(
      bytes(
        string.concat(
          "ProposeFranchiserDelegation: the expiration ",
          vm.toString(_expiration),
          " is too soon; it must be at least ",
          vm.toString(_minimumExpiration()),
          " so the positions cannot expire before the proposal's last legitimate execution time"
        )
      )
    );
    _proposeScript.run();
  }

  function test_RevertIf_DelegationRoundRepeatsADelegatee() external {
    address _delegatee = makeAddr("repeatedDelegatee");
    address[] memory _delegatees = new address[](2);
    uint256[] memory _amounts = new uint256[](2);
    _delegatees[0] = _delegatee;
    _amounts[0] = 100_000e18;
    _delegatees[1] = _delegatee;
    _amounts[1] = 200_000e18;
    ProposeFranchiserDelegationTestConfig _proposeScript = new ProposeFranchiserDelegationTestConfig(
      governor,
      factory,
      PROPOSER,
      _delegatees,
      _amounts,
      _safeExpiration(),
      DELEGATION_PROPOSAL_DESCRIPTION
    );
    _proposeScript.disableLogging();

    vm.expectRevert(
      bytes(
        string.concat(
          "ProposeFranchiserDelegation: the delegatee ",
          vm.toString(_delegatee),
          " appears more than once; combine their amounts into a single entry"
        )
      )
    );
    _proposeScript.run();
  }

  function test_RevertIf_DelegationRoundSendsZeroToADelegateeWithNoPosition() external {
    address _delegatee = makeAddr("neverFundedDelegatee");
    ProposeFranchiserDelegationTestConfig _proposeScript = new ProposeFranchiserDelegationTestConfig(
      governor,
      factory,
      PROPOSER,
      _asArray(_delegatee),
      _asArray(uint256(0)),
      _safeExpiration(),
      DELEGATION_PROPOSAL_DESCRIPTION
    );
    _proposeScript.disableLogging();

    vm.expectRevert(
      bytes(
        string.concat(
          "ProposeFranchiserDelegation: the amount for delegatee ",
          vm.toString(_delegatee),
          " is zero but they have no existing position; a zero amount is only meaningful as "
          "an expiration adjustment to an existing position"
        )
      )
    );
    _proposeScript.run();
  }
}

contract PostUpgradeFranchiserDelegationMainnetScript is PostUpgradeFranchiserDelegationTest {
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
