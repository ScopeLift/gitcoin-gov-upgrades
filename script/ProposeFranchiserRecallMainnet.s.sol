// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {FranchiserExpiryFactory} from "franchiser-expiry/src/FranchiserExpiryFactory.sol";
import {ProposeFranchiserRecall} from "script/ProposeFranchiserRecall.s.sol";
import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";

/// @notice Mainnet configuration for a Franchiser recall proposal, the DAO's lever for unwinding
/// delegations before they expire. Like the delegation script, it is reused: each recall edits
/// the delegatees and recipients below, and the edit is committed so the repository keeps a
/// history. Expired positions do not need a proposal — anyone can return those to the Timelock
/// with `RecallExpiredFranchisersMainnet`.
contract ProposeFranchiserRecallMainnet is ProposeFranchiserRecall {
  // Fixed value that can't change; the ordinary recipient of recalled tokens.
  address constant TIMELOCK = 0x57a8865cfB1eCEf7253c27da6B4BC3dAEE5Be518;

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

  // TODO: Finalize the proposal text before proposing. This description is stored on-chain
  // (hashed) and displayed by governance UIs like Tally.
  string constant DESCRIPTION = "";

  // Boilerplate override so this file declares the public `run()` that scopelint's script rule
  // looks for; the mechanics all live in the base.
  function run() public override {
    super.run();
  }

  function _getProposalParams() internal pure override returns (ProposalParams memory) {
    // TODO: Populate the positions this proposal recalls. Each entry pairs a delegatee whose
    // position is being unwound with the recipient of the recalled tokens — ordinarily TIMELOCK;
    // any other recipient triggers a prominent dry-run warning. Empty arrays make this script
    // revert until the recall is filled in. For example:
    //
    //   address[] memory _delegatees = new address[](1);
    //   address[] memory _tokenRecipients = new address[](1);
    //   _delegatees[0] = 0x0000000000000000000000000000000000000000;
    //   _tokenRecipients[0] = TIMELOCK;
    address[] memory _delegatees = new address[](0);
    address[] memory _tokenRecipients = new address[](0);

    return ProposalParams({
      governor: GOVERNOR,
      factory: FACTORY,
      proposer: PROPOSER,
      delegatees: _delegatees,
      tokenRecipients: _tokenRecipients,
      description: DESCRIPTION
    });
  }
}
