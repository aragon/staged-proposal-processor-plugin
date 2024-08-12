// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

/// @title Errors
/// @notice Library containing all custom errors the plugin may revert with.
library Errors {
    // SPP
    /// @notice Thrown the proposal does not exist.
    error ProposalNotExists();

    /// ! @notice not used so far
    error CallerNotABody();

    /// ! @notice not used so far
    error ProposalCannotExecute(bytes32);

    /// @notice Thrown when the stages length is zero.
    error StageCountZero();

    /// @notice Thrown when the metadata is empty.
    error EmptyMetadata();

    /// @notice Thrown when staged duration has already passed.
    error StageDurationAlreadyPassed();

    error InsufficientGas();

    // Trusted Forwarder
    /// @notice Thrown when trusted forwarder can not execute the actions.
    error NotPossible();

    /// @notice Thrown when a plugin doesn't support IProposal interface
    error InterfaceNotSupported();
}
