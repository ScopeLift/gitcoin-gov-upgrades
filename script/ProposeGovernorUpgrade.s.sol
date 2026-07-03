// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ICompoundTimelock} from "@openzeppelin/contracts/vendor/compound/ICompoundTimelock.sol";
import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";
import {IGovernorBravo} from "src/interfaces/IGovernorBravo.sol";

/// @notice Abstract base that holds the mechanics of proposing the Governor upgrade: a proposal,
/// submitted to the old (currently active) Governor, that transfers admin control of the DAO's
/// Timelock to the new `GitcoinGovernorWithGuardian`. The proposal carries two actions:
///
/// 1. `timelock.setPendingAdmin(newGovernor)` — the Timelock, executing the passed proposal,
///    names the new Governor as its pending admin.
/// 2. `newGovernor.__acceptAdmin()` — the new Governor claims the admin role from the Timelock.
///
/// A concrete contract supplies the configuration for a specific proposal by implementing
/// `_getProposalParams`.
abstract contract ProposeGovernorUpgrade is Script {
  struct ProposalParams {
    IGovernorBravo oldGovernor;
    GitcoinGovernorWithGuardian newGovernor;
    address proposer;
    string description;
  }

  uint256 public proposalId;
  bool internal isLogging = true;

  function run() public virtual {
    ProposalParams memory _params = _getProposalParams();
    _revertIfProposalParamsAreInvalid(_params);

    (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas) =
      _buildProposalActions(_params);

    _log("Proposing the Governor upgrade with:");
    _log(string.concat("  oldGovernor: ", vm.toString(address(_params.oldGovernor))));
    _log(string.concat("  newGovernor: ", vm.toString(address(_params.newGovernor))));
    _log(string.concat("  timelock:    ", vm.toString(_params.oldGovernor.timelock())));
    _log(string.concat("  proposer:    ", vm.toString(_params.proposer)));
    _log(string.concat("  description: ", _params.description));

    vm.startBroadcast(_params.proposer);
    // BROADCAST: submit the upgrade proposal to the old Governor
    _log("[1/1] Submitting the upgrade proposal to the old Governor");
    proposalId = _params.oldGovernor.propose(_targets, _values, _calldatas, _params.description);
    vm.stopBroadcast();

    _log(string.concat("Upgrade proposal submitted with id ", vm.toString(proposalId)));
  }

  function disableLogging() public {
    isLogging = false;
  }

  function _getProposalParams() internal view virtual returns (ProposalParams memory);

  function _buildProposalActions(ProposalParams memory _params)
    internal
    view
    returns (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas)
  {
    _targets = new address[](2);
    _values = new uint256[](2);
    _calldatas = new bytes[](2);

    _targets[0] = _params.oldGovernor.timelock();
    _calldatas[0] =
      abi.encodeCall(ICompoundTimelock.setPendingAdmin, (address(_params.newGovernor)));

    _targets[1] = address(_params.newGovernor);
    _calldatas[1] = abi.encodeCall(_params.newGovernor.__acceptAdmin, ());
  }

  function _log(string memory _msg) internal view {
    if (isLogging) {
      console2.log(_msg);
    }
  }

  function _revertIfProposalParamsAreInvalid(ProposalParams memory _params) internal view {
    if (address(_params.oldGovernor) == address(0)) {
      revert(
        "ProposeGovernorUpgrade: oldGovernor is the zero address; "
        "set it to the address of the currently active Governor"
      );
    }
    if (address(_params.newGovernor) == address(0)) {
      revert(
        "ProposeGovernorUpgrade: newGovernor is the zero address; "
        "set it to the address of the deployed GitcoinGovernorWithGuardian"
      );
    }
    if (_params.proposer == address(0)) {
      revert(
        "ProposeGovernorUpgrade: proposer is the zero address; "
        "set it to the delegate submitting the proposal"
      );
    }
    if (bytes(_params.description).length == 0) {
      revert(
        "ProposeGovernorUpgrade: description is empty; "
        "set it to the text of the upgrade proposal"
      );
    }

    address _timelock = _params.oldGovernor.timelock();
    if (_params.newGovernor.timelock() != _timelock) {
      revert(
        string.concat(
          "ProposeGovernorUpgrade: the new governor's timelock is ",
          vm.toString(_params.newGovernor.timelock()),
          " but the old governor's timelock is ",
          vm.toString(_timelock),
          "; both governors must be wired to the same timelock"
        )
      );
    }
    if (ICompoundTimelock(payable(_timelock)).admin() != address(_params.oldGovernor)) {
      revert(
        string.concat(
          "ProposeGovernorUpgrade: the timelock's admin is ",
          vm.toString(ICompoundTimelock(payable(_timelock)).admin()),
          " but expected the old governor ",
          vm.toString(address(_params.oldGovernor)),
          "; the upgrade proposal must be submitted to the governor that controls the timelock"
        )
      );
    }
    uint256 _proposerVotes = _params.oldGovernor.getVotes(_params.proposer, block.number - 1);
    if (_proposerVotes < _params.oldGovernor.proposalThreshold()) {
      revert(
        string.concat(
          "ProposeGovernorUpgrade: the proposer's voting weight of ",
          vm.toString(_proposerVotes),
          " is below the old governor's proposal threshold of ",
          vm.toString(_params.oldGovernor.proposalThreshold()),
          "; the proposer must hold or be delegated at least the threshold"
        )
      );
    }
  }
}
