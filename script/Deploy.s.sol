// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.18;

import {console} from "forge-std/console.sol";

import {BaseScript} from "./Base.sol";
import {PluginSettings} from "../src/utils/PluginSettings.sol";
import {StagedProposalProcessor as SPP} from "../src/StagedProposalProcessor.sol";
import {StagedProposalProcessorSetup as SPPSetup} from "../src/StagedProposalProcessorSetup.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Deploy is BaseScript {
    error InvalidVersionRelease(uint8 release, uint8 latestRelease);
    error InvalidVersionBuild(uint8 build, uint8 latestBuild);
    error SomethingWentWrong();

    function run() external {
        // get deployed contracts
        pluginRepoFactory = getRepoFactoryAddress();
        managementDao = getManagementDaoAddress();

        vm.startBroadcast(deployerPrivateKey);

        // crete plugin repo and version
        sppRepo = _createPluginRepo();

        sppSetup = new SPPSetup(new SPP(), block.chainid != 324 && block.chainid != 300);

        uint256 latestRelease = sppRepo.latestRelease();
        if (PluginSettings.VERSION_RELEASE > latestRelease + 1) {
            revert InvalidVersionRelease(PluginSettings.VERSION_RELEASE, uint8(latestRelease));
        }
        uint256 latestBuild = sppRepo.buildCount(uint8(latestRelease));
        if (PluginSettings.VERSION_BUILD < latestBuild + 1) {
            revert InvalidVersionBuild(PluginSettings.VERSION_BUILD, uint8(latestBuild));
        }

        sppRepo.createVersion(
            PluginSettings.VERSION_RELEASE,
            address(sppSetup),
            bytes(PluginSettings.BUILD_METADATA),
            bytes(PluginSettings.RELEASE_METADATA)
        );

        if (PluginSettings.VERSION_RELEASE != sppRepo.latestRelease()) {
            revert SomethingWentWrong();
        }

        // Deploy a dummy proxy to force its verification
        new ERC1967Proxy(address(sppRepo), bytes(""));

        // transfer ownership of the plugin to the management DAO and revoke from deployer
        _transferOwnershipToManagementDao();

        vm.stopBroadcast();

        console.log("- SPP PluginRepo:   ", address(sppRepo));
        console.log("- SPP PluginSetup:  ", address(sppSetup));
        console.log("- Implementation:   ", sppSetup.implementation());
        console.log("- Version:          ", _versionString(PluginSettings.VERSION_RELEASE, PluginSettings.VERSION_BUILD));
    }

    function _createPluginRepo() internal returns (PluginRepo _sppRepo) {
        string memory subdomain = vm.envOr("SPP_ENS_SUBDOMAIN", string(""));
        if (bytes(subdomain).length == 0) {
            subdomain = string.concat("spp-", vm.toString(block.timestamp));
        }
        console.log("- ENS subdomain:    ", subdomain);
        _sppRepo = PluginRepoFactory(pluginRepoFactory).createPluginRepo(subdomain, deployer);
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
