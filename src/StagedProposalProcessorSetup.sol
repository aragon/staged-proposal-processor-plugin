// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.18;

import {SPPRuleCondition} from "./utils/SPPRuleCondition.sol";
import {StagedProposalProcessor as SPP} from "./StagedProposalProcessor.sol";
import {Permissions} from "./libraries/Permissions.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {
    PluginUpgradeableSetup
} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginUpgradeableSetup.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {
    RuledCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/extensions/RuledCondition.sol";

/// @title StagedProposalProcessorSetup
/// @author Aragon X - 2024
/// @notice The setup contract of the `StagedProposalProcessor` plugin.
/// @dev Release 1, Build 2
contract StagedProposalProcessorSetup is PluginUpgradeableSetup {
    using ProxyLib for address;

    /// @notice A special address encoding permissions that are valid for any address `who` or `where`.
    address private constant ANY_ADDR = address(type(uint160).max);

    /// @notice The address of the condition implementation contract.
    address public immutable CONDITION_IMPLEMENTATION;

    /// @notice Whether the network supports EIP-1167 minimal proxies (clones).
    /// @dev False on networks like ZkSync that lack CREATE2 clone support; falls back to UUPS.
    bool public immutable CLONES_SUPPORTED;

    /// @notice Constructs the `PluginUpgradeableSetup` by storing the `SPP` implementation address.
    /// @dev The implementation address is used to deploy UUPS proxies referencing it and
    /// to verify the plugin on the respective block explorers.
    constructor(SPP _spp) PluginUpgradeableSetup(address(_spp)) {
        CONDITION_IMPLEMENTATION = address(
            new SPPRuleCondition(address(0), new RuledCondition.Rule[](0))
        );
        // Clones not supported on ZkSync
        CLONES_SUPPORTED = block.chainid != 324 && block.chainid != 300;
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes calldata _installationParams
    ) external returns (address spp, PreparedSetupData memory preparedSetupData) {
        (
            bytes memory pluginMetadata,
            SPP.Stage[] memory stages,
            RuledCondition.Rule[] memory rules,
            IPlugin.TargetConfig memory targetConfig
        ) = abi.decode(
                _installationParams,
                (bytes, SPP.Stage[], RuledCondition.Rule[], IPlugin.TargetConfig)
            );

        // By default, we assume that sub-plugins will use a delegate call to invoke the executor,
        // which will keep `msg.sender` as the sub-plugin within the SPP context.
        // Therefore, the default trusted forwarder is set to the zero address (address(0)).
        // However, the grantee of `SET_TRUSTED_FORWARDER_PERMISSION` can update this address at any time.
        // Allowing a user-provided trusted forwarder here is risky if the plugin installer is malicious.
        spp = IMPLEMENTATION.deployUUPSProxy(
            abi.encodeCall(
                SPP.initialize,
                (IDAO(_dao), address(0), stages, pluginMetadata, targetConfig)
            )
        );

        // Clone and initialize the condition contract.
        // On networks without EIP-1167 clone support (e.g. ZkSync), fall back to UUPS.
        bytes memory initData = abi.encodeCall(SPPRuleCondition.initialize, (_dao, rules));
        address sppCondition = CLONES_SUPPORTED
            ? CONDITION_IMPLEMENTATION.deployMinimalProxy(initData)
            : CONDITION_IMPLEMENTATION.deployUUPSProxy(initData);

        preparedSetupData.permissions = _getPermissions(
            _dao,
            spp,
            sppCondition,
            PermissionLib.Operation.Grant
        );

        preparedSetupData.helpers = new address[](1);
        preparedSetupData.helpers[0] = sppCondition;
    }

    /// @inheritdoc IPluginSetup
    /// @dev v1.1 → v1.2: deploys a fresh `SPPRuleCondition` seeded with the existing rules and migrates
    /// `CREATE_PROPOSAL_PERMISSION` (on the plugin) and `UPDATE_RULES_PERMISSION` (on the helper) from
    /// the old condition to the new one. The plugin proxy itself is upgraded to the new implementation
    /// by the `PluginSetupProcessor` automatically; no reinitializer is required because no new storage
    /// is introduced in build 2. Existing rules are read from the old helper, so no caller-supplied data
    /// is required — `_payload.data` is ignored.
    function prepareUpdate(
        address _dao,
        uint16 _fromBuild,
        SetupPayload calldata _payload
    ) external virtual override returns (bytes memory initData, PreparedSetupData memory preparedSetupData) {
        if (_fromBuild != 1) {
            revert InvalidUpdatePath({fromBuild: _fromBuild, thisBuild: 2});
        }

        address oldCondition = _payload.currentHelpers[0];
        RuledCondition.Rule[] memory rules = SPPRuleCondition(oldCondition).getRules();

        bytes memory conditionInitData = abi.encodeCall(
            SPPRuleCondition.initialize,
            (_dao, rules)
        );
        address newCondition = CLONES_SUPPORTED
            ? CONDITION_IMPLEMENTATION.deployMinimalProxy(conditionInitData)
            : CONDITION_IMPLEMENTATION.deployUUPSProxy(conditionInitData);

        preparedSetupData.helpers = new address[](1);
        preparedSetupData.helpers[0] = newCondition;

        preparedSetupData.permissions = new PermissionLib.MultiTargetPermission[](4);

        // Move CREATE_PROPOSAL_PERMISSION on the plugin from the old condition to the new one.
        preparedSetupData.permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: ANY_ADDR,
            condition: oldCondition,
            permissionId: Permissions.CREATE_PROPOSAL_PERMISSION_ID
        });
        preparedSetupData.permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.GrantWithCondition,
            where: _payload.plugin,
            who: ANY_ADDR,
            condition: newCondition,
            permissionId: Permissions.CREATE_PROPOSAL_PERMISSION_ID
        });

        // Move UPDATE_RULES_PERMISSION (DAO is the rule manager) from the old condition to the new one.
        preparedSetupData.permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: oldCondition,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: Permissions.UPDATE_RULES_PERMISSION_ID
        });
        preparedSetupData.permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: newCondition,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: Permissions.UPDATE_RULES_PERMISSION_ID
        });

        // initData stays empty — applyUpdate triggers the proxy implementation upgrade on its own.
        initData = "";
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external pure returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        permissions = _getPermissions(
            _dao,
            _payload.plugin,
            _payload.currentHelpers[0],
            PermissionLib.Operation.Revoke
        );
    }

    function _getPermissions(
        address _dao,
        address _spp,
        address _ruledCondition,
        PermissionLib.Operation _op
    ) private pure returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        permissions = new PermissionLib.MultiTargetPermission[](9);

        // Permissions on SPP
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: _op,
            where: _spp,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: Permissions.UPDATE_STAGES_PERMISSION_ID
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: _op,
            where: _spp,
            who: ANY_ADDR,
            condition: PermissionLib.NO_CONDITION,
            permissionId: Permissions.EXECUTE_PROPOSAL_PERMISSION_ID
        });

        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: _op,
            where: _spp,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: Permissions.SET_TRUSTED_FORWARDER_PERMISSION_ID
        });

        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: _op,
            where: _spp,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: Permissions.SET_TARGET_CONFIG_PERMISSION_ID
        });

        permissions[4] = PermissionLib.MultiTargetPermission({
            operation: _op,
            where: _spp,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: Permissions.SET_METADATA_PERMISSION_ID
        });

        permissions[5] = PermissionLib.MultiTargetPermission({
            operation: _op == PermissionLib.Operation.Grant
                ? PermissionLib.Operation.GrantWithCondition
                : _op,
            where: _spp,
            who: ANY_ADDR,
            condition: _ruledCondition,
            permissionId: Permissions.CREATE_PROPOSAL_PERMISSION_ID
        });

        permissions[6] = PermissionLib.MultiTargetPermission({
            operation: _op,
            where: _spp,
            who: ANY_ADDR,
            condition: PermissionLib.NO_CONDITION,
            permissionId: Permissions.ADVANCE_PERMISSION_ID
        });

        /// Permissions on the dao by SPP.
        permissions[7] = PermissionLib.MultiTargetPermission({
            operation: _op,
            where: _dao,
            who: _spp,
            condition: PermissionLib.NO_CONDITION,
            permissionId: Permissions.EXECUTE_PERMISSION_ID
        });

        /// Permissions on the ruledCondition
        permissions[8] = PermissionLib.MultiTargetPermission({
            operation: _op,
            where: _ruledCondition,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: Permissions.UPDATE_RULES_PERMISSION_ID
        });
    }
}
