// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {FranchiserExpiryFactory} from "franchiser-expiry/src/FranchiserExpiryFactory.sol";
import {RecallExpiredFranchisers} from "script/RecallExpiredFranchisers.s.sol";

/// @notice Mainnet configuration for sweeping the Timelock's expired Franchiser positions.
/// Recalling expired positions is permissionless and the tokens always return to the Timelock,
/// so anyone can run this from any account. The delegatee list below is a candidate set — the
/// script recalls only the positions that exist and have expired — so the intended maintenance
/// is to keep every delegatee the DAO has ever funded on the list, appending as delegation
/// rounds add new ones.
contract RecallExpiredFranchisersMainnet is RecallExpiredFranchisers {
  // Fixed value that can't change; the owner of every position the DAO funds.
  address constant TIMELOCK = 0x57a8865cfB1eCEf7253c27da6B4BC3dAEE5Be518;

  // TODO: Set to the FranchiserExpiryFactory address once it is deployed to mainnet. The zero
  // address makes this script revert until then.
  FranchiserExpiryFactory constant FACTORY = FranchiserExpiryFactory(address(0));

  // Boilerplate override so this file declares the public `run()` that scopelint's script rule
  // looks for; the mechanics all live in the base.
  function run() public override {
    super.run();
  }

  function _getRecallParams() internal pure override returns (RecallParams memory) {
    // TODO: List every delegatee the DAO has funded through the factory. The list is filtered
    // on-chain, so keeping delegatees with live or already-swept positions on it is safe and
    // expected. An empty list makes this script revert until it is populated. For example:
    //
    //   address[] memory _delegatees = new address[](1);
    //   _delegatees[0] = 0x0000000000000000000000000000000000000000;
    address[] memory _delegatees = new address[](0);

    return RecallParams({factory: FACTORY, owner: TIMELOCK, delegatees: _delegatees});
  }
}
