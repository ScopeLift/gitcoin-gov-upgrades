// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

// `run()` is inherited from the abstract base; scopelint's per-file `script` rule does not resolve
// the inherited entrypoint, so this concrete config opts out of that check.
// scopelint: ignore-script-file

import {ICompoundTimelock} from "@openzeppelin/contracts/vendor/compound/ICompoundTimelock.sol";
import {DeployGitcoinGovernorWithGuardian} from "script/DeployGitcoinGovernorWithGuardian.s.sol";
import {IComp} from "src/interfaces/IComp.sol";

/// @notice Mainnet deployment configuration for the upgraded Gitcoin Governor.
/// @dev The governance parameters mirror the active "GTC Governor Bravo"
/// (0x9D4C63565D5618310271bF3F3c01b2954C1D1639) so the upgrade preserves current behavior. The
/// late-quorum vote extension is new to this Governor and has no precedent to carry over.
contract DeployGitcoinGovernorWithGuardianMainnet is DeployGitcoinGovernorWithGuardian {
  // TODO: Confirm the Governor name with Gitcoin stakeholders before deploying. It sets the EIP-712
  // domain separator used when signing votes; defaulted here to the active Governor's name for
  // continuity.
  string constant GOVERNOR_NAME = "GTC Governor Bravo";

  // Fixed values that can't change
  IComp constant GTC_TOKEN = IComp(0xDe30da39c46104798bB5aA3fe8B9e0e1F348163F);
  ICompoundTimelock constant TIMELOCK =
    ICompoundTimelock(payable(0x57a8865cfB1eCEf7253c27da6B4BC3dAEE5Be518));

  // Match the values from the existing Governor
  uint256 constant INITIAL_QUORUM = 2_500_000e18;
  uint48 constant INITIAL_VOTING_DELAY = 13_140;
  uint32 constant INITIAL_VOTING_PERIOD = 40_320;
  uint256 constant INITIAL_PROPOSAL_THRESHOLD = 150_000e18;

  // TODO: Validate the late-quorum vote extension with Gitcoin stakeholders before deploying. This
  // is a new parameter with no precedent in the active Governor; defaulted here to ~2 days (14,400
  // blocks at ~12s/block), the minimum window guaranteed between a proposal reaching quorum and its
  // voting period ending.
  uint48 constant INITIAL_VOTE_EXTENSION = 14_400;

  function _getDeploymentParams() internal pure override returns (DeploymentParams memory) {
    return DeploymentParams({
      name: GOVERNOR_NAME,
      initialQuorum: INITIAL_QUORUM,
      initialVoteExtension: INITIAL_VOTE_EXTENSION,
      initialVotingDelay: INITIAL_VOTING_DELAY,
      initialVotingPeriod: INITIAL_VOTING_PERIOD,
      initialProposalThreshold: INITIAL_PROPOSAL_THRESHOLD,
      token: GTC_TOKEN,
      timelock: TIMELOCK
    });
  }
}
