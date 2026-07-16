// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Franchiser} from "franchiser-expiry/src/Franchiser.sol";
import {FranchiserExpiryFactory} from "franchiser-expiry/src/FranchiserExpiryFactory.sol";
import {FranchiserLens} from "franchiser-expiry/src/FranchiserLens.sol";
import {DeployFranchiserMainnet} from "script/DeployFranchiserMainnet.s.sol";
import {GitcoinGovernorPostUpgradeTestBase} from "test/helpers/GitcoinGovernorUpgradeTestBase.sol";
import {
  ProposeFranchiserDelegationTestConfig
} from "test/helpers/ProposeFranchiserDelegationTestConfig.sol";
import {
  ProposeFranchiserRecallTestConfig
} from "test/helpers/ProposeFranchiserRecallTestConfig.sol";
import {
  RecallExpiredFranchisersTestConfig
} from "test/helpers/RecallExpiredFranchisersTestConfig.sol";

// Shared base for the Franchiser fork integration suites. The full Governor upgrade executes in
// setUp — matching the production sequence, where Franchiser adoption follows the upgrade — and
// the Franchiser system then comes into being through its own provenance hook. Holds proposal
// mirrors for the operations scripts' actions and step helpers for driving each script and
// walking its proposal through the new Governor's lifecycle.
abstract contract PostUpgradeFranchiserTestBase is GitcoinGovernorPostUpgradeTestBase {
  // Mirrors the delegation script's block-time assumption for converting the Governor's
  // block-denominated voting pipeline into seconds when computing expirations.
  uint256 constant SECONDS_PER_BLOCK = 12;

  string constant DELEGATION_PROPOSAL_DESCRIPTION = "Delegate treasury GTC through the Franchiser";
  string constant RECALL_PROPOSAL_DESCRIPTION = "Recall Franchiser delegations to the Timelock";

  FranchiserExpiryFactory factory;
  FranchiserLens lens;

  function setUp() public virtual override {
    super.setUp();
    (factory, lens) = _fetchOrDeployFranchiser();
  }

  function _fetchOrDeployFranchiser()
    internal
    virtual
    returns (FranchiserExpiryFactory, FranchiserLens);

  //-------------------------- Provenance implementation helpers --------------------------//

  // Deploys the Franchiser system onto the fork by running the real mainnet deploy script,
  // exactly as the production deployment will run it.
  function _deployFranchiserWithMainnetScript()
    internal
    returns (FranchiserExpiryFactory, FranchiserLens)
  {
    DeployFranchiserMainnet _deployScript = new DeployFranchiserMainnet();
    _deployScript.disableLogging();
    _deployScript.run();
    return (_deployScript.factory(), _deployScript.lens());
  }

  //---------------------------------- Expiration helpers ----------------------------------//

  // The earliest expiration the delegation script accepts, mirroring its validation: the
  // proposal must remain executable through the voting pipeline, the Timelock delay, and the
  // grace period without the positions expiring.
  function _minimumExpiration() internal view returns (uint256) {
    return block.timestamp + SECONDS_PER_BLOCK * (governor.votingDelay() + governor.votingPeriod())
      + TIMELOCK.delay() + TIMELOCK.GRACE_PERIOD();
  }

  // A comfortably valid expiration for rounds whose expiry timing is not the point of the test.
  function _safeExpiration() internal view returns (uint256) {
    return _minimumExpiration() + 30 days;
  }

  //---------------------------------- Array construction ----------------------------------//

  function _asArray(address _single) internal pure returns (address[] memory _array) {
    _array = new address[](1);
    _array[0] = _single;
  }

  function _asArray(uint256 _single) internal pure returns (uint256[] memory _array) {
    _array = new uint256[](1);
    _array[0] = _single;
  }

  //----------------------------------- Proposal mirrors -----------------------------------//

  // The two actions of a delegation proposal, mirroring what the delegation script builds. The
  // submit helpers guard that the mirror is faithful by recomputing the script-returned proposal
  // id from these actions.
  function _delegationProposalDetails(
    address[] memory _delegatees,
    uint256[] memory _amounts,
    uint256 _expiration
  ) internal view returns (ProposalDetails memory _proposal) {
    uint256 _totalAmount = 0;
    for (uint256 _index = 0; _index < _amounts.length; _index += 1) {
      _totalAmount += _amounts[_index];
    }
    _proposal.targets = new address[](2);
    _proposal.values = new uint256[](2);
    _proposal.calldatas = new bytes[](2);
    _proposal.targets[0] = address(GTC_TOKEN);
    _proposal.calldatas[0] = abi.encodeCall(IERC20.approve, (address(factory), _totalAmount));
    _proposal.targets[1] = address(factory);
    _proposal.calldatas[1] = abi.encodeCall(factory.fundMany, (_delegatees, _amounts, _expiration));
    _proposal.description = DELEGATION_PROPOSAL_DESCRIPTION;
    _proposal.id = _hashProposal(_proposal);
  }

  // The single action of a recall proposal, mirroring what the recall script builds.
  function _recallProposalDetails(address[] memory _delegatees, address[] memory _tokenRecipients)
    internal
    view
    returns (ProposalDetails memory _proposal)
  {
    _proposal.targets = new address[](1);
    _proposal.values = new uint256[](1);
    _proposal.calldatas = new bytes[](1);
    _proposal.targets[0] = address(factory);
    _proposal.calldatas[0] = abi.encodeCall(factory.recallMany, (_delegatees, _tokenRecipients));
    _proposal.description = RECALL_PROPOSAL_DESCRIPTION;
    _proposal.id = _hashProposal(_proposal);
  }

  //---------------------------- Driving the operations scripts ----------------------------//

  // Submits a delegation round by running the proposal script, exactly as a delegate would, and
  // returns the mirrored proposal details for driving the proposal's lifecycle.
  function _submitDelegationRound(
    address[] memory _delegatees,
    uint256[] memory _amounts,
    uint256 _expiration
  ) internal returns (ProposalDetails memory _proposal) {
    ProposeFranchiserDelegationTestConfig _proposeScript = new ProposeFranchiserDelegationTestConfig(
      governor,
      factory,
      PROPOSER,
      _delegatees,
      _amounts,
      _expiration,
      DELEGATION_PROPOSAL_DESCRIPTION
    );
    _proposeScript.disableLogging();
    _proposeScript.run();
    _proposal = _delegationProposalDetails(_delegatees, _amounts, _expiration);
    _guardProposalId(
      _proposeScript.proposalId(),
      _proposal.id,
      "the delegation script vs the _delegationProposalDetails mirror"
    );
  }

  // Submits a recall round by running the proposal script, exactly as a delegate would, and
  // returns the mirrored proposal details for driving the proposal's lifecycle.
  function _submitRecallRound(address[] memory _delegatees, address[] memory _tokenRecipients)
    internal
    returns (ProposalDetails memory _proposal)
  {
    ProposeFranchiserRecallTestConfig _proposeScript = new ProposeFranchiserRecallTestConfig(
      governor, factory, PROPOSER, _delegatees, _tokenRecipients, RECALL_PROPOSAL_DESCRIPTION
    );
    _proposeScript.disableLogging();
    _proposeScript.run();
    _proposal = _recallProposalDetails(_delegatees, _tokenRecipients);
    _guardProposalId(
      _proposeScript.proposalId(),
      _proposal.id,
      "the recall script vs the _recallProposalDetails mirror"
    );
  }

  // Walks a proposal submitted by an operations script through the rest of its lifecycle: the
  // electorate passes it, then it is queued, waited out, and executed.
  function _passQueueAndExecuteSubmittedProposal(ProposalDetails memory _proposal) internal {
    _jumpToProposalActive(_proposal.id);
    _delegatesCastVotes(_proposal.id, FOR);
    _jumpPastProposalDeadline(_proposal.id);
    _guardProposalState(
      governor.state(_proposal.id),
      IGovernor.ProposalState.Succeeded,
      "after the electorate voted a script-submitted proposal through"
    );
    _queueProposal(_proposal);
    _jumpPastProposalEta(_proposal.id);
    _executeProposal(_proposal);
    _guardProposalState(
      governor.state(_proposal.id),
      IGovernor.ProposalState.Executed,
      "after executing a script-submitted proposal"
    );
  }

  // The full delegation journey: submit the round via the proposal script, pass, queue, execute.
  function _delegateViaProposal(
    address[] memory _delegatees,
    uint256[] memory _amounts,
    uint256 _expiration
  ) internal {
    ProposalDetails memory _proposal = _submitDelegationRound(_delegatees, _amounts, _expiration);
    _passQueueAndExecuteSubmittedProposal(_proposal);
  }

  function _delegateViaProposal(address _delegatee, uint256 _amount, uint256 _expiration) internal {
    _delegateViaProposal(_asArray(_delegatee), _asArray(_amount), _expiration);
  }

  // The full early-recall journey: submit the recall via the proposal script, pass, queue,
  // execute. Recalled tokens return to the Timelock.
  function _recallViaProposal(address _delegatee) internal {
    ProposalDetails memory _proposal =
      _submitRecallRound(_asArray(_delegatee), _asArray(address(TIMELOCK)));
    _passQueueAndExecuteSubmittedProposal(_proposal);
  }

  // Runs the permissionless sweep script over the candidate list and returns the script so tests
  // can assert what it recalled. The script broadcasts from Foundry's default sender — an
  // arbitrary EOA with no special standing, which is the point.
  function _sweepExpiredPositions(address[] memory _candidates)
    internal
    returns (RecallExpiredFranchisersTestConfig)
  {
    RecallExpiredFranchisersTestConfig _sweepScript =
      new RecallExpiredFranchisersTestConfig(factory, address(TIMELOCK), _candidates);
    _sweepScript.disableLogging();
    _sweepScript.run();
    return _sweepScript;
  }

  //----------------------------------- Franchiser lookups -----------------------------------//

  // The (deterministic) address of the Timelock's Franchiser for a delegatee, whether or not it
  // exists yet.
  function _franchiserFor(address _delegatee) internal view returns (Franchiser) {
    return factory.getFranchiser(address(TIMELOCK), _delegatee);
  }
}
