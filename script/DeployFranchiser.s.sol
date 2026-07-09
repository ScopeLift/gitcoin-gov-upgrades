// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {FranchiserExpiryFactory} from "franchiser-expiry/src/FranchiserExpiryFactory.sol";
import {FranchiserLens} from "franchiser-expiry/src/FranchiserLens.sol";
import {IVotingToken} from "franchiser-expiry/src/interfaces/IVotingToken.sol";

/// @notice Abstract base that holds the mechanics of deploying the Franchiser system: the
/// `FranchiserExpiryFactory` (whose constructor also deploys the canonical `Franchiser`
/// implementation it clones) and the read-only `FranchiserLens` for inspecting delegations.
/// A concrete contract supplies the configuration for a specific deployment by implementing
/// `_getDeploymentParams`.
abstract contract DeployFranchiser is Script {
  struct DeploymentParams {
    IVotingToken votingToken;
  }

  FranchiserExpiryFactory public factory;
  FranchiserLens public lens;
  bool internal isLogging = true;

  function run() public virtual {
    DeploymentParams memory _params = _getDeploymentParams();
    _revertIfDeploymentParamsAreInvalid(_params);

    _log("Deploying the Franchiser system with:");
    _log(string.concat("  votingToken: ", vm.toString(address(_params.votingToken))));

    vm.startBroadcast();
    // BROADCAST: deploy the FranchiserExpiryFactory (its constructor also deploys the canonical
    // Franchiser implementation that all positions are cloned from)
    _log("[1/2] Deploying FranchiserExpiryFactory");
    factory = new FranchiserExpiryFactory(_params.votingToken);
    // BROADCAST: deploy the FranchiserLens wired to the factory
    _log("[2/2] Deploying FranchiserLens");
    lens = new FranchiserLens(_params.votingToken, factory);
    vm.stopBroadcast();

    _log(string.concat("FranchiserExpiryFactory deployed at ", vm.toString(address(factory))));
    _log(
      string.concat(
        "Franchiser implementation deployed at ",
        vm.toString(address(factory.franchiserImplementation()))
      )
    );
    _log(string.concat("FranchiserLens deployed at ", vm.toString(address(lens))));

    _revertIfDeploymentIsInvalid(_params);
  }

  function disableLogging() public {
    isLogging = false;
  }

  function _getDeploymentParams() internal view virtual returns (DeploymentParams memory);

  function _log(string memory _msg) internal view {
    if (isLogging) {
      console2.log(_msg);
    }
  }

  function _revertIfDeploymentParamsAreInvalid(DeploymentParams memory _params) internal view {
    if (address(_params.votingToken) == address(0)) {
      revert(
        "DeployFranchiser: votingToken is the zero address; "
        "set it to the address of the COMP-style GTC token"
      );
    }
    if (address(_params.votingToken).code.length == 0) {
      revert(
        string.concat(
          "DeployFranchiser: votingToken ",
          vm.toString(address(_params.votingToken)),
          " has no code on this network; check the address and the RPC endpoint"
        )
      );
    }
  }

  function _revertIfDeploymentIsInvalid(DeploymentParams memory _params) internal view {
    if (address(factory.votingToken()) != address(_params.votingToken)) {
      revert(
        string.concat(
          "DeployFranchiser: the deployed factory's voting token is ",
          vm.toString(address(factory.votingToken())),
          " but expected ",
          vm.toString(address(_params.votingToken))
        )
      );
    }
    if (address(factory.franchiserImplementation()).code.length == 0) {
      revert(
        "DeployFranchiser: the factory did not deploy a Franchiser implementation; "
        "this should be impossible and indicates a broken factory"
      );
    }
    if (address(factory.franchiserImplementation().votingToken()) != address(_params.votingToken)) {
      revert(
        string.concat(
          "DeployFranchiser: the Franchiser implementation's voting token is ",
          vm.toString(address(factory.franchiserImplementation().votingToken())),
          " but expected ",
          vm.toString(address(_params.votingToken))
        )
      );
    }
    if (address(lens.votingToken()) != address(_params.votingToken)) {
      revert(
        string.concat(
          "DeployFranchiser: the deployed lens's voting token is ",
          vm.toString(address(lens.votingToken())),
          " but expected ",
          vm.toString(address(_params.votingToken))
        )
      );
    }
    if (address(lens.franchiserFactory()) != address(factory)) {
      revert(
        string.concat(
          "DeployFranchiser: the deployed lens's factory is ",
          vm.toString(address(lens.franchiserFactory())),
          " but expected the factory deployed by this run, ",
          vm.toString(address(factory))
        )
      );
    }
  }
}
