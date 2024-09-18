// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {Script} from "forge-std/Script.sol";

import {Constants} from "./utils/Constants.sol";

import {StagedProposalProcessorSetup as SPPSetup} from "../src/StagedProposalProcessorSetup.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

contract BaseScript is Script, Constants {
    // core contracts
    address public pluginRepoFactory;
    address public managementDao;

    SPPSetup public sppSetup;
    PluginRepo public sppRepo;

    uint256 internal deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
    string internal network = vm.envString("NETWORK_NAME");
    string internal protocolVersion = vm.envString("PROTOCOL_VERSION");

    address internal immutable deployer = vm.addr(deployerPrivateKey);

    error UnsupportedNetwork(string network);

    function getRepoContractAddresses(
        string memory _network
    ) public view returns (address _repoFactory, address _managementDao) {
        string memory _json = _getOsxConfigs(_network);

        string memory _repoFactoryKey = _buildKey(protocolVersion, PLUGIN_FACTORY_ADDRESS_KEY);

        if (!vm.keyExists(_json, _repoFactoryKey)) {
            revert UnsupportedNetwork(_network);
        }
        _repoFactory = vm.parseJsonAddress(_json, _repoFactoryKey);

        string memory _managementDaoKey = _buildKey(protocolVersion, MANAGEMENT_DAO_ADDRESS_KEY);

        if (!vm.keyExists(_json, _managementDaoKey)) {
            revert UnsupportedNetwork(_network);
        }
        _managementDao = vm.parseJsonAddress(_json, _managementDaoKey);
    }

    function _getOsxConfigs(string memory _network) internal view returns (string memory) {
        string memory osxConfigsPath = string.concat(
            vm.projectRoot(),
            "/",
            DEPLOYMENTS_PATH,
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
