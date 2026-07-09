// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {IVotingToken} from "franchiser-expiry/src/interfaces/IVotingToken.sol";
import {DeployFranchiser} from "script/DeployFranchiser.s.sol";

/// @notice Mainnet deployment configuration for the Franchiser system. The only parameter is the
/// GTC token: the factory has no owner, no admin, and nothing else to configure. GTC does not
/// implement the full `IVotingToken` interface the Franchiser contracts declare (it is a
/// COMP-style token), but it exposes every function they actually call — `delegate`, `balanceOf`,
/// `transfer`, `transferFrom`, `allowance`, and `permit` — so the cast below is sound at runtime.
contract DeployFranchiserMainnet is DeployFranchiser {
  // Fixed value that can't change
  IVotingToken constant GTC_TOKEN = IVotingToken(0xDe30da39c46104798bB5aA3fe8B9e0e1F348163F);

  // Boilerplate override so this file declares the public `run()` that scopelint's script rule
  // looks for; the mechanics all live in the base.
  function run() public override {
    super.run();
  }

  function _getDeploymentParams() internal pure override returns (DeploymentParams memory) {
    return DeploymentParams({votingToken: GTC_TOKEN});
  }
}
