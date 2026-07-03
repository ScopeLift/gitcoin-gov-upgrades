// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";
import {IGovernorBravo} from "src/interfaces/IGovernorBravo.sol";
import {ProposeGovernorUpgrade} from "script/ProposeGovernorUpgrade.s.sol";

// Test-only configuration for the upgrade proposal script. The mainnet concrete hardcodes its
// values as committed constants, but a fork test deploys the new Governor at a nonce-dependent
// address that cannot be known ahead of time — so this config takes the values by constructor
// injection instead. All the substantive mechanics (action construction, validation, submission)
// still run in the inherited abstract base.
contract ProposeGovernorUpgradeTestConfig is ProposeGovernorUpgrade {
  IGovernorBravo internal immutable OLD_GOVERNOR;
  GitcoinGovernorWithGuardian internal immutable NEW_GOVERNOR;
  address internal immutable PROPOSER;
  string internal description;

  constructor(
    IGovernorBravo _oldGovernor,
    GitcoinGovernorWithGuardian _newGovernor,
    address _proposer,
    string memory _description
  ) {
    OLD_GOVERNOR = _oldGovernor;
    NEW_GOVERNOR = _newGovernor;
    PROPOSER = _proposer;
    description = _description;
  }

  function _getProposalParams() internal view override returns (ProposalParams memory) {
    return ProposalParams({
      oldGovernor: OLD_GOVERNOR,
      newGovernor: NEW_GOVERNOR,
      proposer: PROPOSER,
      description: description
    });
  }
}
