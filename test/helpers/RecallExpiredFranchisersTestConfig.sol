// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {FranchiserExpiryFactory} from "franchiser-expiry/src/FranchiserExpiryFactory.sol";
import {RecallExpiredFranchisers} from "script/RecallExpiredFranchisers.s.sol";

// Test-only configuration for the expired-position sweep script. The mainnet concrete hardcodes
// its values as committed constants, but a fork test deploys the factory at an address that
// cannot be known ahead of time and varies the candidate list per test — so this config takes
// everything by constructor injection instead. All the substantive mechanics (filtering,
// validation, the recall broadcast) still run in the inherited abstract base.
contract RecallExpiredFranchisersTestConfig is RecallExpiredFranchisers {
  FranchiserExpiryFactory internal immutable FACTORY;
  address internal immutable OWNER;
  address[] internal delegatees;

  constructor(FranchiserExpiryFactory _factory, address _owner, address[] memory _delegatees) {
    FACTORY = _factory;
    OWNER = _owner;
    delegatees = _delegatees;
  }

  function _getRecallParams() internal view override returns (RecallParams memory) {
    return RecallParams({factory: FACTORY, owner: OWNER, delegatees: delegatees});
  }
}
