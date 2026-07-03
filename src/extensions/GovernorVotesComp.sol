// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {IComp} from "src/interfaces/IComp.sol";

/// @title GovernorVotesComp
/// @author [ScopeLift](https://scopelift.co)
/// @notice Modified GovernorVotes contract that supports legacy COMP-style tokens.
abstract contract GovernorVotesComp is Governor {
  /// @notice The legacy IComp token from which voting weight is sourced.
  IComp public token;

  /// @notice This function implements the clock interface as specified in ERC-6372.
  /// @dev Returns the current clock value used for governance voting.
  /// @return uint48 The current block number cast to uint48.
  function clock() public view virtual override returns (uint48) {
    return Time.blockNumber();
  }

  /// @notice Returns a machine-readable description of the clock as specified in ERC-6372.
  /// @dev This function provides information about the clock mode used for governance timing.
  /// @return string A string describing the clock mode, indicating that block numbers are used
  /// as the time measure, with the default starting point.
  // forge-lint: disable-next-line(mixed-case-function)
  function CLOCK_MODE() public view virtual override returns (string memory) {
    return "mode=blocknumber&from=default";
  }

  /// @notice Retrieves the voting weight for a specific account at a given timepoint.
  /// @dev This function overrides the base _getVotes function to use Compound's getPriorVotes
  /// mechanism.
  /// @param _account The address of the account to check the voting weight for.
  /// @param _timepoint The timepoint at which to check the voting weight.
  /// @param /*params*/ Unused parameter, kept for compatibility with the base function signature.
  /// @return uint256 The voting weight of the account at the specified timepoint.
  function _getVotes(
    address _account,
    uint256 _timepoint,
    bytes memory /*params*/
  )
    internal
    view
    virtual
    override
    returns (uint256)
  {
    return token.getPriorVotes(_account, _timepoint);
  }
}
