// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {Franchiser} from "franchiser-expiry/src/Franchiser.sol";
import {FranchiserExpiryFactory} from "franchiser-expiry/src/FranchiserExpiryFactory.sol";
import {IVotingToken} from "franchiser-expiry/src/interfaces/IVotingToken.sol";
import {ProposeFranchiserBase} from "script/ProposeFranchiserBase.sol";
import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";

/// @notice Abstract base that holds the mechanics of proposing Franchiser recalls: a proposal,
/// submitted to the Governor that controls the DAO's Timelock, that unwinds one or more of the
/// Timelock's Franchiser positions before they expire. The proposal carries one action:
/// `factory.recallMany`, which recalls each position's tokens — including any the delegatee has
/// sub-delegated — to the corresponding recipient, ordinarily the Timelock. Any other recipient
/// is legal but sends treasury funds out of the treasury, so the script prints a prominent
/// warning for each such recipient during the dry run.
///
/// This is the DAO's early-unwind lever. Positions that have already expired do not need it:
/// anyone can return those to the Timelock permissionlessly with `RecallExpiredFranchisers`.
///
/// A concrete contract supplies the configuration for a specific proposal by implementing
/// `_getProposalParams`.
abstract contract ProposeFranchiserRecall is ProposeFranchiserBase {
  struct ProposalParams {
    GitcoinGovernorWithGuardian governor;
    FranchiserExpiryFactory factory;
    address proposer;
    address[] delegatees;
    address[] tokenRecipients;
    string description;
  }

  uint256 public offTreasuryRecipientCount;

  function run() public virtual {
    ProposalParams memory _params = _getProposalParams();
    _validateProposalParams(_params);

    (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas) =
      _buildProposalActions(_params);

    _logProposalSummary(_params);
    _warnIfTokenRecipientIsNotTheTimelock(_params);

    vm.startBroadcast(_params.proposer);
    // BROADCAST: submit the recall proposal to the Governor
    _log("[1/1] Submitting the recall proposal to the Governor");
    proposalId = _params.governor.propose(_targets, _values, _calldatas, _params.description);
    vm.stopBroadcast();

    _log(string.concat("Recall proposal submitted with id ", vm.toString(proposalId)));
  }

  function _getProposalParams() internal view virtual returns (ProposalParams memory);

  function _scriptName() internal pure override returns (string memory) {
    return "ProposeFranchiserRecall";
  }

  function _buildProposalActions(ProposalParams memory _params)
    internal
    pure
    returns (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas)
  {
    _targets = new address[](1);
    _values = new uint256[](1);
    _calldatas = new bytes[](1);

    _targets[0] = address(_params.factory);
    _calldatas[0] =
      abi.encodeCall(_params.factory.recallMany, (_params.delegatees, _params.tokenRecipients));
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
          vm.toString(_params.tokenRecipients[_index]),
          " (franchiser ",
          vm.toString(address(_franchiser)),
          " holds ",
          vm.toString(_votingToken.balanceOf(address(_franchiser))),
          ", plus any sub-delegated tokens)"
        )
      );
    }
  }

  // Recalled tokens ordinarily return to the Timelock. Any other recipient is legal — the DAO
  // can deliberately direct recalled funds elsewhere — but it sends treasury funds out of the
  // treasury, so the dry run shouts about each one for the proposer to consciously confirm. The
  // public counter lets tests pin the behavior despite logging being silenced.
  function _warnIfTokenRecipientIsNotTheTimelock(ProposalParams memory _params) internal {
    address _timelock = _params.governor.timelock();
    for (uint256 _index = 0; _index < _params.tokenRecipients.length; _index += 1) {
      if (_params.tokenRecipients[_index] == _timelock) {
        continue;
      }
      offTreasuryRecipientCount += 1;
      _log(unicode"⚠️⚠️⚠️  WARNING  ⚠️⚠️⚠️");
      _log(
        string.concat(
          "The recipient for delegatee ",
          vm.toString(_params.delegatees[_index]),
          " is ",
          vm.toString(_params.tokenRecipients[_index]),
          ", which is NOT the Timelock (",
          vm.toString(_timelock),
          ")."
        )
      );
      _log("The tokens recalled from this position will NOT return to the DAO treasury.");
      _log("Proceed only if this proposal intends to send treasury funds to this address.");
    }
  }

  function _validateProposalParams(ProposalParams memory _params) internal view {
    _validateGovernanceWiring(
      _params.governor, _params.factory, _params.proposer, _params.description
    );
    _validateDelegatees(_params.delegatees, "remove the duplicate entry");
    if (_params.delegatees.length != _params.tokenRecipients.length) {
      revert(
        string.concat(
          "ProposeFranchiserRecall: ",
          vm.toString(_params.delegatees.length),
          " delegatees but ",
          vm.toString(_params.tokenRecipients.length),
          " recipients; every delegatee needs exactly one recipient"
        )
      );
    }

    address _timelock = _params.governor.timelock();
    for (uint256 _index = 0; _index < _params.delegatees.length; _index += 1) {
      address _delegatee = _params.delegatees[_index];
      if (_params.tokenRecipients[_index] == address(0)) {
        revert(
          string.concat(
            "ProposeFranchiserRecall: the recipient for delegatee ",
            vm.toString(_delegatee),
            " is the zero address; recalls are ordinarily sent back to the Timelock"
          )
        );
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

    _validateProposerMeetsThreshold(_params.governor, _params.proposer);
  }
}
