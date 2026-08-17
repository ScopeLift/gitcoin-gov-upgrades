// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {ICompoundTimelock} from "@openzeppelin/contracts/vendor/compound/ICompoundTimelock.sol";
import {DeployGitcoinGovernorWithGuardian} from "script/DeployGitcoinGovernorWithGuardian.s.sol";
import {IComp} from "src/interfaces/IComp.sol";

/// @notice Mainnet deployment configuration for the upgraded Gitcoin Governor.
/// @dev The proposal threshold and voting period mirror the active "GTC Governor Bravo"
/// (0x9D4C63565D5618310271bF3F3c01b2954C1D1639). The quorum, voting delay, late-quorum vote
/// extension, Proposal Guardian, and name are configured specifically for this upgrade.
contract DeployGitcoinGovernorWithGuardianMainnet is DeployGitcoinGovernorWithGuardian {
  // Sets the EIP-712 domain name used when signing votes.
  string constant GOVERNOR_NAME = "Gitcoin Governor Charlie";

  // Fixed values that can't change
  IComp constant GTC_TOKEN = IComp(0xDe30da39c46104798bB5aA3fe8B9e0e1F348163F);
  ICompoundTimelock constant TIMELOCK =
    ICompoundTimelock(payable(0x57a8865cfB1eCEf7253c27da6B4BC3dAEE5Be518));

  // Governance parameters confirmed for the upgrade. The voting period and proposal threshold
  // remain unchanged from the existing Governor.
  uint256 constant INITIAL_QUORUM = 1_500_000e18;
  uint48 constant INITIAL_VOTING_DELAY = 14_400;
  uint32 constant INITIAL_VOTING_PERIOD = 40_320;
  uint256 constant INITIAL_PROPOSAL_THRESHOLD = 150_000e18;

  // Guarantees approximately 24 hours between a proposal reaching quorum and voting ending,
  // assuming 12-second blocks.
  uint48 constant INITIAL_VOTE_EXTENSION = 7200;

  // Gitcoin's designated Proposal Guardian.
  address constant INITIAL_PROPOSAL_GUARDIAN = 0x5743E35477363241300FcEdc2F5eB0195F300817;

  // Boilerplate override so this file declares the public `run()` that scopelint's script rule
  // looks for; the mechanics all live in the base.
  function run() public override {
    DeployGitcoinGovernorWithGuardian.run();
  }

  function _getDeploymentParams() internal pure override returns (DeploymentParams memory) {
    return DeploymentParams({
      name: GOVERNOR_NAME,
      initialQuorum: INITIAL_QUORUM,
      initialVoteExtension: INITIAL_VOTE_EXTENSION,
      initialVotingDelay: INITIAL_VOTING_DELAY,
      initialVotingPeriod: INITIAL_VOTING_PERIOD,
      initialProposalThreshold: INITIAL_PROPOSAL_THRESHOLD,
      token: GTC_TOKEN,
      timelock: TIMELOCK,
      initialProposalGuardian: INITIAL_PROPOSAL_GUARDIAN
    });
  }
}
