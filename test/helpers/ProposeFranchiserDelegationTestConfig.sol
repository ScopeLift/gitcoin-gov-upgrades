// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {FranchiserExpiryFactory} from "franchiser-expiry/src/FranchiserExpiryFactory.sol";
import {ProposeFranchiserDelegation} from "script/ProposeFranchiserDelegation.s.sol";
import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";

// Test-only configuration for the Franchiser delegation proposal script. The mainnet concrete
// hardcodes its values as committed constants, but a fork test deploys the Governor and factory
// at addresses that cannot be known ahead of time and varies the delegation round per test — so
// this config takes everything by constructor injection instead. All the substantive mechanics
// (action construction, validation, submission) still run in the inherited abstract base.
contract ProposeFranchiserDelegationTestConfig is ProposeFranchiserDelegation {
  GitcoinGovernorWithGuardian internal immutable GOVERNOR;
  FranchiserExpiryFactory internal immutable FACTORY;
  address internal immutable PROPOSER;
  uint256 internal immutable EXPIRATION;
  address[] internal delegatees;
  uint256[] internal amounts;
  string internal description;

  constructor(
    GitcoinGovernorWithGuardian _governor,
    FranchiserExpiryFactory _factory,
    address _proposer,
    address[] memory _delegatees,
    uint256[] memory _amounts,
    uint256 _expiration,
    string memory _description
  ) {
    GOVERNOR = _governor;
    FACTORY = _factory;
    PROPOSER = _proposer;
    EXPIRATION = _expiration;
    delegatees = _delegatees;
    amounts = _amounts;
    description = _description;
  }

  function _getProposalParams() internal view override returns (ProposalParams memory) {
    return ProposalParams({
      governor: GOVERNOR,
      factory: FACTORY,
      proposer: PROPOSER,
      delegatees: delegatees,
      amounts: amounts,
      expiration: EXPIRATION,
      description: description
    });
  }
}
