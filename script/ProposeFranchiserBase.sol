// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {FranchiserExpiryFactory} from "franchiser-expiry/src/FranchiserExpiryFactory.sol";
import {LoggedScript} from "script/LoggedScript.sol";
import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";

/// @notice Shared mechanics for the scripts that submit a Franchiser operation to the Governor as
/// a proposal (`ProposeFranchiserDelegation` and `ProposeFranchiserRecall`): the submitted
/// proposal id, and the validations every such proposal needs — the governance wiring, the
/// delegatee list, and the proposer clearing the proposal threshold. Checks specific to one
/// operation stay in its script; `_scriptName` prefixes the shared revert messages so each still
/// names the script that raised it.
abstract contract ProposeFranchiserBase is LoggedScript {
  uint256 public proposalId;

  function _scriptName() internal pure virtual returns (string memory);

  function _validateGovernanceWiring(
    GitcoinGovernorWithGuardian _governor,
    FranchiserExpiryFactory _factory,
    address _proposer,
    string memory _description
  ) internal view {
    if (address(_governor) == address(0)) {
      revert(
        string.concat(
          _scriptName(),
          ": governor is the zero address; "
          "set it to the address of the Governor that controls the Timelock"
        )
      );
    }
    if (address(_factory) == address(0)) {
      revert(
        string.concat(
          _scriptName(),
          ": factory is the zero address; "
          "set it to the address of the deployed FranchiserExpiryFactory"
        )
      );
    }
    if (_proposer == address(0)) {
      revert(
        string.concat(
          _scriptName(),
          ": proposer is the zero address; set it to the delegate submitting the proposal"
        )
      );
    }
    if (bytes(_description).length == 0) {
      revert(
        string.concat(_scriptName(), ": description is empty; set it to the text of the proposal")
      );
    }
    if (address(_factory.votingToken()) != address(_governor.token())) {
      revert(
        string.concat(
          _scriptName(),
          ": the factory's voting token is ",
          vm.toString(address(_factory.votingToken())),
          " but the governor's token is ",
          vm.toString(address(_governor.token())),
          "; the factory and the governor must be wired to the same token"
        )
      );
    }
  }

  // Every proposal delegatee list must be non-empty and hold no zero or repeated addresses. What
  // to do about a repeated address differs by operation, so the script supplies the hint that
  // completes the duplicate-entry message.
  function _validateDelegatees(address[] memory _delegatees, string memory _duplicateEntryHint)
    internal
    pure
  {
    if (_delegatees.length == 0) {
      revert(
        string.concat(_scriptName(), ": no delegatees; populate the delegatees for this proposal")
      );
    }
    for (uint256 _index = 0; _index < _delegatees.length; _index += 1) {
      if (_delegatees[_index] == address(0)) {
        revert(
          string.concat(
            _scriptName(), ": the delegatee at index ", vm.toString(_index), " is the zero address"
          )
        );
      }
      for (uint256 _priorIndex = 0; _priorIndex < _index; _priorIndex += 1) {
        if (_delegatees[_priorIndex] == _delegatees[_index]) {
          revert(
            string.concat(
              _scriptName(),
              ": the delegatee ",
              vm.toString(_delegatees[_index]),
              " appears more than once; ",
              _duplicateEntryHint
            )
          );
        }
      }
    }
  }

  function _validateProposerMeetsThreshold(GitcoinGovernorWithGuardian _governor, address _proposer)
    internal
    view
  {
    uint256 _proposerVotes = _governor.getVotes(_proposer, block.number - 1);
    if (_proposerVotes < _governor.proposalThreshold()) {
      revert(
        string.concat(
          _scriptName(),
          ": the proposer's voting weight of ",
          vm.toString(_proposerVotes),
          " is below the governor's proposal threshold of ",
          vm.toString(_governor.proposalThreshold()),
          "; the proposer must hold or be delegated at least the threshold"
        )
      );
    }
  }
}
