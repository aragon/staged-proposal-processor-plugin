// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

/// @title Errors
/// @author Aragon X - 2024
/// @notice Library containing all custom errors the plugin may revert with.
library Errors {
    // SPP

    /// @notice Thrown when a proposal doesn't exist.
    /// @param proposalId The ID of the proposal which doesn't exist.
    error NonexistentProposal(uint256 proposalId);

    /// @notice Thrown if the start date is less than current timestamp.
    error StartDateInvalid(uint64);

    /// @notice Thrown if stage durations are invalid.
    error StageDurationsInvalid();

    /// @notice Thrown if the thresholds are invalid.
    error StageThresholdsInvalid();

    /// @notice Thrown if the proposal is not cancalable in the `stageId`.
    error StageNotCancelable(uint16 stageId);

    /// @notice Thrown if the proposal has already been cancelled.
    /// @param proposalId The id of the proposal.
    error ProposalAlreadyCancelled(uint256 proposalId);

    /// @notice Thrown if a body address is duplicated in the same stage.
    /// @param stageId The stage id that contains the duplicated body address.
    /// @param body The address that is duplicated in `stageId`.
    error DuplicateBodyAddress(uint256 stageId, address body);

    /// @notice Thrown if the proposal with same actions and metadata already exists.
    /// @param proposalId The id of the proposal.
    error ProposalAlreadyExists(uint256 proposalId);

    /// @notice Thrown if first stage's params don't match the count of the current first stage's bodies' count.
    error InvalidCustomParamsForFirstStage();

    /// ! @notice not used so far
    error CallerNotABody();

    /// ! @notice not used so far
    error ProposalCannotExecute(uint256);

    /// @notice Thrown when the stages length is zero.
    error StageCountZero();

    /// @notice Thrown when the body tries to submit report for the stage id that has not yet become active.
    /// @param currentStageId The stage id that proposal is currently at.
    /// @param reportedStageId The stage id for which the report is being submitted.
    error StageIdInvalid(uint64 currentStageId, uint64 reportedStageId);

    /// @notice Thrown when the metadata is empty.
    error EmptyMetadata();

    error InsufficientGas();

    // Trusted Forwarder
    /// @notice Thrown when trusted forwarder can not execute the actions.
    error IncorrectActionCount();

    /// @notice Thrown when a body doesn't support IProposal interface.
    error InterfaceNotSupported();

    /// @notice Thrown when the proposal can not be advanced.
    error ProposalCannotAdvance(uint256 proposalId);

    /// @notice Thrown if the proposal execution is forbidden.
    /// @param proposalId The ID of the proposal.
    error ProposalExecutionForbidden(uint256 proposalId);
}
