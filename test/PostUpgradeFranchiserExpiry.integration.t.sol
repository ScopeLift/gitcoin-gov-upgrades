// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {FranchiserExpiryFactory} from "franchiser-expiry/src/FranchiserExpiryFactory.sol";
import {FranchiserLens} from "franchiser-expiry/src/FranchiserLens.sol";
import {
  IFranchiserExpiryFactoryErrors
} from "franchiser-expiry/src/interfaces/FranchiserExpiryFactory/IFranchiserExpiryFactoryErrors.sol";
import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";
import {FranchiserUpgradeTestBase} from "test/helpers/FranchiserUpgradeTestBase.sol";
import {
  RecallExpiredFranchisersTestConfig
} from "test/helpers/RecallExpiredFranchisersTestConfig.sol";

// Exercises position expiry after the Governor upgrade: the permissionless sweep script
// returning lapsed delegations to the Timelock, what expiry does (and does not do) to voting
// weight, and the guard that keeps live positions out of reach.
abstract contract PostUpgradeFranchiserExpiryTest is FranchiserUpgradeTestBase {
  function test_AnyoneSweepsAnExpiredPositionReturningTokensAndRemovingWeight() external {
    address _delegatee = makeAddr("expiringDelegatee");
    uint256 _amount = 500_000e18;
    uint256 _expiration = _safeExpiration();
    _delegateViaProposal(_delegatee, _amount, _expiration);
    uint256 _timelockBalanceWhileDelegated = GTC_TOKEN.balanceOf(address(TIMELOCK));

    // Time reaches the expiration exactly — the boundary is inclusive, so the position is
    // already sweepable. The sweep script broadcasts from Foundry's default sender, an arbitrary
    // EOA with no special standing.
    vm.warp(_expiration);
    vm.roll(block.number + 1);
    RecallExpiredFranchisersTestConfig _sweepScript = _sweepExpiredPositions(_asArray(_delegatee));

    assertEq(_sweepScript.recalledCount(), 1);
    assertEq(_sweepScript.recalledDelegatees(0), _delegatee);
    assertEq(GTC_TOKEN.balanceOf(address(TIMELOCK)), _timelockBalanceWhileDelegated + _amount);
    assertEq(GTC_TOKEN.balanceOf(address(_franchiserFor(_delegatee))), 0);
    assertEq(GTC_TOKEN.getCurrentVotes(_delegatee), 0);
  }

  function test_ExpiredPositionRetainsVotingWeightUntilSomeoneSweepsIt() external {
    address _delegatee = makeAddr("lingeringDelegatee");
    uint256 _amount = 500_000e18;
    uint256 _expiration = _safeExpiration();
    _delegateViaProposal(_delegatee, _amount, _expiration);

    // Expiry is not self-executing: long after the expiration passes, the delegatee still holds
    // the full delegated weight. Sweeping is a real operational obligation.
    vm.warp(_expiration + 90 days);
    vm.roll(block.number + 1);
    assertEq(GTC_TOKEN.getCurrentVotes(_delegatee), _amount);

    _sweepExpiredPositions(_asArray(_delegatee));
    assertEq(GTC_TOKEN.getCurrentVotes(_delegatee), 0);
  }

  function test_SweepRecallsOnlyExpiredPositionsFromAMixedCandidateList() external {
    // Two positions with different expirations, funded in successive rounds, plus a candidate
    // that was never funded at all.
    address _expiredDelegatee = makeAddr("expiredDelegatee");
    uint256 _expiredAmount = 300_000e18;
    uint256 _earlyExpiration = _safeExpiration();
    _delegateViaProposal(_expiredDelegatee, _expiredAmount, _earlyExpiration);

    address _liveDelegatee = makeAddr("liveDelegatee");
    uint256 _liveAmount = 200_000e18;
    _delegateViaProposal(_liveDelegatee, _liveAmount, _earlyExpiration + 180 days);

    address _neverFunded = makeAddr("neverFundedDelegatee");
    address[] memory _candidates = new address[](3);
    _candidates[0] = _expiredDelegatee;
    _candidates[1] = _liveDelegatee;
    _candidates[2] = _neverFunded;

    vm.warp(_earlyExpiration + 1);
    vm.roll(block.number + 1);
    RecallExpiredFranchisersTestConfig _sweepScript = _sweepExpiredPositions(_candidates);

    // Only the expired position is recalled; the live one keeps its tokens and weight, and the
    // never-funded candidate is skipped harmlessly.
    assertEq(_sweepScript.recalledCount(), 1);
    assertEq(_sweepScript.recalledDelegatees(0), _expiredDelegatee);
    assertEq(GTC_TOKEN.getCurrentVotes(_expiredDelegatee), 0);
    assertEq(GTC_TOKEN.balanceOf(address(_franchiserFor(_liveDelegatee))), _liveAmount);
    assertEq(GTC_TOKEN.getCurrentVotes(_liveDelegatee), _liveAmount);
    assertEq(address(_franchiserFor(_neverFunded)).code.length, 0);
  }

  function test_SweepWithNothingExpiredRecallsNothing() external {
    address _delegatee = makeAddr("freshlyFundedDelegatee");
    uint256 _amount = 500_000e18;
    _delegateViaProposal(_delegatee, _amount, _safeExpiration());
    uint256 _timelockBalanceWhileDelegated = GTC_TOKEN.balanceOf(address(TIMELOCK));

    address[] memory _candidates = new address[](2);
    _candidates[0] = _delegatee;
    _candidates[1] = makeAddr("neverFundedDelegatee");
    RecallExpiredFranchisersTestConfig _sweepScript = _sweepExpiredPositions(_candidates);

    assertEq(_sweepScript.recalledCount(), 0);
    assertEq(GTC_TOKEN.balanceOf(address(TIMELOCK)), _timelockBalanceWhileDelegated);
    assertEq(GTC_TOKEN.balanceOf(address(_franchiserFor(_delegatee))), _amount);
    assertEq(GTC_TOKEN.getCurrentVotes(_delegatee), _amount);
  }

  function test_RevertIf_AnExpiredRecallIsForcedBeforeTheExpiration() external {
    address _delegatee = makeAddr("protectedDelegatee");
    _delegateViaProposal(_delegatee, 500_000e18, _safeExpiration());

    // The factory itself guards live positions: nobody can force an expired-style recall early,
    // no matter who asks.
    vm.prank(makeAddr("impatientKeeper"));
    vm.expectRevert(IFranchiserExpiryFactoryErrors.FranchiserNotExpired.selector);
    factory.recallExpired(address(TIMELOCK), _delegatee);
  }
}

contract PostUpgradeFranchiserExpiryMainnetScript is PostUpgradeFranchiserExpiryTest {
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
