// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";
import {IGovernorBravo} from "src/interfaces/IGovernorBravo.sol";
import {ProposeGovernorUpgrade} from "script/ProposeGovernorUpgrade.s.sol";

/// @notice Mainnet configuration for the Governor upgrade proposal, submitted to the active
/// "GTC Governor Bravo" to transfer Timelock control to the new `GitcoinGovernorWithGuardian`.
contract ProposeGovernorUpgradeMainnet is ProposeGovernorUpgrade {
  IGovernorBravo constant OLD_GOVERNOR = IGovernorBravo(0x9D4C63565D5618310271bF3F3c01b2954C1D1639);

  // Gitcoin Governor Charlie, deployed to mainnet on August 17, 2026.
  GitcoinGovernorWithGuardian constant NEW_GOVERNOR =
    GitcoinGovernorWithGuardian(payable(0xef41CbD211076E8b1901e214Bf751d404cf06638));

  // TODO: Set to the delegate who will submit the proposal. They must hold or be delegated voting
  // weight of at least the old Governor's proposal threshold. The zero address makes this script
  // revert until a proposer is confirmed.
  address constant PROPOSER = address(0);

  // TODO: Finalize the proposal text with Gitcoin stakeholders before proposing. This description
  // is stored on-chain (hashed) and displayed by governance UIs like Tally.
  string constant DESCRIPTION = "Upgrade the Gitcoin Governor: transfer Timelock admin rights from"
    " the current Governor to the new GitcoinGovernorWithGuardian, which adds a proposal guardian,"
    " late-quorum protection, and a DAO-settable quorum.";

  // Boilerplate override so this file declares the public `run()` that scopelint's script rule
  // looks for; the mechanics all live in the base.
  function run() public override {
    super.run();
  }

  function _getProposalParams() internal pure override returns (ProposalParams memory) {
    return ProposalParams({
      oldGovernor: OLD_GOVERNOR,
      newGovernor: NEW_GOVERNOR,
      proposer: PROPOSER,
      description: DESCRIPTION
    });
  }
}
