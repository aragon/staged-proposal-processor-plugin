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

/// @title MyPluginSetup
/// @author Aragon X - 2024
/// @notice The setup contract of the `StagedProposalProcessor` plugin.
/// @dev Release 1, Build 1
contract StagedProposalProcessorSetup is PluginUpgradeableSetup {
    using ProxyLib for address;

    /// @notice A special address encoding permissions that are valid for any address `who` or `where`.
    address private constant ANY_ADDR = address(type(uint160).max);

    /// @notice The address of the condition implementation contract.
    address public immutable CONDITION_IMPLEMENTATION;

    /// @notice Constructs the `PluginUpgradeableSetup` by storing the `SPP` implementation address.
    /// @dev The implementation address is used to deploy UUPS proxies referencing it and
    /// to verify the plugin on the respective block explorers.
    constructor() PluginUpgradeableSetup(address(new SPP())) {
        CONDITION_IMPLEMENTATION = address(
            new SPPRuleCondition(address(0), new RuledCondition.Rule[](0))
        );
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

        // Clone and initialize the plugin contract.
        bytes memory initData = abi.encodeCall(SPPRuleCondition.initialize, (_dao, rules));
        address sppCondition = CONDITION_IMPLEMENTATION.deployUUPSProxy(initData);

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
    /// @dev The default implementation for the initial build 1 that reverts because no earlier build exists.
    function prepareUpdate(
        address _dao,
        uint16 _fromBuild,
        SetupPayload calldata _payload
    ) external pure virtual returns (bytes memory, PreparedSetupData memory) {
        (_dao, _fromBuild, _payload);
        revert InvalidUpdatePath({fromBuild: 0, thisBuild: 1});
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
