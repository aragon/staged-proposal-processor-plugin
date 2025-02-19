// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {Constants} from "./utils/Constants.sol";
import {PluginSettings} from "../src/utils/PluginSettings.sol";
import {StagedProposalProcessorSetup as SPPSetup} from "../src/StagedProposalProcessorSetup.sol";
import {StagedProposalProcessorSetup as SPPSetupZkSync} from "../src/StagedProposalProcessorSetupZkSync.sol";

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

    // solhint-disable immutable-vars-naming
    address internal immutable deployer = vm.addr(deployerPrivateKey);

    error UnsupportedNetwork(string network);

    error InvalidVersionRelease(uint8 release, uint8 latestRelease);
    error InvalidVersionBuild(uint8 build, uint8 latestBuild);

    error SomethingWentWrong();

    function _printAragonArt() internal pure {
        console.log(ARAGON_OSX_ASCII_ART);
    }

    function getRepoFactoryAddress() public view returns (address _repoFactory) {
        string memory _json = _getOsxConfigs(network);

        string memory _repoFactoryKey = _buildKey(protocolVersion, PLUGIN_FACTORY_ADDRESS_KEY);

        if (!vm.keyExists(_json, _repoFactoryKey)) {
            revert UnsupportedNetwork(network);
        }
        _repoFactory = vm.parseJsonAddress(_json, _repoFactoryKey);
    }

    function getManagementDaoAddress() public view returns (address _managementDao) {
        string memory _json = _getOsxConfigs(network);

        string memory _managementDaoKey = _buildKey(protocolVersion, MANAGEMENT_DAO_ADDRESS_KEY);

        if (!vm.keyExists(_json, _managementDaoKey)) {
            revert UnsupportedNetwork(network);
        }
        _managementDao = vm.parseJsonAddress(_json, _managementDaoKey);
    }

    function getPluginRepoAddress() public view returns (address _sppRepo) {
        string memory _json = _getOsxConfigs(network);

        string memory _sppRepoKey = _buildKey(protocolVersion, SPP_PLUGIN_REPO_KEY);

        if (!vm.keyExists(_json, _sppRepoKey)) {
            revert UnsupportedNetwork(network);
        }
        _sppRepo = vm.parseJsonAddress(_json, _sppRepoKey);
    }

    function getBasePluginRepoAddress() public view returns (address _sppRepo) {
        string memory _json = _getOsxConfigs(network);

        string memory _sppRepoKey = _buildKey(protocolVersion, BASE_PLUGIN_REPO_KEY);

        if (!vm.keyExists(_json, _sppRepoKey)) {
            revert UnsupportedNetwork(network);
        }
        _sppRepo = vm.parseJsonAddress(_json, _sppRepoKey);
    }

    function _createAndCheckNewVersion() internal returns (SPPSetup _sppSetup) {
        bytes32 networkHash = keccak256(abi.encodePacked(network));
        if(networkHash == keccak256(abi.encodePacked("zksyncSepolia")) || networkHash == keccak256(abi.encodePacked("zksyncMainnet"))) {
            _sppSetup = SPPSetup(address(new SPPSetupZkSync()));
        } else {
            _sppSetup = new SPPSetup();
        }
        
        // Check release number
        uint256 latestRelease = sppRepo.latestRelease();

        if (PluginSettings.VERSION_RELEASE > latestRelease + 1) {
            revert InvalidVersionRelease(PluginSettings.VERSION_RELEASE, uint8(latestRelease));
        }
        // Check build number
        uint256 latestBuild = sppRepo.buildCount(uint8(latestRelease));
        if (PluginSettings.VERSION_BUILD < latestBuild + 1) {
            revert InvalidVersionBuild(PluginSettings.VERSION_BUILD, uint8(latestBuild));
        }

        // create plugin version
        sppRepo.createVersion(
            PluginSettings.VERSION_RELEASE,
            address(_sppSetup),
            PluginSettings.BUILD_METADATA,
            PluginSettings.RELEASE_METADATA
        );

        // check version was created correctly
        if (PluginSettings.VERSION_RELEASE != sppRepo.latestRelease()) {
            revert SomethingWentWrong();
        }

        console.log(
            "- SPP PluginSetup: ",
            address(_sppSetup)
        );
        console.log(
            "- Version: ",
            _versionString(PluginSettings.VERSION_RELEASE, PluginSettings.VERSION_BUILD)
        );
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

    function _versionString(uint8 _release, uint8 _build) internal pure returns (string memory) {
        return string(abi.encodePacked("v", vm.toString(_release), ".", vm.toString(_build)));
    }

    function _protocolVersionString(uint8[3] memory version) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "v",
                    vm.toString(version[0]),
                    ".",
                    vm.toString(version[1]),
                    ".",
                    vm.toString(version[2])
                )
            );
    }
}
