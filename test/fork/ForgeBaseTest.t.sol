// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";

import {Events} from "../utils/Events.sol";
import {Fuzzers} from "../utils/Fuzzers.sol";
import {Constants} from "../utils/Constants.sol";
import {Assertions} from "../utils/Assertions.sol";
import {Constants as ScriptConstants} from "../../script/utils/Constants.sol";
import {StagedProposalProcessorSetup as SPPSetup} from "../../src/StagedProposalProcessorSetup.sol";

import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";

import {
    hashHelpers,
    PluginSetupRef
} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

import {console} from "forge-std/console.sol";

contract ForgeBaseTest is Assertions, Constants, Events, Fuzzers, ScriptConstants, Test {
    uint256 internal deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
    string internal network = vm.envString("NETWORK_NAME");
    string internal networkRpcUrl = vm.envString("NETWORK_RPC_URL");
    string internal protocolVersion = vm.envString("PROTOCOL_VERSION");

    // solhint-disable immutable-vars-naming
    address internal immutable deployer = vm.addr(deployerPrivateKey);
    PluginRepo internal sppRepo;
    PluginRepo internal adminRepo;
    PluginRepo internal multiSigRepo;

    address internal managementDao;
    PluginSetupProcessor internal psp;
    DAOFactory internal daoFactory;

    SPPSetup internal _sppSetup;

    function setUp() public virtual {
        // Fork the "network"
        vm.createSelectFork({urlOrAlias: networkRpcUrl});

        // get needed contract addresses
        sppRepo = PluginRepo(getContractAddress(SPP_PLUGIN_REPO_KEY));
        adminRepo = PluginRepo(getContractAddress(ADMIN_PLUGIN_REPO_KEY));
        multiSigRepo = PluginRepo(getContractAddress(MULTISIG_PLUGIN_REPO_KEY));
        managementDao = getContractAddress(MANAGEMENT_DAO_ADDRESS_KEY);
        psp = PluginSetupProcessor(getContractAddress(PLUGIN_SETUP_PROCESSOR_KEY));
        daoFactory = DAOFactory(getContractAddress(DAO_FACTORY_ADDRESS_KEY));

        // publish new spp version
        _sppSetup = new SPPSetup();
        // Check release number
        uint256 latestRelease = sppRepo.latestRelease();

        uint256 latestBuild = sppRepo.buildCount(uint8(latestRelease));

        // create plugin version
        vm.prank(managementDao);
        sppRepo.createVersion(
            uint8(latestRelease),
            address(_sppSetup),
            "dummy build metadata",
            "dummy release metadata"
        );

        // check version was created correctly
        assertEq(sppRepo.latestRelease(), latestRelease, "release");
        assertEq(sppRepo.buildCount(uint8(latestRelease)), latestBuild + 1, "build");

        _labelContracts();
    }

    function _labelContracts() internal {
        vm.label(address(sppRepo), "SPP_Repo");
        vm.label(address(adminRepo), "Admin_Repo");
        vm.label(address(multiSigRepo), "Multisig_Repo");
        vm.label(address(managementDao), "Management_DAO");
        vm.label(address(psp), "PSP");
        vm.label(address(daoFactory), "DaoFactory");
    }

    function getContractAddress(string memory _baseKey) public view returns (address _sppRepo) {
        string memory _json = _getOsxDeployments(network);

        string memory _contractKey = _buildDeploymentCtrKey(protocolVersion, _baseKey);

        if (!vm.keyExistsJson(_json, _contractKey)) {
            revert UnsupportedNetwork(network);
        }
        _sppRepo = vm.parseJsonAddress(_json, _contractKey);
    }

    function _getOsxDeployments(string memory _network) internal view returns (string memory) {
        string memory osxDeploymentsPath = string.concat(
            vm.projectRoot(),
            "/",
            DEPLOYMENTS_PATH,
            "/",
            _network,
            ".json"
        );
        return vm.readFile(osxDeploymentsPath);
    }

    function _buildDeploymentCtrKey(
        string memory _protocolVersion,
        string memory _contractKey
    ) internal pure returns (string memory) {
        return string.concat(".['", _protocolVersion, "'].", _contractKey);
    }

    function _createDummyDaoAdmin()
        internal
        returns (DAO dao, DAOFactory.InstalledPlugin[] memory installedPlugins)
    {
        DAOFactory.DAOSettings memory daoSettings = DAOFactory.DAOSettings({
            trustedForwarder: address(0),
            daoURI: "dummy dao description",
            subdomain: "test-dao",
            metadata: "dummy metadata"
        });

        // install admin plugin

        // admin plugin data
        // IPlugin.TargetConfig memory adminConfig =
        bytes memory adminData = abi.encode(
            deployer,
            IPlugin.TargetConfig({target: address(0), operation: IPlugin.Operation.Call})
        );

        console.log("deployer", deployer);

        DAOFactory.PluginSettings[] memory pluginSettings = new DAOFactory.PluginSettings[](1);
        uint8 latestRelease = adminRepo.latestRelease();
        uint256 latestBuild = adminRepo.buildCount(latestRelease);
        pluginSettings[0] = DAOFactory.PluginSettings({
            pluginSetupRef: PluginSetupRef({
                versionTag: PluginRepo.Tag({release: latestRelease, build: uint16(latestBuild)}),
                pluginSetupRepo: adminRepo
            }),
            data: adminData
        });

        // return daoFactory.createDao(daoSettings, pluginSettings);

        console.log("herererere");
        daoFactory.createDao(daoSettings, pluginSettings);

        (bool success, bytes memory returnData) = address(daoFactory).call(
            abi.encodeWithSelector(daoFactory.createDao.selector, daoSettings, pluginSettings)
        );

        console.log("success", success);
        console.logBytes(returnData);
    }
}
