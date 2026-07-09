// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Franchiser} from "franchiser-expiry/src/Franchiser.sol";
import {FranchiserExpiryFactory} from "franchiser-expiry/src/FranchiserExpiryFactory.sol";
import {IVotingToken} from "franchiser-expiry/src/interfaces/IVotingToken.sol";
import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";

/// @notice Abstract base that holds the mechanics of proposing Franchiser recalls: a proposal,
/// submitted to the Governor that controls the DAO's Timelock, that unwinds one or more of the
/// Timelock's Franchiser positions before they expire. The proposal carries one action:
/// `factory.recallMany(delegatees, tos)`, which recalls each position's tokens — including any
/// the delegatee has sub-delegated — to the corresponding recipient, ordinarily the Timelock.
///
/// This is the DAO's early-unwind lever. Positions that have already expired do not need it:
/// anyone can return those to the Timelock permissionlessly with `RecallExpiredFranchisers`.
///
/// A concrete contract supplies the configuration for a specific proposal by implementing
/// `_getProposalParams`.
abstract contract ProposeFranchiserRecall is Script {
  struct ProposalParams {
    GitcoinGovernorWithGuardian governor;
    FranchiserExpiryFactory factory;
    address proposer;
    address[] delegatees;
    address[] tos;
    string description;
  }

  uint256 public proposalId;
  bool internal isLogging = true;

  function run() public virtual {
    ProposalParams memory _params = _getProposalParams();
    _revertIfProposalParamsAreInvalid(_params);

    (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas) =
      _buildProposalActions(_params);

    _logProposalSummary(_params);

    vm.startBroadcast(_params.proposer);
    // BROADCAST: submit the recall proposal to the Governor
    _log("[1/1] Submitting the recall proposal to the Governor");
    proposalId = _params.governor.propose(_targets, _values, _calldatas, _params.description);
    vm.stopBroadcast();

    _log(string.concat("Recall proposal submitted with id ", vm.toString(proposalId)));
  }

  function disableLogging() public {
    isLogging = false;
  }

  function _getProposalParams() internal view virtual returns (ProposalParams memory);

  function _buildProposalActions(ProposalParams memory _params)
    internal
    pure
    returns (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas)
  {
    _targets = new address[](1);
    _values = new uint256[](1);
    _calldatas = new bytes[](1);

    _targets[0] = address(_params.factory);
    _calldatas[0] = abi.encodeCall(_params.factory.recallMany, (_params.delegatees, _params.tos));
  }

  function _logProposalSummary(ProposalParams memory _params) internal view {
    address _timelock = _params.governor.timelock();
    IVotingToken _votingToken = _params.factory.votingToken();
    _log("Proposing Franchiser recalls with:");
    _log(string.concat("  governor:    ", vm.toString(address(_params.governor))));
    _log(string.concat("  factory:     ", vm.toString(address(_params.factory))));
    _log(string.concat("  votingToken: ", vm.toString(address(_votingToken))));
    _log(string.concat("  timelock:    ", vm.toString(_timelock)));
    _log(string.concat("  proposer:    ", vm.toString(_params.proposer)));
    _log(string.concat("  description: ", _params.description));
    _log("  recalls:");
    for (uint256 _index = 0; _index < _params.delegatees.length; _index += 1) {
      Franchiser _franchiser = _params.factory.getFranchiser(_timelock, _params.delegatees[_index]);
      // The franchiser's own balance understates what the recall returns when the delegatee has
      // sub-delegated: recalling also claws back the entire sub-delegation tree.
      _log(
        string.concat(
          "    ",
          vm.toString(_params.delegatees[_index]),
          " -> ",
          vm.toString(_params.tos[_index]),
          " (franchiser ",
          vm.toString(address(_franchiser)),
          " holds ",
          vm.toString(_votingToken.balanceOf(address(_franchiser))),
          ", plus any sub-delegated tokens)"
        )
      );
    }
  }

  function _log(string memory _msg) internal view {
    if (isLogging) {
      console2.log(_msg);
    }
  }

  function _revertIfProposalParamsAreInvalid(ProposalParams memory _params) internal view {
    if (address(_params.governor) == address(0)) {
      revert(
        "ProposeFranchiserRecall: governor is the zero address; "
        "set it to the address of the Governor that controls the Timelock"
      );
    }
    if (address(_params.factory) == address(0)) {
      revert(
        "ProposeFranchiserRecall: factory is the zero address; "
        "set it to the address of the deployed FranchiserExpiryFactory"
      );
    }
    if (_params.proposer == address(0)) {
      revert(
        "ProposeFranchiserRecall: proposer is the zero address; "
        "set it to the delegate submitting the proposal"
      );
    }
    if (bytes(_params.description).length == 0) {
      revert(
        "ProposeFranchiserRecall: description is empty; "
        "set it to the text of the recall proposal"
      );
    }
    if (_params.delegatees.length == 0) {
      revert(
        "ProposeFranchiserRecall: no delegatees; "
        "populate the delegatees whose positions this proposal recalls"
      );
    }
    if (_params.delegatees.length != _params.tos.length) {
      revert(
        string.concat(
          "ProposeFranchiserRecall: ",
          vm.toString(_params.delegatees.length),
          " delegatees but ",
          vm.toString(_params.tos.length),
          " recipients; every delegatee needs exactly one recipient"
        )
      );
    }
    if (address(_params.factory.votingToken()) != address(_params.governor.token())) {
      revert(
        string.concat(
          "ProposeFranchiserRecall: the factory's voting token is ",
          vm.toString(address(_params.factory.votingToken())),
          " but the governor's token is ",
          vm.toString(address(_params.governor.token())),
          "; the factory and the governor must be wired to the same token"
        )
      );
    }

    address _timelock = _params.governor.timelock();
    for (uint256 _index = 0; _index < _params.delegatees.length; _index += 1) {
      address _delegatee = _params.delegatees[_index];
      if (_delegatee == address(0)) {
        revert(
          string.concat(
            "ProposeFranchiserRecall: the delegatee at index ",
            vm.toString(_index),
            " is the zero address"
          )
        );
      }
      if (_params.tos[_index] == address(0)) {
        revert(
          string.concat(
            "ProposeFranchiserRecall: the recipient for delegatee ",
            vm.toString(_delegatee),
            " is the zero address; recalls are ordinarily sent back to the Timelock"
          )
        );
      }
      for (uint256 _priorIndex = 0; _priorIndex < _index; _priorIndex += 1) {
        if (_params.delegatees[_priorIndex] == _delegatee) {
          revert(
            string.concat(
              "ProposeFranchiserRecall: the delegatee ",
              vm.toString(_delegatee),
              " appears more than once; remove the duplicate entry"
            )
          );
        }
      }
      if (address(_params.factory.getFranchiser(_timelock, _delegatee)).code.length == 0) {
        revert(
          string.concat(
            "ProposeFranchiserRecall: no position exists for delegatee ",
            vm.toString(_delegatee),
            "; recalling it would silently do nothing, so remove the entry"
          )
        );
      }
    }

    uint256 _proposerVotes = _params.governor.getVotes(_params.proposer, block.number - 1);
    if (_proposerVotes < _params.governor.proposalThreshold()) {
      revert(
        string.concat(
          "ProposeFranchiserRecall: the proposer's voting weight of ",
          vm.toString(_proposerVotes),
          " is below the governor's proposal threshold of ",
          vm.toString(_params.governor.proposalThreshold()),
          "; the proposer must hold or be delegated at least the threshold"
        )
      );
    }
  }
}
