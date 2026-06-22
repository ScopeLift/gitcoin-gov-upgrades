// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

/// @title GovernorSettableFixedQuorum
/// @author [ScopeLift](https://scopelift.co)
/// @notice An abstract extension to the Governor which implements a fixed quorum which can be
/// updated by governance.
abstract contract GovernorSettableFixedQuorum is Governor {
  using Checkpoints for Checkpoints.Trace208;

  /// @notice Historical checkpoints of quorum values by timepoint
  Checkpoints.Trace208 private quorumCheckpoints;

  /// @notice Emitted when the quorum value has changed.
  event QuorumUpdated(uint256 oldQuorum, uint256 newQuorum);

  /// @param _initialQuorum The quorum value set upon deployment
  constructor(uint256 _initialQuorum) {
    _setQuorum(_initialQuorum);
  }

  /// @notice A function to set quorum for the current timepoint. Proposals created after this
  /// timepoint will be subject to the new quorum.
  /// @param _amount The new quorum threshold.
  function setQuorum(uint256 _amount) external virtual onlyGovernance {
    _setQuorum(_amount);
  }

  /// @notice A function to get the quorum threshold for a given timepoint.
  /// @param _voteStart The vote start timepoint for a given proposal.
  function quorum(uint256 _voteStart) public view virtual override returns (uint256) {
    return quorumCheckpoints.upperLookupRecent(SafeCast.toUint32(_voteStart));
  }

  /// @notice A function to set quorum for the current timepoint.
  /// @param _amount The quorum amount to checkpoint.
  function _setQuorum(uint256 _amount) internal virtual {
    uint48 _timepoint = clock();
    emit QuorumUpdated(quorum(_timepoint), _amount);
    quorumCheckpoints.push(_timepoint, SafeCast.toUint208(_amount));
  }
}
