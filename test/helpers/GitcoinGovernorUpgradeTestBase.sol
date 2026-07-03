// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {ICompoundTimelock} from "@openzeppelin/contracts/vendor/compound/ICompoundTimelock.sol";
import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";
import {IGovernorBravo} from "src/interfaces/IGovernorBravo.sol";
import {
  DeployGitcoinGovernorWithGuardianMainnet
} from "script/DeployGitcoinGovernorWithGuardianMainnet.s.sol";
import {IGtc} from "test/helpers/IGtc.sol";
import {ProposeGovernorUpgradeTestConfig} from "test/helpers/ProposeGovernorUpgradeTestConfig.sol";

// Shared base for the mainnet fork integration suites. Holds the provenance abstraction (how the
// system under test comes into being), the real-delegate electorate, and step helpers for
// walking proposals through their lifecycle on both the old and the new Governor.
abstract contract GitcoinGovernorUpgradeTestBase is Test {
  // Vote support values shared by both governors' bravo-style counting.
  uint8 constant AGAINST = 0;
  uint8 constant FOR = 1;
  uint8 constant ABSTAIN = 2;
  // The support value GovernorCountingFractional reserves for fractional votes.
  uint8 constant VOTE_TYPE_FRACTIONAL = 255;

  uint256 constant FORK_BLOCK = 25_453_000;

  IGovernorBravo constant OLD_GOVERNOR = IGovernorBravo(0x9D4C63565D5618310271bF3F3c01b2954C1D1639);
  IGtc constant GTC_TOKEN = IGtc(0xDe30da39c46104798bB5aA3fe8B9e0e1F348163F);
  ICompoundTimelock constant TIMELOCK =
    ICompoundTimelock(payable(0x57a8865cfB1eCEf7253c27da6B4BC3dAEE5Be518));

  // kbw.eth — a real delegate whose voting weight (~485k GTC at FORK_BLOCK) clears the 150k
  // proposal threshold on both governors (guarded in setUp).
  address constant PROPOSER = 0xc2E2B715d9e302947Ec7e312fd2384b5a1296099;

  // Real Gitcoin delegates who, together with the PROPOSER, form the test electorate. Approximate
  // voting weights at FORK_BLOCK are noted; live weights are fetched in setUp.
  address constant KEV = 0x00De4B13153673BCAE2616b67bf822500d325Fc3; // kev.eth, ~1.56M GTC
  address constant ANON_GNOSIS_SAFE = 0x93F80a67FdFDF9DaF1aee5276Db95c8761cc8561; // ~500k GTC
  // eventhorizoncommunity.eth, ~152k GTC
  address constant EVENT_HORIZON = 0xb35659cbac913D5E4119F2Af47fD490A45e2c826;
  address constant LEFTERIS = 0x2B888954421b424C5D3D9Ce9bB67c9bD47537d12; // lefteris.eth, ~100k GTC
  address constant CERV1 = 0x5a5D9aB7b1bD978F80909503EBb828879daCa9C3; // cerv1.eth, ~90k GTC

  // Governance parameters of the active Governor at FORK_BLOCK, mirrored by the new Governor's
  // mainnet deploy config.
  uint256 constant QUORUM = 2_500_000e18;
  uint48 constant VOTE_EXTENSION = 14_400;

  // Floors on the Timelock's real treasury holdings, guarded in setUp: the send tests draw on
  // the Timelock's genuine balances rather than manufactured ones, and need enough behind them
  // to stay representative. At FORK_BLOCK the Timelock holds ~12.5M GTC and ~139 ETH.
  uint256 constant MIN_TIMELOCK_GTC_BALANCE = 1_000_000e18;
  uint256 constant MIN_TIMELOCK_ETH_BALANCE = 10 ether;

  string constant UPGRADE_PROPOSAL_DESCRIPTION =
    "Upgrade the Gitcoin Governor to GitcoinGovernorWithGuardian";

  // Bundles everything needed to drive one proposal through either governor's lifecycle.
  struct ProposalDetails {
    address[] targets;
    uint256[] values;
    bytes[] calldatas;
    string description;
    uint256 id;
  }

  GitcoinGovernorWithGuardian governor;
  uint256 upgradeProposalId;

  // The electorate: real delegates whose live voting weights are read from the fork in setUp.
  // Combined they must clear the 2.5M quorum — asserted in setUp so that a fork-block bump that
  // erodes their weight fails loudly rather than silently changing what the tests exercise.
  // Weights are stored at GTC's native uint96 checkpoint width so that vote math over them can
  // widen into narrower types (e.g. the uint128 fields of a fractional vote) without unsafe
  // casts.
  address[] delegates;
  mapping(address delegate => uint96 weight) delegateWeights;
  uint256 totalDelegateWeight;

  function setUp() public virtual {
    _setUpNetwork();
    governor = _fetchOrDeploySystem();

    delegates.push(KEV);
    delegates.push(ANON_GNOSIS_SAFE);
    delegates.push(PROPOSER);
    delegates.push(EVENT_HORIZON);
    delegates.push(LEFTERIS);
    delegates.push(CERV1);
    for (uint256 _index = 0; _index < delegates.length; _index += 1) {
      uint96 _weight = GTC_TOKEN.getCurrentVotes(delegates[_index]);
      delegateWeights[delegates[_index]] = _weight;
      totalDelegateWeight += _weight;
    }

    // Guards on the assumptions the suites make about the forked state. These revert rather
    // than assert: a failure here means the test setup no longer holds — not that a behavior
    // under test regressed. Each message is aimed at a future developer bumping FORK_BLOCK.
    for (uint256 _index = 0; _index < delegates.length; _index += 1) {
      if (delegateWeights[delegates[_index]] == 0) {
        revert(
          string.concat(
            "Delegate ",
            vm.toString(delegates[_index]),
            " has no voting weight at FORK_BLOCK; replace them in the electorate"
          )
        );
      }
    }
    if (totalDelegateWeight < QUORUM) {
      revert(
        string.concat(
          "The test electorate's combined weight of ",
          vm.toString(totalDelegateWeight),
          " no longer clears the quorum of ",
          vm.toString(QUORUM),
          "; refresh the delegate set for this fork block"
        )
      );
    }
    if (_votingWeightOf(PROPOSER) < OLD_GOVERNOR.proposalThreshold()) {
      revert(
        string.concat(
          "The PROPOSER's voting weight of ",
          vm.toString(_votingWeightOf(PROPOSER)),
          " no longer clears the proposal threshold of ",
          vm.toString(OLD_GOVERNOR.proposalThreshold()),
          "; choose a new proposer for this fork block"
        )
      );
    }
    if (GTC_TOKEN.balanceOf(address(TIMELOCK)) < MIN_TIMELOCK_GTC_BALANCE) {
      revert(
        "The Timelock holds too little GTC for representative treasury tests; revisit FORK_BLOCK"
      );
    }
    if (address(TIMELOCK).balance < MIN_TIMELOCK_ETH_BALANCE) {
      revert(
        "The Timelock holds too little ETH for representative treasury tests; revisit FORK_BLOCK"
      );
    }
  }

  function _setUpNetwork() internal virtual;

  function _fetchOrDeploySystem() internal virtual returns (GitcoinGovernorWithGuardian);

  //-------------------------- Provenance implementation helpers --------------------------//
  // Provenance concretes at the bottom of each test file implement the two methods above with
  // one-line delegations to these helpers.

  function _createMainnetFork() internal {
    vm.createSelectFork("mainnet", FORK_BLOCK);
  }

  // Deploys the new Governor onto the fork by running the real mainnet deploy script, exactly as
  // the production deployment will run it.
  function _deployGovernorWithMainnetScript() internal returns (GitcoinGovernorWithGuardian) {
    DeployGitcoinGovernorWithGuardianMainnet _deployScript =
      new DeployGitcoinGovernorWithGuardianMainnet();
    _deployScript.disableLogging();
    _deployScript.run();
    return _deployScript.governor();
  }

  //---------------------------------- Electorate helpers ----------------------------------//

  // A delegate's voting weight as read from the fork in setUp. Stable for the run: nothing in
  // the tests re-delegates, and GTC moved by proposals is not delegated on either end.
  function _votingWeightOf(address _delegate) internal view returns (uint96) {
    return delegateWeights[_delegate];
  }

  //---------------------------------- Proposal construction ----------------------------------//

  function _buildProposal(
    address _target,
    uint256 _value,
    bytes memory _calldata,
    string memory _description
  ) internal pure returns (ProposalDetails memory _proposal) {
    _proposal.targets = new address[](1);
    _proposal.values = new uint256[](1);
    _proposal.calldatas = new bytes[](1);
    _proposal.targets[0] = _target;
    _proposal.values[0] = _value;
    _proposal.calldatas[0] = _calldata;
    _proposal.description = _description;
    _proposal.id = _hashProposal(_proposal);
  }

  function _buildGtcSendProposal(address _receiver, uint256 _amount, string memory _description)
    internal
    pure
    returns (ProposalDetails memory)
  {
    return _buildProposal(
      address(GTC_TOKEN), 0, abi.encodeCall(IGtc.transfer, (_receiver, _amount)), _description
    );
  }

  // Both governors compute proposal ids identically: the OpenZeppelin hash of the actions and
  // the description hash.
  function _hashProposal(ProposalDetails memory _proposal) internal pure returns (uint256) {
    return uint256(
      keccak256(
        abi.encode(
          _proposal.targets,
          _proposal.values,
          _proposal.calldatas,
          keccak256(bytes(_proposal.description))
        )
      )
    );
  }

  // The two actions of the upgrade proposal, mirroring what the proposal script builds. The
  // tests assert the mirror is faithful by recomputing the script-returned proposal id from
  // these actions.
  function _upgradeProposalDetails() internal view returns (ProposalDetails memory _proposal) {
    _proposal.targets = new address[](2);
    _proposal.values = new uint256[](2);
    _proposal.calldatas = new bytes[](2);
    _proposal.targets[0] = address(TIMELOCK);
    _proposal.calldatas[0] = abi.encodeCall(ICompoundTimelock.setPendingAdmin, (address(governor)));
    _proposal.targets[1] = address(governor);
    _proposal.calldatas[1] = abi.encodeCall(governor.__acceptAdmin, ());
    _proposal.description = UPGRADE_PROPOSAL_DESCRIPTION;
    _proposal.id = _hashProposal(_proposal);
  }

  //----------------------------- Upgrade proposal (old Governor) -----------------------------//

  // Submits the upgrade proposal by running the proposal script, exactly as a delegate would.
  function _submitUpgradeProposal() internal {
    ProposeGovernorUpgradeTestConfig _proposeScript = new ProposeGovernorUpgradeTestConfig(
      OLD_GOVERNOR, governor, PROPOSER, UPGRADE_PROPOSAL_DESCRIPTION
    );
    _proposeScript.disableLogging();
    _proposeScript.run();
    upgradeProposalId = _proposeScript.proposalId();
  }

  function _jumpToUpgradeProposalActive() internal {
    vm.roll(OLD_GOVERNOR.proposalSnapshot(upgradeProposalId) + 1);
    assertEq(OLD_GOVERNOR.state(upgradeProposalId), IGovernor.ProposalState.Active);
  }

  function _jumpPastUpgradeProposalDeadline() internal {
    vm.roll(OLD_GOVERNOR.proposalDeadline(upgradeProposalId) + 1);
  }

  function _passUpgradeProposal() internal {
    _jumpToUpgradeProposalActive();
    _delegatesCastVotesOnOldGovernor(upgradeProposalId, FOR);
    _jumpPastUpgradeProposalDeadline();
  }

  function _defeatUpgradeProposal() internal {
    _jumpToUpgradeProposalActive();
    _delegatesCastVotesOnOldGovernor(upgradeProposalId, AGAINST);
    _jumpPastUpgradeProposalDeadline();
  }

  function _queueUpgradeProposal() internal {
    ProposalDetails memory _proposal = _upgradeProposalDetails();
    OLD_GOVERNOR.queue(
      _proposal.targets,
      _proposal.values,
      _proposal.calldatas,
      keccak256(bytes(_proposal.description))
    );
  }

  function _jumpPastUpgradeProposalEta() internal {
    vm.roll(block.number + 1);
    vm.warp(OLD_GOVERNOR.proposalEta(upgradeProposalId) + 1);
  }

  function _executeUpgradeProposal() internal {
    ProposalDetails memory _proposal = _upgradeProposalDetails();
    OLD_GOVERNOR.execute(
      _proposal.targets,
      _proposal.values,
      _proposal.calldatas,
      keccak256(bytes(_proposal.description))
    );
  }

  // The full upgrade journey: submit via the proposal script, pass, queue, wait out the
  // Timelock delay, execute, and confirm the new Governor now controls the Timelock.
  function _upgradeToNewGovernor() internal {
    _submitUpgradeProposal();
    _passUpgradeProposal();
    _queueUpgradeProposal();
    _jumpPastUpgradeProposalEta();
    _executeUpgradeProposal();
    assertEq(TIMELOCK.admin(), address(governor));
  }

  //------------------------- Arbitrary proposals on the old Governor -------------------------//

  function _submitProposalToOldGovernor(ProposalDetails memory _proposal) internal {
    vm.prank(PROPOSER);
    uint256 _id = OLD_GOVERNOR.propose(
      _proposal.targets, _proposal.values, _proposal.calldatas, _proposal.description
    );
    assertEq(_id, _proposal.id);
  }

  function _delegatesCastVotesOnOldGovernor(uint256 _proposalId, uint8 _support) internal {
    for (uint256 _index = 0; _index < delegates.length; _index += 1) {
      vm.prank(delegates[_index]);
      OLD_GOVERNOR.castVote(_proposalId, _support);
    }
  }

  function _submitAndPassProposalOnOldGovernor(ProposalDetails memory _proposal) internal {
    _submitProposalToOldGovernor(_proposal);
    vm.roll(OLD_GOVERNOR.proposalSnapshot(_proposal.id) + 1);
    _delegatesCastVotesOnOldGovernor(_proposal.id, FOR);
    vm.roll(OLD_GOVERNOR.proposalDeadline(_proposal.id) + 1);
    assertEq(OLD_GOVERNOR.state(_proposal.id), IGovernor.ProposalState.Succeeded);
  }

  // Queues a succeeded proposal on the old Governor, waits out the Timelock delay, and executes.
  function _queueAndExecuteProposalOnOldGovernor(ProposalDetails memory _proposal) internal {
    OLD_GOVERNOR.queue(
      _proposal.targets,
      _proposal.values,
      _proposal.calldatas,
      keccak256(bytes(_proposal.description))
    );
    vm.roll(block.number + 1);
    vm.warp(OLD_GOVERNOR.proposalEta(_proposal.id) + 1);
    OLD_GOVERNOR.execute(
      _proposal.targets,
      _proposal.values,
      _proposal.calldatas,
      keccak256(bytes(_proposal.description))
    );
    assertEq(OLD_GOVERNOR.state(_proposal.id), IGovernor.ProposalState.Executed);
  }

  //------------------------------ Proposals on the new Governor ------------------------------//

  function _submitProposal(ProposalDetails memory _proposal) internal {
    vm.prank(PROPOSER);
    uint256 _id = governor.propose(
      _proposal.targets, _proposal.values, _proposal.calldatas, _proposal.description
    );
    assertEq(_id, _proposal.id);
    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Pending);
  }

  function _jumpToProposalActive(uint256 _proposalId) internal {
    vm.roll(governor.proposalSnapshot(_proposalId) + 1);
    assertEq(governor.state(_proposalId), IGovernor.ProposalState.Active);
  }

  function _castVote(address _voter, uint256 _proposalId, uint8 _support) internal {
    vm.prank(_voter);
    governor.castVote(_proposalId, _support);
  }

  function _delegatesCastVotes(uint256 _proposalId, uint8 _support) internal {
    for (uint256 _index = 0; _index < delegates.length; _index += 1) {
      _castVote(delegates[_index], _proposalId, _support);
    }
  }

  // Casts a vote from every electorate member except one — used by tests that need a tally
  // sitting between the excluded delegate's weight and the full electorate's.
  function _delegatesCastVotesExcept(uint256 _proposalId, uint8 _support, address _excluded)
    internal
  {
    for (uint256 _index = 0; _index < delegates.length; _index += 1) {
      if (delegates[_index] == _excluded) {
        continue;
      }
      _castVote(delegates[_index], _proposalId, _support);
    }
  }

  function _jumpPastProposalDeadline(uint256 _proposalId) internal {
    vm.roll(governor.proposalDeadline(_proposalId) + 1);
  }

  function _queueProposal(ProposalDetails memory _proposal) internal {
    governor.queue(
      _proposal.targets,
      _proposal.values,
      _proposal.calldatas,
      keccak256(bytes(_proposal.description))
    );
  }

  function _jumpPastProposalEta(uint256 _proposalId) internal {
    vm.roll(block.number + 1);
    vm.warp(governor.proposalEta(_proposalId) + 1);
  }

  function _executeProposal(ProposalDetails memory _proposal) internal {
    governor.execute(
      _proposal.targets,
      _proposal.values,
      _proposal.calldatas,
      keccak256(bytes(_proposal.description))
    );
  }

  function _submitAndPassProposal(ProposalDetails memory _proposal) internal {
    _submitProposal(_proposal);
    _jumpToProposalActive(_proposal.id);
    _delegatesCastVotes(_proposal.id, FOR);
    _jumpPastProposalDeadline(_proposal.id);
    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Succeeded);
  }

  function _submitPassQueueAndExecuteProposal(ProposalDetails memory _proposal) internal {
    _submitAndPassProposal(_proposal);
    _queueProposal(_proposal);
    _jumpPastProposalEta(_proposal.id);
    _executeProposal(_proposal);
    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Executed);
  }

  //----------------------------------------- Misc -----------------------------------------//

  // The hash under which the Compound Timelock stores a queued transaction. The new Governor
  // queues every action with an empty signature and the proposal's eta.
  function _timelockTransactionHash(
    address _target,
    uint256 _value,
    bytes memory _data,
    uint256 _eta
  ) internal pure returns (bytes32) {
    return keccak256(abi.encode(_target, _value, "", _data, _eta));
  }

  function assertEq(IGovernor.ProposalState _actual, IGovernor.ProposalState _expected)
    internal
    pure
  {
    assertEq(uint8(_actual), uint8(_expected));
  }
}

// Base for suites that exercise the new Governor after the upgrade: the full adoption journey
// (deploy, propose, vote, queue, execute) runs once in setUp, so every test starts from a state
// where the new Governor controls the Timelock.
abstract contract GitcoinGovernorPostUpgradeTestBase is GitcoinGovernorUpgradeTestBase {
  function setUp() public virtual override {
    super.setUp();
    _upgradeToNewGovernor();
  }
}
