// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {FranchiserExpiryFactory} from "franchiser-expiry/src/FranchiserExpiryFactory.sol";
import {ProposeFranchiserRecall} from "script/ProposeFranchiserRecall.s.sol";
import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";

// Test-only configuration for the Franchiser recall proposal script. The mainnet concrete
// hardcodes its values as committed constants, but a fork test deploys the Governor and factory
// at addresses that cannot be known ahead of time and varies the recalled positions per test — so
// this config takes everything by constructor injection instead. All the substantive mechanics
// (action construction, validation, submission) still run in the inherited abstract base.
contract ProposeFranchiserRecallTestConfig is ProposeFranchiserRecall {
  GitcoinGovernorWithGuardian internal immutable GOVERNOR;
  FranchiserExpiryFactory internal immutable FACTORY;
  address internal immutable PROPOSER;
  address[] internal delegatees;
  address[] internal tokenRecipients;
  string internal description;

  constructor(
    GitcoinGovernorWithGuardian _governor,
    FranchiserExpiryFactory _factory,
    address _proposer,
    address[] memory _delegatees,
    address[] memory _tokenRecipients,
    string memory _description
  ) {
    GOVERNOR = _governor;
    FACTORY = _factory;
    PROPOSER = _proposer;
    delegatees = _delegatees;
    tokenRecipients = _tokenRecipients;
    description = _description;
  }

  function _getProposalParams() internal view override returns (ProposalParams memory) {
    return ProposalParams({
      governor: GOVERNOR,
      factory: FACTORY,
      proposer: PROPOSER,
      delegatees: delegatees,
      tokenRecipients: tokenRecipients,
      description: description
    });
  }
}
