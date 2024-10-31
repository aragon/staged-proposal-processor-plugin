// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BaseScript} from "./Base.sol";
import {PluginSettings} from "../src/utils/PluginSettings.sol";
import {StagedProposalProcessorSetup as SPPSetup} from "../src/StagedProposalProcessorSetup.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";

import {console} from "forge-std/console.sol";

contract Deploy is BaseScript {
    function run() external {
        // get deployed contracts
        pluginRepoFactory = getRepoFactoryAddress();
        managementDao = getManagementDaoAddress();

        vm.startBroadcast(deployerPrivateKey);

        // crete plugin repo and version
        sppRepo = _createPluginRepo();
        sppSetup = _createAndCheckNewVersion();

        //transfer ownership of the plugin to the management DAO and revoke from deployer
        _transferOwnershipToManagementDao();

        vm.stopBroadcast();
    }

    function _createPluginRepo() internal returns (PluginRepo _sppRepo) {
        // create plugin repo
        _sppRepo = PluginRepoFactory(pluginRepoFactory).createPluginRepo(
            PluginSettings.PLUGIN_REPO_ENS_SUBDOMAIN_NAME,
            deployer
        );

        if (_sppRepo == PluginRepo(address(0))) {
            revert SomethingWentWrong();
        }

        console.log(
            "SPP repo deployed with ENS domain",
            PluginSettings.PLUGIN_REPO_ENS_SUBDOMAIN_NAME,
            "at address: ",
            address(_sppRepo)
        );
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
