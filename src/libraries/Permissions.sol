// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

/// @notice The ID of the permission required to call the `createProposal` function.
bytes32 constant CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");

/// @notice The ID of the permission required to call the `setTrustedForwarder` function.
bytes32 constant SET_TRUSTED_FORWARDER_PERMISSION_ID = keccak256(
    "SET_TRUSTED_FORWARDER_PERMISSION"
);

/// @notice The ID of the permission required to call the `updateStages` function.
bytes32 constant UPDATE_STAGES_PERMISSION_ID = keccak256("UPDATE_STAGES_PERMISSION");

/// @notice The ID of the permission required to execute the proposal if it's on the last stage.
bytes32 constant EXECUTE_PROPOSAL_PERMISSION_ID = keccak256("EXECUTE_PROPOSAL_PERMISSION");

/// @notice The ID of the permission required to cancel the proposal.
bytes32 constant CANCEL_PROPOSAL_PERMISSION_ID = keccak256("CANCEL_PROPOSAL_PERMISSION");

/// @notice The ID of the permission required to advance the proposal.
bytes32 constant ADVANCE_PROPOSAL_PERMISSION_ID = keccak256("ADVANCE_PROPOSAL_PERMISSION");

/// @notice The ID of the permission required to edit the proposal.
bytes32 constant EDIT_PROPOSAL_PERMISSION_ID = keccak256("EDIT_PROPOSAL_PERMISSION");

/// @notice The ID of the permission required to call the `updateRules` function.
bytes32 constant UPDATE_RULES_PERMISSION_ID = keccak256("UPDATE_RULES_PERMISSION");

/// @notice The ID of the permission required to call the `setTargetConfig` function.
bytes32 constant SET_TARGET_CONFIG_PERMISSION_ID = keccak256("SET_TARGET_CONFIG_PERMISSION");

/// @notice The ID of the permission required to call the `updateMetadata` function.
bytes32 constant SET_METADATA_PERMISSION_ID = keccak256("SET_METADATA_PERMISSION");
