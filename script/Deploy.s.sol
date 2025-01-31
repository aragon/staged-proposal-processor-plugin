// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {console} from "forge-std/console.sol";

import {BaseScript} from "./Base.sol";
import {PluginSettings} from "../src/utils/PluginSettings.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";

contract Deploy is BaseScript {
    function run() external {
        _printAragonArt();
        // get deployed contracts
        pluginRepoFactory = getRepoFactoryAddress();
        managementDao = getManagementDaoAddress();

        vm.startBroadcast(deployerPrivateKey);

        // crete plugin repo and version
        sppRepo = _createPluginRepo();
        sppSetup = _createAndCheckNewVersion();

        // transfer ownership of the plugin to the management DAO and revoke from deployer
        _transferOwnershipToManagementDao();

        address[] memory addresses = new address[](2);
        addresses[0] =  address(sppRepo);
        addresses[1] = PluginRepoFactory(pluginRepoFactory).pluginRepoBase();
        
        _storeDeploymentJSON(block.chainid, addresses);
       
        vm.stopBroadcast();
    }

    function _createPluginRepo() internal returns (PluginRepo _sppRepo) {
        // create plugin repo
        _sppRepo = PluginRepoFactory(pluginRepoFactory).createPluginRepo(
            PluginSettings.PLUGIN_REPO_ENS_SUBDOMAIN_NAME,
            deployer
        );

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
