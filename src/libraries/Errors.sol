// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

/// @title Errors
/// @notice Library containing all custom errors the plugin may revert with.
library Errors {
    // SPP
    /// @notice Thrown the proposal does not exist.
    error ProposalNotExists(uint256);

    /// @notice Thrown if a plugin address is duplicated in the same stage.
    /// @param stageId The stage id that contains the duplicated plugin address.
    /// @param plugin The address that is duplicated in `stageId`.
    error DuplicatePluginAddress(uint256 stageId, address plugin);

    /// @notice Thrown if the proposal with same actions and metadata already exists.
    /// @param proposalId The id of the proposal.
    error ProposalAlreadyExists(uint256 proposalId);

    /// ! @notice not used so far
    error CallerNotABody();

    /// ! @notice not used so far
    error ProposalCannotExecute(uint256);

    /// @notice Thrown when the stages length is zero.
    error StageCountZero();

    /// @notice Thrown when the body tries to submit report for the stage id that has not yet become active.
    /// @param currentStageId The stage id that proposal is currently at.
    /// @param submittedStageId The stage id for which the report is being submitted.
    error StageIdInvalid(uint64 currentStageId, uint64 submittedStageId);

    /// @notice Thrown when the metadata is empty.
    error EmptyMetadata();

    error InsufficientGas();

    // Trusted Forwarder
    /// @notice Thrown when trusted forwarder can not execute the actions.
    error IncorrectActionCount();

    /// @notice Thrown when a plugin doesn't support IProposal interface.
    error InterfaceNotSupported();

    /// @notice Thrown when the proposal can not be advanced.
    error ProposalCannotAdvance(uint256 proposalId);
}
