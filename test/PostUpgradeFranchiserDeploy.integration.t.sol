// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {Franchiser} from "franchiser-expiry/src/Franchiser.sol";
import {FranchiserExpiryFactory} from "franchiser-expiry/src/FranchiserExpiryFactory.sol";
import {FranchiserLens} from "franchiser-expiry/src/FranchiserLens.sol";
import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";
import {FranchiserUpgradeTestBase} from "test/helpers/FranchiserUpgradeTestBase.sol";

// Exercises the Franchiser deployment after the Governor upgrade has executed: the system the
// deploy script produces is wired to GTC, internally consistent, and coherent with the Governor
// that will administer it.
abstract contract PostUpgradeFranchiserDeployTest is FranchiserUpgradeTestBase {
  function test_DeployedFranchiserSystemIsWiredToGtcAndInternallyConsistent() external view {
    // The factory sources the same token the Governor sources voting weight from.
    assertEq(address(factory.votingToken()), address(GTC_TOKEN));
    assertEq(address(factory.votingToken()), address(governor.token()));

    // The factory deployed a canonical Franchiser implementation wired to the same token, with
    // the expected sub-delegation shape.
    Franchiser _implementation = factory.franchiserImplementation();
    assertGt(address(_implementation).code.length, 0);
    assertEq(address(_implementation.votingToken()), address(GTC_TOKEN));
    assertEq(factory.INITIAL_MAXIMUM_SUBDELEGATEES(), 8);

    // The lens reads through the same token and factory.
    assertEq(address(lens.votingToken()), address(GTC_TOKEN));
    assertEq(address(lens.franchiserFactory()), address(factory));
  }

  function test_FreshlyDeployedFactoryHoldsNoPositionForTheTimelock() external {
    // Position addresses are deterministic before they exist; none exists until the DAO's first
    // delegation round funds one.
    Franchiser _franchiser = _franchiserFor(makeAddr("someDelegatee"));
    assertNotEq(address(_franchiser), address(0));
    assertEq(address(_franchiser).code.length, 0);
    assertEq(factory.expirations(_franchiser), 0);
  }
}

contract PostUpgradeFranchiserDeployMainnetScript is PostUpgradeFranchiserDeployTest {
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
