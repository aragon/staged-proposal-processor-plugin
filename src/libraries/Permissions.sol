// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

library Permissions {
    /// @notice The ID of the permission required to call the `createProposal` function.
    bytes32 internal constant CREATE_PROPOSAL_PERMISSION_ID =
        keccak256("CREATE_PROPOSAL_PERMISSION");

    /// @notice The ID of the permission required to call the `setTrustedForwarder` function.
    bytes32 internal constant SET_TRUSTED_FORWARDER_PERMISSION_ID =
        keccak256("SET_TRUSTED_FORWARDER_PERMISSION");

    /// @notice The ID of the permission required to call the `updateStages` function.
    bytes32 internal constant UPDATE_STAGES_PERMISSION_ID = keccak256("UPDATE_STAGES_PERMISSION");

    /// @notice The ID of the permission required to execute the proposal if it's on the last stage.
    /// @dev It is important to use a different identifier than keccak256("EXECUTE_PERMISSION") to ensure
    ///      that it can still be granted with ANY_ADDR. Refer to the DAO.sol function -
    ///      `isPermissionRestrictedForAnyAddr` for more details.
    bytes32 internal constant EXECUTE_PROPOSAL_PERMISSION_ID =
        keccak256("EXECUTE_PROPOSAL_PERMISSION");

    /// @notice The ID of the permission required to execute the proposal on the dao.
    bytes32 internal constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");

    /// @notice The ID of the permission required to cancel the proposal.
    bytes32 internal constant CANCEL_PERMISSION_ID = keccak256("CANCEL_PERMISSION");

    /// @notice The ID of the permission required to advance the proposal.
    bytes32 internal constant ADVANCE_PERMISSION_ID = keccak256("ADVANCE_PERMISSION");

    /// @notice The ID of the permission required to edit the proposal.
    bytes32 internal constant EDIT_PERMISSION_ID = keccak256("EDIT_PERMISSION");

    /// @notice The ID of the permission required to call the `updateRules` function.
    bytes32 internal constant UPDATE_RULES_PERMISSION_ID = keccak256("UPDATE_RULES_PERMISSION");

    /// @notice The ID of the permission required to call the `setTargetConfig` function.
    bytes32 internal constant SET_TARGET_CONFIG_PERMISSION_ID =
        keccak256("SET_TARGET_CONFIG_PERMISSION");

    /// @notice The ID of the permission required to call the `updateMetadata` function.
    bytes32 internal constant SET_METADATA_PERMISSION_ID = keccak256("SET_METADATA_PERMISSION");
}
