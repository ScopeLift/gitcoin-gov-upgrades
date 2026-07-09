// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {FranchiserExpiryFactory} from "franchiser-expiry/src/FranchiserExpiryFactory.sol";
import {ProposeFranchiserDelegation} from "script/ProposeFranchiserDelegation.s.sol";
import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";

/// @notice Mainnet configuration for a round of Franchiser delegations. Unlike the one-time
/// Governor upgrade proposal, this script is reused: each delegation round edits the delegatees,
/// amounts, expiration, and description below, and the edit is committed so the repository keeps
/// a history of every round the DAO has proposed.
contract ProposeFranchiserDelegationMainnet is ProposeFranchiserDelegation {
  // TODO: Set to the GitcoinGovernorWithGuardian address once it is deployed to mainnet and
  // controls the Timelock. The zero address makes this script revert until then.
  GitcoinGovernorWithGuardian constant GOVERNOR = GitcoinGovernorWithGuardian(payable(address(0)));

  // TODO: Set to the FranchiserExpiryFactory address once it is deployed to mainnet. The zero
  // address makes this script revert until then.
  FranchiserExpiryFactory constant FACTORY = FranchiserExpiryFactory(address(0));

  // TODO: Set to the delegate who will submit the proposal. They must hold or be delegated voting
  // weight of at least the Governor's proposal threshold. The zero address makes this script
  // revert until a proposer is confirmed.
  address constant PROPOSER = address(0);

  // TODO: Set to this round's expiration as a unix timestamp. Every position funded by this round
  // shares it, and funding a delegatee with a live position overwrites that position's
  // expiration. It must be far enough out to survive the full proposal pipeline — voting delay,
  // voting period, Timelock delay, and grace period — which the script enforces.
  uint256 constant EXPIRATION = 0;

  // TODO: Finalize this round's proposal text before proposing. This description is stored
  // on-chain (hashed) and displayed by governance UIs like Tally.
  string constant DESCRIPTION = "";

  // Boilerplate override so this file declares the public `run()` that scopelint's script rule
  // looks for; the mechanics all live in the base.
  function run() public override {
    super.run();
  }

  function _getProposalParams() internal pure override returns (ProposalParams memory) {
    // TODO: Populate this round's delegations. Each entry pairs a delegatee with the amount of
    // GTC to delegate to them; a zero amount adjusts the expiration of an existing position
    // without adding tokens. Empty arrays make this script revert until the round is filled in.
    // For example:
    //
    //   address[] memory _delegatees = new address[](2);
    //   uint256[] memory _amounts = new uint256[](2);
    //   _delegatees[0] = 0x0000000000000000000000000000000000000000;
    //   _amounts[0] = 500_000e18;
    //   _delegatees[1] = 0x0000000000000000000000000000000000000000;
    //   _amounts[1] = 250_000e18;
    address[] memory _delegatees = new address[](0);
    uint256[] memory _amounts = new uint256[](0);

    return ProposalParams({
      governor: GOVERNOR,
      factory: FACTORY,
      proposer: PROPOSER,
      delegatees: _delegatees,
      amounts: _amounts,
      expiration: EXPIRATION,
      description: DESCRIPTION
    });
  }
}
