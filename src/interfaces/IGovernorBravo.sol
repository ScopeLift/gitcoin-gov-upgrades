// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

/// @title IGovernorBravo
/// @author [ScopeLift](https://scopelift.co)
/// @notice The subset of the ABI of Gitcoin's active Governor ("GTC Governor Bravo") that this
/// project uses to propose, vote on, and execute the proposal transferring Timelock control to the
/// upgraded Governor. The active Governor was built on OpenZeppelin Contracts v4.8.0 during the
/// DAO's 2023 upgrade.
/// @dev The v4.8.0 Governor's `ProposalState` enum has an identical layout to the v5 one, so this
/// interface reuses `IGovernor.ProposalState` from the pinned OpenZeppelin v5 library rather than
/// redeclaring it.
interface IGovernorBravo {
  /// @notice The address of the Compound Timelock through which this Governor executes passed
  /// proposals, and whose admin it is.
  function timelock() external view returns (address);

  /// @notice The number of votes required to become a proposer.
  function proposalThreshold() external view returns (uint256);

  /// @notice The voting weight an account held at a past block.
  /// @param _account The address whose voting weight is queried.
  /// @param _blockNumber The block number at which the weight is read.
  /// @return The number of votes the account held at the given block.
  function getVotes(address _account, uint256 _blockNumber) external view returns (uint256);

  /// @notice The current lifecycle state of a proposal.
  /// @param _proposalId The identifier of the proposal to query.
  /// @return The proposal's current state.
  function state(uint256 _proposalId) external view returns (IGovernor.ProposalState);

  /// @notice The block at which a proposal's voting weight is snapshotted, i.e. the block after
  /// which voting opens.
  /// @param _proposalId The identifier of the proposal to query.
  /// @return The proposal's snapshot block number.
  function proposalSnapshot(uint256 _proposalId) external view returns (uint256);

  /// @notice The block at which a proposal's voting period ends.
  /// @param _proposalId The identifier of the proposal to query.
  /// @return The proposal's deadline block number.
  function proposalDeadline(uint256 _proposalId) external view returns (uint256);

  /// @notice The timestamp at which a queued proposal becomes executable in the Timelock.
  /// @param _proposalId The identifier of the proposal to query.
  /// @return The proposal's eta timestamp, or zero if it is not queued.
  function proposalEta(uint256 _proposalId) external view returns (uint256);

  /// @notice Creates a new proposal. The caller must hold voting weight of at least
  /// `proposalThreshold` at the previous block.
  /// @param _targets The addresses the proposal's actions call.
  /// @param _values The ETH values sent with each action.
  /// @param _calldatas The calldata each action is called with.
  /// @param _description A human-readable description of the proposal.
  /// @return The identifier of the newly created proposal.
  function propose(
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    string memory _description
  ) external returns (uint256);

  /// @notice Casts a vote on a proposal.
  /// @param _proposalId The identifier of the proposal voted on.
  /// @param _support The vote type: 0 = Against, 1 = For, 2 = Abstain.
  /// @return The voting weight cast.
  function castVote(uint256 _proposalId, uint8 _support) external returns (uint256);

  /// @notice Queues a succeeded proposal's actions in the Timelock.
  /// @param _targets The addresses the proposal's actions call.
  /// @param _values The ETH values sent with each action.
  /// @param _calldatas The calldata each action is called with.
  /// @param _descriptionHash The keccak256 hash of the proposal's description.
  /// @return The identifier of the queued proposal.
  function queue(
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) external returns (uint256);

  /// @notice Executes a queued proposal once its Timelock eta has passed.
  /// @param _targets The addresses the proposal's actions call.
  /// @param _values The ETH values sent with each action.
  /// @param _calldatas The calldata each action is called with.
  /// @param _descriptionHash The keccak256 hash of the proposal's description.
  /// @return The identifier of the executed proposal.
  function execute(
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) external payable returns (uint256);
}
