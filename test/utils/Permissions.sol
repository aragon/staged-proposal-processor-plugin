// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

// / @notice A special address encoding permissions that are valid for any address `who` or `where`.
address constant ANY_ADDR = address(type(uint160).max);

// / @notice The identifier of the `EXECUTE_PERMISSION` permission.
bytes32 constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");

// / @notice The ID of the permission required to call the `updateStages` function.
bytes32 constant UPDATE_STAGES_PERMISSION_ID = keccak256("UPDATE_STAGES_PERMISSION");

// / @notice The ID of the permission required to call the `setTrustedForwarder` function.
bytes32 constant SET_TRUSTED_FORWARDER_PERMISSION_ID = keccak256(
    "SET_TRUSTED_FORWARDER_PERMISSION"
);

// / @notice The ID of the permission required to call the `createProposal` function.
bytes32 constant CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");

// / @notice The ID of the permission required to call the `updateRules` function.
bytes32 constant UPDATE_RULES_PERMISSION_ID = keccak256("UPDATE_RULES_PERMISSION");

// / @notice The ID of the permission required to call the `setTargetConfig` function.
bytes32 constant SET_TARGET_CONFIG_PERMISSION_ID = keccak256("SET_TARGET_CONFIG_PERMISSION");

// / @notice The ID of the permission required to call the `updateMetadata` function.
bytes32 constant SET_METADATA_PERMISSION_ID = keccak256("SET_METADATA_PERMISSION");

// / @notice The ID of the permission required to call the `execute` function.
bytes32 constant EXECUTE_PROPOSAL_PERMISSION_ID = keccak256("EXECUTE_PROPOSAL_PERMISSION");
