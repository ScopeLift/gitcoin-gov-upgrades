// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ICompoundTimelock} from "@openzeppelin/contracts/vendor/compound/ICompoundTimelock.sol";
import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";
import {IComp} from "src/interfaces/IComp.sol";

/// @notice Abstract base that holds the mechanics of deploying a `GitcoinGovernorWithGuardian`.
/// A concrete contract supplies the configuration for a specific deployment by implementing
/// `_getDeploymentParams`.
abstract contract DeployGitcoinGovernorWithGuardian is Script {
  struct DeploymentParams {
    string name;
    uint256 initialQuorum;
    uint48 initialVoteExtension;
    uint48 initialVotingDelay;
    uint32 initialVotingPeriod;
    uint256 initialProposalThreshold;
    IComp token;
    ICompoundTimelock timelock;
    address initialProposalGuardian;
  }

  GitcoinGovernorWithGuardian public governor;
  bool internal isLogging = true;

  function run() public virtual {
    DeploymentParams memory _params = _getDeploymentParams();
    _validateDeploymentParams(_params);

    _log("Deploying GitcoinGovernorWithGuardian with:");
    _log(string.concat("  name:                     ", _params.name));
    _log(string.concat("  initialQuorum:            ", vm.toString(_params.initialQuorum)));
    _log(string.concat("  initialVoteExtension:     ", vm.toString(_params.initialVoteExtension)));
    _log(string.concat("  initialVotingDelay:       ", vm.toString(_params.initialVotingDelay)));
    _log(string.concat("  initialVotingPeriod:      ", vm.toString(_params.initialVotingPeriod)));
    _log(
      string.concat("  initialProposalThreshold: ", vm.toString(_params.initialProposalThreshold))
    );
    _log(string.concat("  token:                    ", vm.toString(address(_params.token))));
    _log(string.concat("  timelock:                 ", vm.toString(address(_params.timelock))));
    _log(
      string.concat("  initialProposalGuardian:  ", vm.toString(_params.initialProposalGuardian))
    );

    vm.startBroadcast();
    // BROADCAST: deploy the GitcoinGovernorWithGuardian
    _log("[1/1] Deploying GitcoinGovernorWithGuardian");
    governor = new GitcoinGovernorWithGuardian(
      _params.name,
      _params.initialQuorum,
      _params.initialVoteExtension,
      _params.initialVotingDelay,
      _params.initialVotingPeriod,
      _params.initialProposalThreshold,
      address(_params.token),
      _params.timelock,
      _params.initialProposalGuardian
    );
    vm.stopBroadcast();

    _log(string.concat("GitcoinGovernorWithGuardian deployed at ", vm.toString(address(governor))));

    _validateDeployment(_params);
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

  function _validateDeploymentParams(DeploymentParams memory _params) internal pure {
    if (address(_params.token) == address(0)) {
      revert(
        "DeployGitcoinGovernorWithGuardian: token is the zero address; "
        "set it to the address of the COMP-style GTC token"
      );
    }
    if (address(_params.timelock) == address(0)) {
      revert(
        "DeployGitcoinGovernorWithGuardian: timelock is the zero address; "
        "set it to the address of Gitcoin's Compound Timelock"
      );
    }
    if (_params.initialProposalGuardian == address(0)) {
      revert(
        "DeployGitcoinGovernorWithGuardian: initialProposalGuardian is the zero address; "
        "deploying without a guardian would let every proposer cancel their own proposals at "
        "any lifecycle stage, so set it to the address that should hold cancel authority"
      );
    }
  }

  function _validateDeployment(DeploymentParams memory _params) internal view {
    if (address(governor.token()) != address(_params.token)) {
      revert(
        string.concat(
          "DeployGitcoinGovernorWithGuardian: deployed governor token is ",
          vm.toString(address(governor.token())),
          " but expected ",
          vm.toString(address(_params.token))
        )
      );
    }
    if (governor.timelock() != address(_params.timelock)) {
      revert(
        string.concat(
          "DeployGitcoinGovernorWithGuardian: deployed governor timelock is ",
          vm.toString(governor.timelock()),
          " but expected ",
          vm.toString(address(_params.timelock))
        )
      );
    }
    if (governor.proposalGuardian() != _params.initialProposalGuardian) {
      revert(
        string.concat(
          "DeployGitcoinGovernorWithGuardian: deployed governor proposal guardian is ",
          vm.toString(governor.proposalGuardian()),
          " but expected ",
          vm.toString(_params.initialProposalGuardian)
        )
      );
    }
  }
}
