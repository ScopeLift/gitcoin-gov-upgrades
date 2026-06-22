// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.35;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {
  GovernorCountingFractional
} from "@openzeppelin/contracts/governance/extensions/GovernorCountingFractional.sol";
import {
  GovernorTimelockCompound,
  ICompoundTimelock
} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockCompound.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {
  GovernorPreventLateQuorum
} from "@openzeppelin/contracts/governance/extensions/GovernorPreventLateQuorum.sol";
import {
  GovernorProposalGuardian
} from "@openzeppelin/contracts/governance/extensions/GovernorProposalGuardian.sol";
import {GovernorSettableFixedQuorum} from "src/extensions/GovernorSettableFixedQuorum.sol";
import {GovernorVotesComp} from "src/extensions/GovernorVotesComp.sol";

/// @title GitcoinGovernorWithGuardian
/// @author [ScopeLift](https://scopelift.co)
/// @notice The upgraded Gitcoin Governor. It maintains compatibility with the DAO's Compound era
/// governance infrastructure, namely its Timelock and token, while adding modern governance
/// features and security measures. Those include:
///
/// 1. Proposal Guardian - An address of the DAO's choosing, presumably a security council multi-
/// sig, has the ability to cancel malicious proposals at any point during the proposal lifecycle.
/// 2. Prevent Late Quorum - Ensures that a configurable, minimum amount of time always elapses
/// between when a proposal reaches quorum and when voting on said-proposal ends. Intended to
/// prevent governance attacks that rely on boosting an unpopular proposal over quorum at the last
/// minute.
/// 3. Settable Quorum - Keeps quorum as a fixed number, but allows the DAO to adjust this number
/// via a governance proposal.
contract GitcoinGovernorWithGuardian is
  GovernorCountingFractional,
  GovernorVotesComp,
  GovernorPreventLateQuorum,
  GovernorTimelockCompound,
  GovernorSettings,
  GovernorSettableFixedQuorum,
  GovernorProposalGuardian
{
  /// @param _name Name of the governor instance (used in building the EIP-712 domain separator).
  /// @param _initialQuorum The deployment value for the proposal quorum value this Governor will
  /// enforce.
  /// @param _initialVotingDelay The deployment value for the voting delay this Governor will
  /// enforce.
  /// @param _initialVotingPeriod The deployment value for the voting period this Governor will
  /// enforce.
  /// @param _initialProposalThreshold The deployment value for the number of GTC required to submit
  /// a proposal this Governor will enforce.
  /// @param _timelockAddress The address of Gitcoin's Timelock address.
  constructor(
    string memory _name,
    uint256 _initialQuorum,
    uint48 _initialVoteExtension,
    uint48 _initialVotingDelay,
    uint32 _initialVotingPeriod,
    uint256 _initialProposalThreshold,
    ICompoundTimelock _timelockAddress
  )
    Governor(_name)
    GovernorSettableFixedQuorum(_initialQuorum)
    GovernorPreventLateQuorum(_initialVoteExtension)
    GovernorSettings(_initialVotingDelay, _initialVotingPeriod, _initialProposalThreshold)
    GovernorTimelockCompound(_timelockAddress)
  {}

  /// @inheritdoc GovernorSettings
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function proposalThreshold()
    public
    view
    virtual
    override(Governor, GovernorSettings)
    returns (uint256)
  {
    return GovernorSettings.proposalThreshold();
  }

  /// @inheritdoc GovernorTimelockCompound
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function state(uint256 _proposalId)
    public
    view
    virtual
    override(Governor, GovernorTimelockCompound)
    returns (ProposalState)
  {
    return GovernorTimelockCompound.state(_proposalId);
  }

  /// @inheritdoc GovernorPreventLateQuorum
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function proposalDeadline(uint256 _proposalId)
    public
    view
    virtual
    override(Governor, GovernorPreventLateQuorum)
    returns (uint256)
  {
    return GovernorPreventLateQuorum.proposalDeadline(_proposalId);
  }

  /// @inheritdoc GovernorTimelockCompound
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function proposalNeedsQueuing(uint256 _proposalId)
    public
    view
    virtual
    override(Governor, GovernorTimelockCompound)
    returns (bool)
  {
    return GovernorTimelockCompound.proposalNeedsQueuing(_proposalId);
  }

  /// @inheritdoc GovernorTimelockCompound
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _executor()
    internal
    view
    virtual
    override(Governor, GovernorTimelockCompound)
    returns (address)
  {
    return GovernorTimelockCompound._executor();
  }

  /// @inheritdoc GovernorProposalGuardian
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _validateCancel(uint256 _proposalId, address _caller)
    internal
    view
    virtual
    override(Governor, GovernorProposalGuardian)
    returns (bool)
  {
    return GovernorProposalGuardian._validateCancel(_proposalId, _caller);
  }

  /// @inheritdoc GovernorPreventLateQuorum
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _tallyUpdated(uint256 _proposalId)
    internal
    virtual
    override(Governor, GovernorPreventLateQuorum)
  {
    GovernorPreventLateQuorum._tallyUpdated(_proposalId);
  }

  /// @inheritdoc GovernorTimelockCompound
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _queueOperations(
    uint256 _proposalId,
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) internal virtual override(Governor, GovernorTimelockCompound) returns (uint48) {
    return GovernorTimelockCompound._queueOperations(
      _proposalId, _targets, _values, _calldatas, _descriptionHash
    );
  }

  /// @inheritdoc GovernorTimelockCompound
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _executeOperations(
    uint256 _proposalId,
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) internal virtual override(Governor, GovernorTimelockCompound) {
    return GovernorTimelockCompound._executeOperations(
      _proposalId, _targets, _values, _calldatas, _descriptionHash
    );
  }

  /// @inheritdoc GovernorTimelockCompound
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _cancel(
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) internal virtual override(Governor, GovernorTimelockCompound) returns (uint256) {
    return GovernorTimelockCompound._cancel(_targets, _values, _calldatas, _descriptionHash);
  }
}
