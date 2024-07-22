// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";

import {Constants} from "./utils/Constants.sol";
import {PluginSettings} from "../src/utils/PluginSettings.sol";
import {StagedProposalProcessorSetup as SPPSetup} from "../src/StagedProposalProcessorSetup.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";

import "forge-std/console.sol";

contract Deploy is Script, Constants {
    // core contracts
    address internal pluginRepoFactory;
    address internal managementDao;

    SPPSetup internal sppSetup;
    PluginRepo internal sppRepo;

    uint256 internal deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
    string internal network = vm.envString("NETWORK_NAME");
    string internal protocolVersion = vm.envString("PROTOCOL_VERSION");

    address internal deployer = vm.addr(deployerPrivateKey);

    error UnsupportedNetwork(string network);

    function run() external {
        // get deployed contracts
        (pluginRepoFactory, managementDao) = _getRepoContractAddresses(network);

        // ! 3. check if ensDomain is unclaimed if it is not revert
        // ? this will revert if the ens domain is already claimed when registering, should be checked before?

        vm.startBroadcast(deployerPrivateKey);

        // crete plugin repo and version
        (sppSetup, sppRepo) = _createPluginRepoAndVersion();

        //transfer ownership of the plugin to the management DAO and revoke from deployer
        _transferOwnershipToManagementDao();

        // ! 6. verify the contract on etherscan
        // ? adding --verify when running forge script works, sill I'm having some issues with the proxies

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
        // todo
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](6);

        // Grant to the management DAO
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

        // ? what is this root permission for?
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

    function _getRepoContractAddresses(
        string memory _network
    ) internal view returns (address _repoFactory, address _managementDao) {
        string memory _json = _getOsxConfigs(_network);

        string memory _repoFactoryKey = _buildKey(protocolVersion, pluginFactoryAddressKey);

        if (!vm.keyExistsJson(_json, _repoFactoryKey)) {
            revert UnsupportedNetwork(_network);
        }
        _repoFactory = vm.parseJsonAddress(_json, _repoFactoryKey);

        string memory _managementDaoKey = _buildKey(protocolVersion, managementDaoAddressKey);

        if (!vm.keyExistsJson(_json, _managementDaoKey)) {
            revert UnsupportedNetwork(_network);
        }
        _managementDao = vm.parseJsonAddress(_json, _managementDaoKey);
    }

    function _getOsxConfigs(string memory _network) internal view returns (string memory) {
        string memory osxConfigsPath = string.concat(
            vm.projectRoot(),
            "/",
            deploymentsPath,
            "/",
            _network,
            ".json"
        );
        return vm.readFile(osxConfigsPath);
    }

    function _buildKey(
        string memory _protocolVersion,
        string memory _contractKey
    ) internal pure returns (string memory) {
        return string.concat(".['", _protocolVersion, "'].", _contractKey);
    }
}
