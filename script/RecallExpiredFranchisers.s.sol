// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {Franchiser} from "franchiser-expiry/src/Franchiser.sol";
import {FranchiserExpiryFactory} from "franchiser-expiry/src/FranchiserExpiryFactory.sol";
import {LoggedScript} from "script/LoggedScript.sol";

/// @notice Abstract base that holds the mechanics of sweeping expired Franchiser positions back
/// to their owner with `factory.recallManyExpired`. Unlike the proposal scripts, this is not a
/// governance action: recalling an expired position is permissionless and the tokens always
/// return to the position's owner (the Timelock), so anyone can run it from any account.
///
/// The configured delegatee list is a candidate set, not a command: the script checks each
/// candidate on-chain and recalls only the positions that exist and have expired, logging why it
/// skips the rest. A superset — such as every delegatee the DAO has ever funded — is safe to
/// configure permanently.
///
/// A concrete contract supplies the configuration for a specific sweep by implementing
/// `_getRecallParams`.
abstract contract RecallExpiredFranchisers is LoggedScript {
  struct RecallParams {
    FranchiserExpiryFactory factory;
    address owner;
    address[] delegatees;
  }

  address[] public recalledDelegatees;
  uint256 public recalledCount;

  function run() public virtual {
    RecallParams memory _params = _getRecallParams();
    _validateRecallParams(_params);

    _log("Recalling expired Franchiser positions with:");
    _log(string.concat("  factory: ", vm.toString(address(_params.factory))));
    _log(string.concat("  owner:   ", vm.toString(_params.owner)));
    _log("  candidates:");
    (address[] memory _owners, address[] memory _delegatees) = _filterExpiredPositions(_params);

    if (_delegatees.length == 0) {
      _log("No expired positions among the candidates; nothing to broadcast");
      return;
    }

    vm.startBroadcast();
    // BROADCAST: recall every expired position back to the owner
    _log(
      string.concat(
        "[1/1] Recalling ", vm.toString(_delegatees.length), " expired position(s) to the owner"
      )
    );
    _params.factory.recallManyExpired(_owners, _delegatees);
    vm.stopBroadcast();

    for (uint256 _index = 0; _index < _delegatees.length; _index += 1) {
      recalledDelegatees.push(_delegatees[_index]);
    }
    recalledCount = _delegatees.length;
    _log(string.concat("Recalled ", vm.toString(recalledCount), " expired position(s)"));

    _validateNoTokensLeftBehind(_params, _delegatees);
  }

  function _getRecallParams() internal view virtual returns (RecallParams memory);

  // Splits the candidate list into the positions that can be recalled now — those that exist and
  // have expired — and logs a line explaining the status of every candidate.
  function _filterExpiredPositions(RecallParams memory _params)
    internal
    view
    returns (address[] memory _owners, address[] memory _delegatees)
  {
    bool[] memory _isRecallable = new bool[](_params.delegatees.length);
    uint256 _recallableCount = 0;
    for (uint256 _index = 0; _index < _params.delegatees.length; _index += 1) {
      address _delegatee = _params.delegatees[_index];
      Franchiser _franchiser = _params.factory.getFranchiser(_params.owner, _delegatee);
      if (address(_franchiser).code.length == 0) {
        _log(
          string.concat("    skipping ", vm.toString(_delegatee), ": no position exists for them")
        );
        continue;
      }
      uint256 _expiration = _params.factory.expirations(_franchiser);
      if (block.timestamp < _expiration) {
        _log(
          string.concat(
            "    skipping ",
            vm.toString(_delegatee),
            ": their position does not expire until ",
            vm.toString(_expiration)
          )
        );
        continue;
      }
      _log(
        string.concat(
          "    recalling ",
          vm.toString(_delegatee),
          ": their position (franchiser ",
          vm.toString(address(_franchiser)),
          ") expired at ",
          vm.toString(_expiration)
        )
      );
      _isRecallable[_index] = true;
      _recallableCount += 1;
    }

    _owners = new address[](_recallableCount);
    _delegatees = new address[](_recallableCount);
    uint256 _recallableIndex = 0;
    for (uint256 _index = 0; _index < _params.delegatees.length; _index += 1) {
      if (_isRecallable[_index]) {
        _owners[_recallableIndex] = _params.owner;
        _delegatees[_recallableIndex] = _params.delegatees[_index];
        _recallableIndex += 1;
      }
    }
  }

  function _validateRecallParams(RecallParams memory _params) internal pure {
    if (address(_params.factory) == address(0)) {
      revert(
        "RecallExpiredFranchisers: factory is the zero address; "
        "set it to the address of the deployed FranchiserExpiryFactory"
      );
    }
    if (_params.owner == address(0)) {
      revert(
        "RecallExpiredFranchisers: owner is the zero address; "
        "set it to the owner of the positions being swept, ordinarily the Timelock"
      );
    }
    if (_params.delegatees.length == 0) {
      revert(
        "RecallExpiredFranchisers: no delegatees; "
        "populate the candidate delegatees whose expired positions this script sweeps"
      );
    }
    for (uint256 _index = 0; _index < _params.delegatees.length; _index += 1) {
      if (_params.delegatees[_index] == address(0)) {
        revert(
          string.concat(
            "RecallExpiredFranchisers: the delegatee at index ",
            vm.toString(_index),
            " is the zero address"
          )
        );
      }
      for (uint256 _priorIndex = 0; _priorIndex < _index; _priorIndex += 1) {
        if (_params.delegatees[_priorIndex] == _params.delegatees[_index]) {
          revert(
            string.concat(
              "RecallExpiredFranchisers: the delegatee ",
              vm.toString(_params.delegatees[_index]),
              " appears more than once; remove the duplicate entry"
            )
          );
        }
      }
    }
  }

  function _validateNoTokensLeftBehind(RecallParams memory _params, address[] memory _recalled)
    internal
    view
  {
    for (uint256 _index = 0; _index < _recalled.length; _index += 1) {
      Franchiser _franchiser = _params.factory.getFranchiser(_params.owner, _recalled[_index]);
      uint256 _remainingBalance = _params.factory.votingToken().balanceOf(address(_franchiser));
      if (_remainingBalance != 0) {
        revert(
          string.concat(
            "RecallExpiredFranchisers: the franchiser for delegatee ",
            vm.toString(_recalled[_index]),
            " still holds ",
            vm.toString(_remainingBalance),
            " tokens after the recall; this should be impossible and needs investigation"
          )
        );
      }
    }
  }
}
