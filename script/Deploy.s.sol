// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";

import {BaseScript} from "./Base.sol";

import {PluginSettings} from "../src/utils/PluginSettings.sol";
import {StagedProposalProcessorSetup as SPPSetup} from "../src/StagedProposalProcessorSetup.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";

import "forge-std/console.sol";

contract Deploy is BaseScript {

    function run() external {
        // get deployed contracts
        (pluginRepoFactory, managementDao) = getRepoContractAddresses(network);

        vm.startBroadcast(deployerPrivateKey);

        // crete plugin repo and version
        (sppSetup, sppRepo) = _createPluginRepoAndVersion();

        //transfer ownership of the plugin to the management DAO and revoke from deployer
        _transferOwnershipToManagementDao();

        vm.stopBroadcast();
    }

    function _createPluginRepoAndVersion()
        internal
        returns (SPPSetup _sppSetup, PluginRepo _sppRepo)
    {
        // create plugin repo
        _sppRepo = PluginRepoFactory(pluginRepoFactory).createPluginRepo(
            PluginSettings.PLUGIN_REPO_ENS_SUBDOMAIN_NAME,
            deployer
        );

        _sppSetup = new SPPSetup();

        // create plugin version release 1
        _sppRepo.createVersion(
            PluginSettings.VERSION_RELEASE,
            address(_sppSetup),
            PluginSettings.BUILD_METADATA,
            PluginSettings.RELEASE_METADATA
        );

        console.log("SPP repo deployed at address: ", address(_sppRepo));
        console.log("SPP setup deployed at address: ", address(_sppSetup));
    }

    function _transferOwnershipToManagementDao() internal {
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](6);

        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(sppRepo),
            who: managementDao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: sppRepo.MAINTAINER_PERMISSION_ID()
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(sppRepo),
            who: managementDao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: sppRepo.UPGRADE_REPO_PERMISSION_ID()
        });

        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(sppRepo),
            who: managementDao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: sppRepo.ROOT_PERMISSION_ID()
        });

        // Revoke from deployer
        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: address(sppRepo),
            who: deployer,
            condition: PermissionLib.NO_CONDITION,
            permissionId: sppRepo.MAINTAINER_PERMISSION_ID()
        });
        permissions[4] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: address(sppRepo),
            who: deployer,
            condition: PermissionLib.NO_CONDITION,
            permissionId: sppRepo.UPGRADE_REPO_PERMISSION_ID()
        });
        permissions[5] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: address(sppRepo),
            who: deployer,
            condition: PermissionLib.NO_CONDITION,
            permissionId: sppRepo.ROOT_PERMISSION_ID()
        });

        sppRepo.applyMultiTargetPermissions(permissions);
    }
}
