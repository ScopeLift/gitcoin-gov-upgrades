// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

// Test-only interface for the COMP-style GTC token, covering the functions the integration tests
// use to move tokens, read delegates' voting weight, and manufacture a key-controlled voter for
// the vote-by-signature journey. The production contracts only need the narrower
// `src/interfaces/IComp.sol`.
interface IGtc {
  function balanceOf(address _account) external view returns (uint256);
  function transfer(address _to, uint256 _amount) external returns (bool);
  function delegate(address _delegatee) external;
  function getCurrentVotes(address _account) external view returns (uint96);
}
