// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.35;

interface IComp {
  function getPriorVotes(address account, uint256 blockNumber) external view returns (uint96);
}
