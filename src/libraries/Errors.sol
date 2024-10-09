// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

/// @title Errors
/// @notice Library containing all custom errors the plugin may revert with.
library Errors {
    // SPP
    /// @notice Thrown the proposal does not exist.
    error ProposalNotExists(uint256);

    /// @notice Thrown if the proposal with same actions and metadata already exists.
    /// @param proposalId The id of the proposal.
    error ProposalAlreadyExists(uint256 proposalId);

    /// ! @notice not used so far
    error CallerNotABody();

    /// ! @notice not used so far
    error ProposalCannotExecute(uint256);

    /// @notice Thrown when the stages length is zero.
    error StageCountZero();

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
