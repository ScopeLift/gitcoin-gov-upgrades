// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICompoundTimelock} from "@openzeppelin/contracts/vendor/compound/ICompoundTimelock.sol";
import {Franchiser} from "franchiser-expiry/src/Franchiser.sol";
import {FranchiserExpiryFactory} from "franchiser-expiry/src/FranchiserExpiryFactory.sol";
import {IVotingToken} from "franchiser-expiry/src/interfaces/IVotingToken.sol";
import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";

/// @notice Abstract base that holds the mechanics of proposing a round of Franchiser delegations:
/// a proposal, submitted to the Governor that controls the DAO's Timelock, that delegates treasury
/// tokens held by the Timelock to one or more delegatees through the `FranchiserExpiryFactory`.
/// The proposal carries two actions:
///
/// 1. `votingToken.approve(factory, totalAmount)` — the Timelock approves the factory for the sum
///    of all delegated amounts.
/// 2. `factory.fundMany(delegatees, amounts, expiration)` — the factory pulls the tokens into one
///    Franchiser per delegatee, each of which delegates its balance to its delegatee.
///
/// Funding a delegatee who already has a live position tops it up and overwrites the position's
/// expiration; a zero amount for such a delegatee adjusts the expiration alone. All positions
/// funded by one proposal share a single expiration; propose multiple rounds for differing ones.
///
/// A concrete contract supplies the configuration for a specific proposal by implementing
/// `_getProposalParams`.
abstract contract ProposeFranchiserDelegation is Script {
  struct ProposalParams {
    GitcoinGovernorWithGuardian governor;
    FranchiserExpiryFactory factory;
    address proposer;
    address[] delegatees;
    uint256[] amounts;
    uint256 expiration;
    string description;
  }

  // Mainnet block cadence, used to convert the Governor's block-denominated voting pipeline into
  // seconds when validating the expiration.
  uint256 constant SECONDS_PER_BLOCK = 12;

  uint256 public proposalId;
  bool internal isLogging = true;

  function run() public virtual {
    ProposalParams memory _params = _getProposalParams();
    _revertIfProposalParamsAreInvalid(_params);

    (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas) =
      _buildProposalActions(_params);

    _logProposalSummary(_params);

    vm.startBroadcast(_params.proposer);
    // BROADCAST: submit the delegation proposal to the Governor
    _log("[1/1] Submitting the delegation proposal to the Governor");
    proposalId = _params.governor.propose(_targets, _values, _calldatas, _params.description);
    vm.stopBroadcast();

    _log(string.concat("Delegation proposal submitted with id ", vm.toString(proposalId)));
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

    _targets[0] = address(_params.factory.votingToken());
    _calldatas[0] =
      abi.encodeCall(IERC20.approve, (address(_params.factory), _sumOf(_params.amounts)));

    _targets[1] = address(_params.factory);
    _calldatas[1] = abi.encodeCall(
      _params.factory.fundMany, (_params.delegatees, _params.amounts, _params.expiration)
    );
  }

  function _sumOf(uint256[] memory _amounts) internal pure returns (uint256 _total) {
    for (uint256 _index = 0; _index < _amounts.length; _index += 1) {
      _total += _amounts[_index];
    }
  }

  function _logProposalSummary(ProposalParams memory _params) internal view {
    address _timelock = _params.governor.timelock();
    _log("Proposing Franchiser delegations with:");
    _log(string.concat("  governor:    ", vm.toString(address(_params.governor))));
    _log(string.concat("  factory:     ", vm.toString(address(_params.factory))));
    _log(string.concat("  votingToken: ", vm.toString(address(_params.factory.votingToken()))));
    _log(string.concat("  timelock:    ", vm.toString(_timelock)));
    _log(string.concat("  proposer:    ", vm.toString(_params.proposer)));
    _log(string.concat("  expiration:  ", vm.toString(_params.expiration)));
    _log(string.concat("  totalAmount: ", vm.toString(_sumOf(_params.amounts))));
    _log(string.concat("  description: ", _params.description));
    _log("  delegations:");
    for (uint256 _index = 0; _index < _params.delegatees.length; _index += 1) {
      Franchiser _franchiser = _params.factory.getFranchiser(_timelock, _params.delegatees[_index]);
      string memory _status;
      if (address(_franchiser).code.length == 0) {
        _status = "new position";
      } else {
        _status = "existing position - overwrites its expiration";
      }
      _log(
        string.concat(
          "    ",
          vm.toString(_params.amounts[_index]),
          " -> ",
          vm.toString(_params.delegatees[_index]),
          " (franchiser ",
          vm.toString(address(_franchiser)),
          ", ",
          _status,
          ")"
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
        "ProposeFranchiserDelegation: governor is the zero address; "
        "set it to the address of the Governor that controls the Timelock"
      );
    }
    if (address(_params.factory) == address(0)) {
      revert(
        "ProposeFranchiserDelegation: factory is the zero address; "
        "set it to the address of the deployed FranchiserExpiryFactory"
      );
    }
    if (_params.proposer == address(0)) {
      revert(
        "ProposeFranchiserDelegation: proposer is the zero address; "
        "set it to the delegate submitting the proposal"
      );
    }
    if (bytes(_params.description).length == 0) {
      revert(
        "ProposeFranchiserDelegation: description is empty; "
        "set it to the text of the delegation proposal"
      );
    }
    if (_params.delegatees.length == 0) {
      revert(
        "ProposeFranchiserDelegation: no delegatees; "
        "populate the delegatees and amounts for this delegation round"
      );
    }
    if (_params.delegatees.length != _params.amounts.length) {
      revert(
        string.concat(
          "ProposeFranchiserDelegation: ",
          vm.toString(_params.delegatees.length),
          " delegatees but ",
          vm.toString(_params.amounts.length),
          " amounts; every delegatee needs exactly one amount"
        )
      );
    }
    IVotingToken _votingToken = _params.factory.votingToken();
    if (address(_votingToken) != address(_params.governor.token())) {
      revert(
        string.concat(
          "ProposeFranchiserDelegation: the factory's voting token is ",
          vm.toString(address(_votingToken)),
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
            "ProposeFranchiserDelegation: the delegatee at index ",
            vm.toString(_index),
            " is the zero address"
          )
        );
      }
      for (uint256 _priorIndex = 0; _priorIndex < _index; _priorIndex += 1) {
        if (_params.delegatees[_priorIndex] == _delegatee) {
          revert(
            string.concat(
              "ProposeFranchiserDelegation: the delegatee ",
              vm.toString(_delegatee),
              " appears more than once; combine their amounts into a single entry"
            )
          );
        }
      }
      if (
        _params.amounts[_index] == 0
          && address(_params.factory.getFranchiser(_timelock, _delegatee)).code.length == 0
      ) {
        revert(
          string.concat(
            "ProposeFranchiserDelegation: the amount for delegatee ",
            vm.toString(_delegatee),
            " is zero but they have no existing position; a zero amount is only meaningful as "
            "an expiration adjustment to an existing position"
          )
        );
      }
    }

    uint256 _totalAmount = _sumOf(_params.amounts);
    if (_votingToken.balanceOf(_timelock) < _totalAmount) {
      revert(
        string.concat(
          "ProposeFranchiserDelegation: the proposal delegates ",
          vm.toString(_totalAmount),
          " tokens but the Timelock holds only ",
          vm.toString(_votingToken.balanceOf(_timelock)),
          "; the Timelock must hold the full amount (checked now, and required again at execution)"
        )
      );
    }
    uint256 _proposerVotes = _params.governor.getVotes(_params.proposer, block.number - 1);
    if (_proposerVotes < _params.governor.proposalThreshold()) {
      revert(
        string.concat(
          "ProposeFranchiserDelegation: the proposer's voting weight of ",
          vm.toString(_proposerVotes),
          " is below the governor's proposal threshold of ",
          vm.toString(_params.governor.proposalThreshold()),
          "; the proposer must hold or be delegated at least the threshold"
        )
      );
    }
    _revertIfExpirationIsTooSoon(_params);
  }

  // `fund` reverts if the expiration has already passed when the proposal executes, and execution
  // can legitimately happen as late as the Timelock's grace period after the proposal's eta. So
  // the expiration must outlive the whole pipeline: the voting delay and period (block-denominated
  // and converted at SECONDS_PER_BLOCK), the Timelock delay, and the grace period. This assumes
  // the proposal is queued promptly once it succeeds.
  function _revertIfExpirationIsTooSoon(ProposalParams memory _params) internal view {
    ICompoundTimelock _timelock = ICompoundTimelock(payable(_params.governor.timelock()));
    uint256 _votingPipelineSeconds =
      SECONDS_PER_BLOCK * (_params.governor.votingDelay() + _params.governor.votingPeriod());
    uint256 _minimumExpiration =
      block.timestamp + _votingPipelineSeconds + _timelock.delay() + _timelock.GRACE_PERIOD();
    if (_params.expiration < _minimumExpiration) {
      revert(
        string.concat(
          "ProposeFranchiserDelegation: the expiration ",
          vm.toString(_params.expiration),
          " is too soon; it must be at least ",
          vm.toString(_minimumExpiration),
          " so the positions cannot expire before the proposal's last legitimate execution time"
        )
      );
    }
  }
}
