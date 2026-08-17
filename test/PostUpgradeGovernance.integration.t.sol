// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {GitcoinGovernorWithGuardian} from "src/GitcoinGovernorWithGuardian.sol";
import {GitcoinGovernorPostUpgradeTestBase} from "test/helpers/GitcoinGovernorUpgradeTestBase.sol";

// Exercises day-to-day governance on the new Governor after the upgrade has executed: passing
// and defeating proposals that move treasury assets held by the Timelock, updating the
// Governor's own settings, fractional and by-signature voting, and Timelock expiry.
abstract contract PostUpgradeGovernanceTest is GitcoinGovernorPostUpgradeTestBase {
  /// forge-config: default.fuzz.runs = 25
  /// forge-config: ci.fuzz.runs = 25
  /// forge-config: lite.fuzz.runs = 5
  function testFuzz_PassedProposalSendsGtcHeldByTheTimelock(uint256 _amount) external {
    // The proposal draws on the GTC the Timelock genuinely holds at the fork block.
    uint256 _initialTimelockBalance = GTC_TOKEN.balanceOf(address(TIMELOCK));
    _amount = bound(_amount, 1, _initialTimelockBalance);
    address _receiver = makeAddr("receiver");

    ProposalDetails memory _proposal =
      _buildGtcSendProposal(_receiver, _amount, "Send GTC from the Timelock");
    _submitPassQueueAndExecuteProposal(_proposal);

    assertEq(GTC_TOKEN.balanceOf(_receiver), _amount);
    assertEq(GTC_TOKEN.balanceOf(address(TIMELOCK)), _initialTimelockBalance - _amount);
  }

  /// forge-config: default.fuzz.runs = 25
  /// forge-config: ci.fuzz.runs = 25
  /// forge-config: lite.fuzz.runs = 5
  function testFuzz_PassedProposalSendsEthHeldByTheTimelock(uint256 _amount) external {
    // The proposal draws on the ETH the Timelock genuinely holds at the fork block.
    uint256 _initialTimelockBalance = address(TIMELOCK).balance;
    _amount = bound(_amount, 1, _initialTimelockBalance);
    address _receiver = makeAddr("receiver");

    ProposalDetails memory _proposal =
      _buildProposal(_receiver, _amount, "", "Send ETH from the Timelock");
    _submitPassQueueAndExecuteProposal(_proposal);

    assertEq(_receiver.balance, _amount);
    assertEq(address(TIMELOCK).balance, _initialTimelockBalance - _amount);
  }

  function test_PassedProposalSendsEthAndGtcTogether() external {
    address _receiver = makeAddr("receiver");
    uint256 _gtcAmount = 5000e18;
    uint256 _ethAmount = 5 ether;
    uint256 _initialTimelockGtcBalance = GTC_TOKEN.balanceOf(address(TIMELOCK));
    uint256 _initialTimelockEthBalance = address(TIMELOCK).balance;

    ProposalDetails memory _proposal;
    _proposal.targets = new address[](2);
    _proposal.values = new uint256[](2);
    _proposal.calldatas = new bytes[](2);
    _proposal.targets[0] = address(GTC_TOKEN);
    _proposal.calldatas[0] = abi.encodeCall(GTC_TOKEN.transfer, (_receiver, _gtcAmount));
    _proposal.targets[1] = _receiver;
    _proposal.values[1] = _ethAmount;
    _proposal.description = "Send GTC and ETH from the Timelock";
    _proposal.id = _hashProposal(_proposal);

    _submitPassQueueAndExecuteProposal(_proposal);

    assertEq(GTC_TOKEN.balanceOf(_receiver), _gtcAmount);
    assertEq(_receiver.balance, _ethAmount);
    assertEq(GTC_TOKEN.balanceOf(address(TIMELOCK)), _initialTimelockGtcBalance - _gtcAmount);
    assertEq(address(TIMELOCK).balance, _initialTimelockEthBalance - _ethAmount);
  }

  function test_DefeatedProposalCanNeitherBeQueuedNorExecuted() external {
    address _receiver = makeAddr("receiver");
    uint256 _initialTimelockBalance = GTC_TOKEN.balanceOf(address(TIMELOCK));

    ProposalDetails memory _proposal =
      _buildGtcSendProposal(_receiver, 1000e18, "Send GTC the DAO does not want to send");
    _submitProposal(_proposal);
    _jumpToProposalActive(_proposal.id);
    _delegatesCastVotes(_proposal.id, AGAINST);
    _jumpPastProposalDeadline(_proposal.id);
    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Defeated);

    vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
    _queueProposal(_proposal);
    vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
    _executeProposal(_proposal);
    assertEq(GTC_TOKEN.balanceOf(_receiver), 0);
    assertEq(GTC_TOKEN.balanceOf(address(TIMELOCK)), _initialTimelockBalance);
  }

  function test_ProposalWithOnlyAbstainVotesReachesQuorumButIsDefeated() external {
    ProposalDetails memory _proposal =
      _buildGtcSendProposal(makeAddr("receiver"), 1000e18, "A proposal everyone abstains on");
    _submitProposal(_proposal);
    _jumpToProposalActive(_proposal.id);
    _delegatesCastVotes(_proposal.id, ABSTAIN);
    _jumpPastProposalDeadline(_proposal.id);

    // Abstentions count toward quorum under the Governor's counting mode, but with no FOR
    // majority the proposal still fails.
    (uint256 _against, uint256 _for, uint256 _abstain) = governor.proposalVotes(_proposal.id);
    assertEq(_against, 0);
    assertEq(_for, 0);
    assertGe(_abstain, QUORUM);
    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Defeated);
  }

  function test_GovernanceUpdatesItsOwnSettingsViaProposal() external {
    uint48 _newVotingDelay = 7200;
    uint32 _newVotingPeriod = 21_600;
    uint256 _newProposalThreshold = 100_000e18;
    uint48 _newVoteExtension = 7200;

    ProposalDetails memory _proposal;
    _proposal.targets = new address[](4);
    _proposal.values = new uint256[](4);
    _proposal.calldatas = new bytes[](4);
    for (uint256 _index = 0; _index < 4; _index += 1) {
      _proposal.targets[_index] = address(governor);
    }
    _proposal.calldatas[0] = abi.encodeCall(governor.setVotingDelay, (_newVotingDelay));
    _proposal.calldatas[1] = abi.encodeCall(governor.setVotingPeriod, (_newVotingPeriod));
    _proposal.calldatas[2] = abi.encodeCall(governor.setProposalThreshold, (_newProposalThreshold));
    _proposal.calldatas[3] =
      abi.encodeCall(governor.setLateQuorumVoteExtension, (_newVoteExtension));
    _proposal.description = "Update the Governor's own settings";
    _proposal.id = _hashProposal(_proposal);

    _submitPassQueueAndExecuteProposal(_proposal);

    assertEq(governor.votingDelay(), _newVotingDelay);
    assertEq(governor.votingPeriod(), _newVotingPeriod);
    assertEq(governor.proposalThreshold(), _newProposalThreshold);
    assertEq(governor.lateQuorumVoteExtension(), _newVoteExtension);
  }

  function test_VoterSplitsWeightAcrossForAgainstAndAbstainWithAFractionalVote() external {
    ProposalDetails memory _proposal =
      _buildGtcSendProposal(makeAddr("receiver"), 1000e18, "A proposal with split votes");
    _submitProposal(_proposal);
    _jumpToProposalActive(_proposal.id);

    // kev.eth splits their weight: 10% against, 60% for, 30% abstain. The weight is a uint96, so
    // the splits always fit a fractional vote's uint128 fields.
    uint128 _weight = _votingWeightOf(KEV);
    uint128 _againstVotes = _weight / 10;
    uint128 _abstainVotes = _weight * 3 / 10;
    uint128 _forVotes = _weight - _againstVotes - _abstainVotes;
    vm.prank(KEV);
    governor.castVoteWithReasonAndParams(
      _proposal.id,
      VOTE_TYPE_FRACTIONAL,
      "I contain multitudes",
      abi.encodePacked(_againstVotes, _forVotes, _abstainVotes)
    );
    (uint256 _against, uint256 _for, uint256 _abstain) = governor.proposalVotes(_proposal.id);
    assertEq(_against, _againstVotes);
    assertEq(_for, _forVotes);
    assertEq(_abstain, _abstainVotes);

    // Nominal bravo-style votes from the rest of the electorate coexist with the fractional
    // tally.
    _delegatesCastVotesExcept(_proposal.id, FOR, KEV);
    (_against, _for, _abstain) = governor.proposalVotes(_proposal.id);
    assertEq(_for, _forVotes + totalDelegateWeight - _weight);
    // Ensure the combined result reaches quorum and passes regardless of the fork block.
    if (((_for + _abstain) < QUORUM) || (_for < _against)) {
      revert(
        "Delegate votes at current for vote insufficient to pass proposal in fraction voting tests."
        "Adjust delegates available or change fork block."
      );
    }

    _jumpPastProposalDeadline(_proposal.id);
    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Succeeded);
    _queueProposal(_proposal);
    _jumpPastProposalEta(_proposal.id);
    _executeProposal(_proposal);
    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Executed);
  }

  function test_VoterCastsMultiplePartialFractionalVotes() external {
    ProposalDetails memory _proposal =
      _buildGtcSendProposal(makeAddr("receiver"), 1000e18, "A proposal with partial votes");
    _submitProposal(_proposal);
    _jumpToProposalActive(_proposal.id);

    // First cast: kev.eth commits half their weight, split across all three options.
    uint128 _weight = _votingWeightOf(KEV);
    uint128 _firstAgainst = _weight / 8;
    uint128 _firstFor = _weight / 4;
    uint128 _firstAbstain = _weight / 8;
    vm.prank(KEV);
    governor.castVoteWithReasonAndParams(
      _proposal.id,
      VOTE_TYPE_FRACTIONAL,
      "A first, partial vote",
      abi.encodePacked(_firstAgainst, _firstFor, _firstAbstain)
    );
    (uint256 _against, uint256 _for, uint256 _abstain) = governor.proposalVotes(_proposal.id);
    assertEq(_against, _firstAgainst);
    assertEq(_for, _firstFor);
    assertEq(_abstain, _firstAbstain);
    assertEq(governor.usedVotes(_proposal.id, KEV), _firstAgainst + _firstFor + _firstAbstain);

    // Second cast: the rest of their weight, all FOR. Tallies accumulate across the casts until
    // the voter's full weight is spent.
    uint128 _remaining = _weight - _firstAgainst - _firstFor - _firstAbstain;
    vm.prank(KEV);
    governor.castVoteWithReasonAndParams(
      _proposal.id,
      VOTE_TYPE_FRACTIONAL,
      "A second vote with the rest of my weight",
      abi.encodePacked(uint128(0), _remaining, uint128(0))
    );
    (_against, _for, _abstain) = governor.proposalVotes(_proposal.id);
    assertEq(_against, _firstAgainst);
    assertEq(_for, _firstFor + _remaining);
    assertEq(_abstain, _firstAbstain);
    assertEq(governor.usedVotes(_proposal.id, KEV), _weight);

    // The rest of the electorate pushes the proposal over quorum, and it passes.
    _delegatesCastVotesExcept(_proposal.id, FOR, KEV);
    _jumpPastProposalDeadline(_proposal.id);
    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Succeeded);
  }

  function test_VoterCastsAVoteBySignatureThatARelayerSubmits() external {
    // A voter whose key the test controls, given real voting weight before the snapshot.
    (address _signer, uint256 _signerKey) = makeAddrAndKey("gaslessVoter");
    uint256 _signerWeight = 250_000e18;
    deal(address(GTC_TOKEN), _signer, _signerWeight);
    vm.prank(_signer);
    GTC_TOKEN.delegate(_signer);

    ProposalDetails memory _proposal =
      _buildGtcSendProposal(makeAddr("receiver"), 1000e18, "A proposal voted on by signature");
    _submitProposal(_proposal);
    _jumpToProposalActive(_proposal.id);

    // The voter signs an EIP-712 ballot off-chain, against the domain wallets will derive from
    // the Governor's name and version.
    bytes32 _domainSeparator = keccak256(
      abi.encode(
        keccak256(
          "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        ),
        keccak256(bytes(governor.name())),
        keccak256(bytes(governor.version())),
        block.chainid,
        address(governor)
      )
    );
    bytes32 _structHash = keccak256(
      abi.encode(governor.BALLOT_TYPEHASH(), _proposal.id, FOR, _signer, governor.nonces(_signer))
    );
    bytes32 _digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator, _structHash));
    (uint8 _v, bytes32 _r, bytes32 _s) = vm.sign(_signerKey, _digest);

    // A relayer submits the ballot, paying the gas; the vote is counted for the signer.
    vm.prank(makeAddr("relayer"));
    governor.castVoteBySig(_proposal.id, FOR, _signer, abi.encodePacked(_r, _s, _v));
    assertTrue(governor.hasVoted(_proposal.id, _signer));
    (, uint256 _for,) = governor.proposalVotes(_proposal.id);
    assertEq(_for, _signerWeight);

    // The rest of the electorate votes normally alongside, and the proposal passes.
    _delegatesCastVotes(_proposal.id, FOR);
    _jumpPastProposalDeadline(_proposal.id);
    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Succeeded);
  }

  function test_QueuedProposalExpiresOnceTheTimelockGracePeriodPasses() external {
    address _receiver = makeAddr("receiver");

    ProposalDetails memory _proposal =
      _buildGtcSendProposal(_receiver, 1000e18, "A proposal nobody executes in time");
    _submitAndPassProposal(_proposal);
    _queueProposal(_proposal);

    // Nobody executes the proposal within the Timelock's grace period.
    vm.warp(governor.proposalEta(_proposal.id) + TIMELOCK.GRACE_PERIOD() + 1);
    vm.roll(block.number + 1);
    assertEq(governor.state(_proposal.id), IGovernor.ProposalState.Expired);

    vm.expectPartialRevert(IGovernor.GovernorUnexpectedProposalState.selector);
    _executeProposal(_proposal);
    assertEq(GTC_TOKEN.balanceOf(_receiver), 0);
  }
}

contract PostUpgradeGovernanceMainnetScript is PostUpgradeGovernanceTest {
  function _setUpNetwork() internal override {
    _createMainnetFork();
  }

  function _fetchOrDeploySystem() internal override returns (GitcoinGovernorWithGuardian) {
    return _deployGovernorWithMainnetScript();
  }
}

contract PostUpgradeGovernanceMainnetDeployed is PostUpgradeGovernanceTest {
  function _setUpNetwork() internal override {
    _createMainnetGovernorPostDeploymentFork();
  }

  function _fetchOrDeploySystem() internal view override returns (GitcoinGovernorWithGuardian) {
    return _fetchDeployedGovernor();
  }
}
