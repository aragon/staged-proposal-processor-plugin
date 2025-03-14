// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {console} from "forge-std/console.sol";

import {BaseScript} from "./Base.sol";
import {PluginSettings} from "../src/utils/PluginSettings.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

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

        // Deploy a dummy proxy to force its verification
        new ERC1967Proxy(address(sppRepo), bytes(""));

        // transfer ownership of the plugin to the management DAO and revoke from deployer
        _transferOwnershipToManagementDao();

        vm.stopBroadcast();
    }

    function _createPluginRepo() internal returns (PluginRepo _sppRepo) {
        // create plugin repo
        _sppRepo = PluginRepoFactory(pluginRepoFactory).createPluginRepo(
            PluginSettings.PLUGIN_REPO_ENS_SUBDOMAIN_NAME,
            deployer
        );

        console.log(
            "- SPP PluginRepo: ",
            address(_sppRepo)
        );
        console.log(
            "- ENS subdomain",
            PluginSettings.PLUGIN_REPO_ENS_SUBDOMAIN_NAME
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
