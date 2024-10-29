// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {
    PluginUpgradeableSetup
} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginUpgradeableSetup.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {
    PowerfulCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/PowerfulCondition.sol";

import {StagedProposalProcessor as SPP} from "./StagedProposalProcessor.sol";
import {SPPRuleCondition} from "./utils/SPPRuleCondition.sol";

/// @title MyPluginSetup
/// @dev Release 1, Build 1
contract StagedProposalProcessorSetup is PluginUpgradeableSetup {
    using ProxyLib for address;

    /// @notice The identifier of the `EXECUTE_PERMISSION` permission.
    bytes32 public constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");

    /// @notice The ID of the permission required to call the `updateStages` function.
    bytes32 public constant UPDATE_STAGES_PERMISSION_ID = keccak256("UPDATE_STAGES_PERMISSION");

    /// @notice The ID of the permission required to call the `setTrustedForwarder` function.
    bytes32 public constant SET_TRUSTED_FORWARDER_PERMISSION_ID =
        keccak256("SET_TRUSTED_FORWARDER_PERMISSION");

    /// @notice The ID of the permission required to call the `createProposal` function.
    bytes32 public constant CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");

    /// @notice The ID of the permission required to call the `updateRules` function.
    bytes32 public constant UPDATE_RULES_PERMISSION_ID = keccak256("UPDATE_RULES_PERMISSION");

    /// @notice The ID of the permission required to call the `setTargetConfig` function.
    bytes32 public constant SET_TARGET_CONFIG_PERMISSION_ID =
        keccak256("SET_TARGET_CONFIG_PERMISSION");

    /// @notice The ID of the permission required to call the `updateMetadata` function.
    bytes32 public constant SET_METADATA_PERMISSION_ID = keccak256("SET_METADATA_PERMISSION");

    /// @notice A special address encoding permissions that are valid for any address `who` or `where`.
    address internal constant ANY_ADDR = address(type(uint160).max);

    /// @notice The address of the condition implementation contract.
    address public immutable CONDITION_IMPLEMENTATION;

    /// @notice The condition that always returns true.
    address private immutable ALWAYS_TRUE_CONDITION;
    
    /// @notice Thrown if the `allowedProposer` address is empty only if `rules` are also empty.
    error InvalidAllowedProposer();

    /// @notice Constructs the `PluginUpgradeableSetup` by storing the `MyPlugin` implementation address.
    /// @dev The implementation address is used to deploy UUPS proxies referencing it and
    /// to verify the plugin on the respective block explorers.
    constructor(address alwaysTrueCondition) PluginUpgradeableSetup(address(new SPP())) {
        CONDITION_IMPLEMENTATION = address(
            new SPPRuleCondition(address(0), new PowerfulCondition.Rule[](0))
        );
        ALWAYS_TRUE_CONDITION = alwaysTrueCondition;
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes calldata _data
    ) external returns (address spp, PreparedSetupData memory preparedSetupData) {
        (
            SPP.Stage[] memory stages,
            bytes memory pluginMetadata,
            IPlugin.TargetConfig memory targetConfig,
            PowerfulCondition.Rule[] memory rules,
            address allowedProposer
        ) = abi.decode(
                _data,
                (SPP.Stage[], bytes, IPlugin.TargetConfig, PowerfulCondition.Rule[], address)
            );

        if (rules.length == 0 && allowedProposer == address(0)) {
            revert InvalidAllowedProposer();
        }

        // Note that by default, we assume that sub-plugins will call the executor with
        // a delegate call which will still make `msg.sender` to be sub-plugin on SPP,
        // so as default, we set trusted forwarder = address(0), but grantee of
        // `SET_TRUSTED_FORWARDER_PERMISSION` can anytime set the actual address.
        // Setting a user's passed trusted forwarder below is dangerous in case plugin
        // installer is malicious.
        spp = IMPLEMENTATION.deployUUPSProxy(
            abi.encodeCall(
                SPP.initialize,
                (IDAO(_dao), address(0), stages, pluginMetadata, targetConfig)
            )
        );

        uint256 permissionCount = 6;
        uint256 count = 5;

        // Figure out how many permissions are needed.
        if (allowedProposer != address(0) && allowedProposer != ANY_ADDR) permissionCount++;
        if (rules.length != 0) permissionCount++;

        // Clone and initialize the plugin contract.
        bytes memory initData = abi.encodeCall(SPPRuleCondition.initialize, (_dao, rules));
        address sppCondition = CONDITION_IMPLEMENTATION.deployMinimalProxy(initData);

        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](permissionCount);

        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: spp,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: UPDATE_STAGES_PERMISSION_ID
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _dao,
            who: spp,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });

        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: spp,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: SET_TRUSTED_FORWARDER_PERMISSION_ID
        });

        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: spp,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: SET_TARGET_CONFIG_PERMISSION_ID
        });

        permissions[4] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: spp,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: SET_METADATA_PERMISSION_ID
        });

        permissions[5] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: sppCondition,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: UPDATE_RULES_PERMISSION_ID
        });

        // Even if the `rules` are non-empty, it might still be useful
        // to be able to grant the permission directly to someone without condition.
        if (allowedProposer != address(0) && allowedProposer != ANY_ADDR) {
            permissions[++count] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Grant,
                where: spp,
                who: allowedProposer,
                condition: PermissionLib.NO_CONDITION,
                permissionId: CREATE_PROPOSAL_PERMISSION_ID
            });
        }

        if (rules.length != 0) {
            permissions[++count] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.GrantWithCondition,
                where: spp,
                who: ANY_ADDR,
                condition: sppCondition,
                permissionId: CREATE_PROPOSAL_PERMISSION_ID
            });
        } else if (allowedProposer == ANY_ADDR) {
            permissions[++count] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.GrantWithCondition,
                where: spp,
                who: ANY_ADDR,
                condition: ALWAYS_TRUE_CONDITION,
                permissionId: CREATE_PROPOSAL_PERMISSION_ID
            });
        }

        preparedSetupData.permissions = permissions;
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
        permissions = new PermissionLib.MultiTargetPermission[](7);

        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: UPDATE_STAGES_PERMISSION_ID
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _dao,
            who: _payload.plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });

        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: SET_TRUSTED_FORWARDER_PERMISSION_ID
        });

        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: SET_TARGET_CONFIG_PERMISSION_ID
        });

        permissions[4] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: SET_METADATA_PERMISSION_ID
        });

        permissions[5] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: ANY_ADDR,
            condition: PermissionLib.NO_CONDITION,
            permissionId: CREATE_PROPOSAL_PERMISSION_ID
        });

        permissions[6] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.currentHelpers[0], // sppRuleCondition
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: UPDATE_RULES_PERMISSION_ID
        });
    }
}
