// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {Test, Vm} from "forge-std/Test.sol";
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
// system under test and its upgrade proposal come into being), the real-delegate electorate, and
// step helpers for walking proposals through their lifecycle on both the old and the new
// Governor.
abstract contract GitcoinGovernorUpgradeTestBase is Test {
  // Vote support values shared by both governors' bravo-style counting.
  uint8 constant AGAINST = 0;
  uint8 constant FOR = 1;
  uint8 constant ABSTAIN = 2;
  // The support value GovernorCountingFractional reserves for fractional votes.
  uint8 constant VOTE_TYPE_FRACTIONAL = 255;

  uint256 constant GOVERNOR_PRE_DEPLOYMENT_BLOCK = 25_453_000;
  uint256 constant GOVERNOR_POST_DEPLOYMENT_BLOCK = 25_776_743;
  // The upgrade proposal was submitted to the old Governor on mainnet in transaction
  // 0xb589c7fcb916860feefeef54da017800787e48952fc739b6d1ab50b34ca77e89.
  uint256 constant UPGRADE_PROPOSAL_SUBMISSION_BLOCK = 26_041_897;
  uint256 constant UPGRADE_PROPOSAL_POST_SUBMISSION_BLOCK = 26_041_898;

  IGovernorBravo constant OLD_GOVERNOR = IGovernorBravo(0x9D4C63565D5618310271bF3F3c01b2954C1D1639);
  GitcoinGovernorWithGuardian constant DEPLOYED_GOVERNOR =
    GitcoinGovernorWithGuardian(payable(0xef41CbD211076E8b1901e214Bf751d404cf06638));
  IGtc constant GTC_TOKEN = IGtc(0xDe30da39c46104798bB5aA3fe8B9e0e1F348163F);
  ICompoundTimelock constant TIMELOCK =
    ICompoundTimelock(payable(0x57a8865cfB1eCEf7253c27da6B4BC3dAEE5Be518));
  address constant PROPOSAL_GUARDIAN = 0x5743E35477363241300FcEdc2F5eB0195F300817;
  uint256 constant SUBMITTED_UPGRADE_PROPOSAL_ID =
    0xefb5ffee46ab14020294f926e242a2fa79f096de6577be73d69429207a464489;

  // kbw.eth — a real delegate whose voting weight (~485k GTC at the pre-deployment block) clears
  // the 150k
  // proposal threshold on both governors (guarded in setUp).
  address constant PROPOSER = 0xc2E2B715d9e302947Ec7e312fd2384b5a1296099;

  // Real Gitcoin delegates who, together with the PROPOSER, form the test electorate. Approximate
  // voting weights at the pre-deployment block are noted; live weights are fetched in setUp.
  address constant KEV = 0x00De4B13153673BCAE2616b67bf822500d325Fc3; // kev.eth, ~1.56M GTC
  address constant ANON_GNOSIS_SAFE = 0x93F80a67FdFDF9DaF1aee5276Db95c8761cc8561; // ~500k GTC
  // eventhorizoncommunity.eth, ~152k GTC
  address constant EVENT_HORIZON = 0xb35659cbac913D5E4119F2Af47fD490A45e2c826;
  address constant LEFTERIS = 0x2B888954421b424C5D3D9Ce9bB67c9bD47537d12; // lefteris.eth, ~100k GTC
  address constant CERV1 = 0x5a5D9aB7b1bD978F80909503EBb828879daCa9C3; // cerv1.eth, ~90k GTC

  // New governance parameters supplied by the mainnet deploy config.
  uint256 constant QUORUM = 1_500_000e18;
  uint48 constant VOTE_EXTENSION = 7200;

  // Floors on the Timelock's real treasury holdings, guarded in setUp: the send tests draw on
  // the Timelock's genuine balances rather than manufactured ones, and need enough behind them
  // to stay representative. At the pre-deployment block the Timelock holds ~12.5M GTC and ~139
  // ETH.
  uint256 constant MIN_TIMELOCK_GTC_BALANCE = 1_000_000e18;
  uint256 constant MIN_TIMELOCK_ETH_BALANCE = 10 ether;

  // The description the proposal script submits under the provenances that submit the upgrade
  // proposal themselves; the proposal already on mainnet carries its own.
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
  // The upgrade proposal on the old Governor, set by _proposeUpgrade from the concrete's
  // provenance. The description is tracked alongside the id because it is hashed into it.
  uint256 upgradeProposalId;
  string upgradeProposalDescription;

  // The electorate: real delegates whose live voting weights are read from the fork in setUp.
  // Combined they must clear the 1.5M quorum — asserted in setUp so that a fork-block bump that
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
    // under test regressed. Each message is aimed at a future developer bumping a fork block.
    for (uint256 _index = 0; _index < delegates.length; _index += 1) {
      if (delegateWeights[delegates[_index]] == 0) {
        revert(
          string.concat(
            "Delegate ",
            vm.toString(delegates[_index]),
            " has no voting weight at the pinned fork block; replace them in the electorate"
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
        "The Timelock holds too little GTC for representative treasury tests; revisit the fork block"
      );
    }
    if (address(TIMELOCK).balance < MIN_TIMELOCK_ETH_BALANCE) {
      revert(
        "The Timelock holds too little ETH for representative treasury tests; revisit the fork block"
      );
    }
  }

  function _setUpNetwork() internal virtual;

  function _fetchOrDeploySystem() internal virtual returns (GitcoinGovernorWithGuardian);

  // Produces the upgrade proposal on the old Governor and returns its id and description. Unlike
  // the two hooks above, setUp does not call this one: tests reach it through _proposeUpgrade at
  // the point in their flow where the upgrade is proposed.
  function _fetchOrSubmitUpgradeProposal() internal virtual returns (uint256, string memory);

  //-------------------------- Provenance implementation helpers --------------------------//
  // Provenance concretes at the bottom of each test file implement the hooks above with
  // one-line delegations to these helpers.

  function _createMainnetFork() internal {
    vm.createSelectFork("mainnet", GOVERNOR_PRE_DEPLOYMENT_BLOCK);
  }

  function _createMainnetGovernorPostDeploymentFork() internal {
    vm.createSelectFork("mainnet", GOVERNOR_POST_DEPLOYMENT_BLOCK);
  }

  function _createMainnetUpgradeProposalPostSubmissionFork() internal {
    vm.createSelectFork("mainnet", UPGRADE_PROPOSAL_POST_SUBMISSION_BLOCK);
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

  // Binds the system under test to the Governor deployed on mainnet, exercising its actual
  // production bytecode rather than a fresh deployment of the same source.
  function _fetchDeployedGovernor() internal view returns (GitcoinGovernorWithGuardian) {
    if (address(DEPLOYED_GOVERNOR).code.length == 0) {
      revert(
        "The deployed Governor has no code at GOVERNOR_POST_DEPLOYMENT_BLOCK; "
        "repair its address or pinned deployment block"
      );
    }
    return DEPLOYED_GOVERNOR;
  }

  // Submits the upgrade proposal by running the proposal script, exactly as a delegate would.
  function _submitUpgradeProposalWithScript() internal returns (uint256, string memory) {
    ProposeGovernorUpgradeTestConfig _proposeScript = new ProposeGovernorUpgradeTestConfig(
      OLD_GOVERNOR, governor, PROPOSER, UPGRADE_PROPOSAL_DESCRIPTION
    );
    _proposeScript.disableLogging();
    _proposeScript.run();
    return (_proposeScript.proposalId(), UPGRADE_PROPOSAL_DESCRIPTION);
  }

  // Binds to the upgrade proposal already submitted on mainnet, reading its id and description
  // from the ProposalCreated event the old Governor emitted. The event's actions are left unread
  // on purpose: the tests pair the live description with the actions the _upgradeProposalDetails
  // mirror expects, so the ids matching proves the live proposal carries exactly those actions.
  function _fetchSubmittedUpgradeProposal() internal view returns (uint256, string memory) {
    // The old Governor emits ProposalCreated with the same signature as OZ v5's IGovernor.
    bytes32[] memory _topics = new bytes32[](1);
    _topics[0] = IGovernor.ProposalCreated.selector;
    Vm.EthGetLogs[] memory _logs = vm.eth_getLogs(
      UPGRADE_PROPOSAL_SUBMISSION_BLOCK,
      UPGRADE_PROPOSAL_SUBMISSION_BLOCK,
      address(OLD_GOVERNOR),
      _topics
    );
    if (_logs.length != 1) {
      revert(
        string.concat(
          "Expected one ProposalCreated event from the old Governor at "
          "UPGRADE_PROPOSAL_SUBMISSION_BLOCK but found ",
          vm.toString(_logs.length),
          "; repair the pinned submission block"
        )
      );
    }
    (uint256 _proposalId,,,,,,,, string memory _description) = abi.decode(
      _logs[0].data,
      (uint256, address, address[], uint256[], string[], bytes[], uint256, uint256, string)
    );
    if (_proposalId != SUBMITTED_UPGRADE_PROPOSAL_ID) {
      revert(
        string.concat(
          "The proposal created at UPGRADE_PROPOSAL_SUBMISSION_BLOCK has id ",
          vm.toString(_proposalId),
          " rather than SUBMITTED_UPGRADE_PROPOSAL_ID; repair the pinned block or id"
        )
      );
    }
    return (_proposalId, _description);
  }

  //---------------------------------- Scaffolding guards ----------------------------------//
  // Guards on the state the step helpers expect as they drive proposals through their
  // lifecycle. Like the setUp guards, these revert rather than assert: a failure means a test
  // scaffolding assumption broke — most often a fork-block bump reshaping the electorate — not
  // that a behavior under test regressed. Assertions are reserved for the claims test bodies
  // make about the system under test.

  function _guardProposalState(
    IGovernor.ProposalState _actual,
    IGovernor.ProposalState _expected,
    string memory _context
  ) internal pure {
    if (_actual == _expected) {
      return;
    }
    revert(
      string.concat(
        "Test scaffolding expected a proposal to be ",
        _proposalStateName(_expected),
        " but it is ",
        _proposalStateName(_actual),
        " (",
        _context,
        "); a scaffolding assumption broke; check the setUp guards and pinned fork block before "
        "suspecting the behavior under test"
      )
    );
  }

  function _guardProposalId(uint256 _actualId, uint256 _expectedId, string memory _context)
    internal
    pure
  {
    if (_actualId == _expectedId) {
      return;
    }
    revert(
      string.concat(
        "Test scaffolding expected proposal id ",
        vm.toString(_expectedId),
        " but the governor assigned ",
        vm.toString(_actualId),
        " (",
        _context,
        "); the submitted actions and the test's mirror of them have diverged; realign them"
      )
    );
  }

  function _proposalStateName(IGovernor.ProposalState _state)
    internal
    pure
    returns (string memory)
  {
    if (_state == IGovernor.ProposalState.Pending) {
      return "Pending";
    }
    if (_state == IGovernor.ProposalState.Active) {
      return "Active";
    }
    if (_state == IGovernor.ProposalState.Canceled) {
      return "Canceled";
    }
    if (_state == IGovernor.ProposalState.Defeated) {
      return "Defeated";
    }
    if (_state == IGovernor.ProposalState.Succeeded) {
      return "Succeeded";
    }
    if (_state == IGovernor.ProposalState.Queued) {
      return "Queued";
    }
    if (_state == IGovernor.ProposalState.Expired) {
      return "Expired";
    }
    return "Executed";
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

  // The two actions of the upgrade proposal, mirroring what the proposal script builds, paired
  // with the proposal's description. The tests assert the mirror is faithful by recomputing the
  // upgrade proposal's id from these actions.
  function _upgradeProposalDetails() internal view returns (ProposalDetails memory _proposal) {
    _proposal.targets = new address[](2);
    _proposal.values = new uint256[](2);
    _proposal.calldatas = new bytes[](2);
    _proposal.targets[0] = address(TIMELOCK);
    _proposal.calldatas[0] = abi.encodeCall(ICompoundTimelock.setPendingAdmin, (address(governor)));
    _proposal.targets[1] = address(governor);
    _proposal.calldatas[1] = abi.encodeCall(governor.__acceptAdmin, ());
    _proposal.description = upgradeProposalDescription;
    _proposal.id = _hashProposal(_proposal);
  }

  //----------------------------- Upgrade proposal (old Governor) -----------------------------//

  // Brings the upgrade proposal into being through the provenance hook (submitting it with the
  // real proposal script, or binding to the one already on mainnet) and guards that it carries
  // the actions the _upgradeProposalDetails mirror expects.
  function _proposeUpgrade() internal {
    (upgradeProposalId, upgradeProposalDescription) = _fetchOrSubmitUpgradeProposal();
    _guardProposalId(
      upgradeProposalId,
      _upgradeProposalDetails().id,
      "the upgrade proposal vs the _upgradeProposalDetails mirror"
    );
  }

  function _jumpToUpgradeProposalActive() internal {
    vm.roll(OLD_GOVERNOR.proposalSnapshot(upgradeProposalId) + 1);
    _guardProposalState(
      OLD_GOVERNOR.state(upgradeProposalId),
      IGovernor.ProposalState.Active,
      "jumping to the upgrade proposal's voting window"
    );
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

  // The full upgrade journey: propose, pass, queue, wait out the Timelock delay, execute, and
  // confirm the new Governor now controls the Timelock.
  function _upgradeToNewGovernor() internal {
    _proposeUpgrade();
    _passUpgradeProposal();
    _queueUpgradeProposal();
    _jumpPastUpgradeProposalEta();
    _executeUpgradeProposal();
    if (TIMELOCK.admin() != address(governor)) {
      revert(
        string.concat(
          "Test scaffolding: the upgrade proposal executed but the Timelock's admin is ",
          vm.toString(TIMELOCK.admin()),
          " rather than the new Governor ",
          vm.toString(address(governor)),
          "; the upgrade journey the suites build on is broken"
        )
      );
    }
  }

  //------------------------- Arbitrary proposals on the old Governor -------------------------//

  function _submitProposalToOldGovernor(ProposalDetails memory _proposal) internal {
    vm.prank(PROPOSER);
    uint256 _id = OLD_GOVERNOR.propose(
      _proposal.targets, _proposal.values, _proposal.calldatas, _proposal.description
    );
    _guardProposalId(_id, _proposal.id, "submitting a proposal directly to the old Governor");
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
    _guardProposalState(
      OLD_GOVERNOR.state(_proposal.id),
      IGovernor.ProposalState.Succeeded,
      "after the electorate voted a proposal through on the old Governor"
    );
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
    _guardProposalState(
      OLD_GOVERNOR.state(_proposal.id),
      IGovernor.ProposalState.Executed,
      "after executing a queued proposal on the old Governor"
    );
  }

  //------------------------------ Proposals on the new Governor ------------------------------//

  function _submitProposal(ProposalDetails memory _proposal) internal {
    vm.prank(PROPOSER);
    uint256 _id = governor.propose(
      _proposal.targets, _proposal.values, _proposal.calldatas, _proposal.description
    );
    _guardProposalId(_id, _proposal.id, "submitting a proposal directly to the new Governor");
    _guardProposalState(
      governor.state(_proposal.id),
      IGovernor.ProposalState.Pending,
      "immediately after submitting a proposal to the new Governor"
    );
  }

  function _jumpToProposalActive(uint256 _proposalId) internal {
    vm.roll(governor.proposalSnapshot(_proposalId) + 1);
    _guardProposalState(
      governor.state(_proposalId),
      IGovernor.ProposalState.Active,
      "jumping to a proposal's voting window on the new Governor"
    );
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
    _guardProposalState(
      governor.state(_proposal.id),
      IGovernor.ProposalState.Succeeded,
      "after the electorate voted a proposal through on the new Governor"
    );
  }

  function _submitPassQueueAndExecuteProposal(ProposalDetails memory _proposal) internal {
    _submitAndPassProposal(_proposal);
    _queueProposal(_proposal);
    _jumpPastProposalEta(_proposal.id);
    _executeProposal(_proposal);
    _guardProposalState(
      governor.state(_proposal.id),
      IGovernor.ProposalState.Executed,
      "after executing a queued proposal on the new Governor"
    );
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
