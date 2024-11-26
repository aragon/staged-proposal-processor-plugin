// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";

import {Events} from "../utils/Events.sol";
import {Fuzzers} from "../utils/Fuzzers.sol";
import {Constants} from "../utils/Constants.sol";
import {Assertions} from "../utils/Assertions.sol";
import {Constants as ScriptConstants} from "../../script/utils/Constants.sol";
import {StagedProposalProcessorSetup as SPPSetup} from "../../src/StagedProposalProcessorSetup.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";

import {
    hashHelpers,
    PluginSetupRef
} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {
    PluginUpgradeableSetup
} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginUpgradeableSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";

contract ForkBaseTest is Assertions, Constants, Events, Fuzzers, ScriptConstants, Test {
    uint256 internal deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
    string internal network = vm.envString("NETWORK_NAME");
    string internal networkRpcUrl = vm.envString("NETWORK_RPC_URL");
    string internal protocolVersion = vm.envString("PROTOCOL_VERSION");

    // solhint-disable immutable-vars-naming
    address internal immutable deployer = vm.addr(deployerPrivateKey);
    PluginRepo internal sppRepo;
    PluginRepo internal adminRepo;
    PluginRepo internal multisigRepo;

    PluginUpgradeableSetup internal multisigSetup;

    address internal managementDao;
    PluginSetupProcessor internal psp;
    DAOFactory internal daoFactory;

    SPPSetup internal sppSetup;

    address[] internal members = [address(1), address(2), address(3)];

    // helper structs
    struct MultisigSettings {
        bool onlyListed;
        uint16 minApprovals;
    }

    function setUp() public virtual {
        // Fork the "network"
        vm.createSelectFork({urlOrAlias: networkRpcUrl});

        // get needed contract addresses
        sppRepo = PluginRepo(getContractAddress(SPP_PLUGIN_REPO_KEY));
        adminRepo = PluginRepo(getContractAddress(ADMIN_PLUGIN_REPO_KEY));
        multisigRepo = PluginRepo(getContractAddress(MULTISIG_PLUGIN_REPO_KEY));
        managementDao = getContractAddress(MANAGEMENT_DAO_ADDRESS_KEY);
        psp = PluginSetupProcessor(getContractAddress(PLUGIN_SETUP_PROCESSOR_KEY));
        daoFactory = DAOFactory(getContractAddress(DAO_FACTORY_ADDRESS_KEY));
        multisigSetup = PluginUpgradeableSetup(getContractAddress(MULTISIG_PLUGIN_SETUP_KEY));

        // publish new spp version
        sppSetup = new SPPSetup();
        // Check release number
        uint256 latestRelease = sppRepo.latestRelease();

        uint256 latestBuild = sppRepo.buildCount(uint8(latestRelease));

        // create plugin version
        resetPrank(managementDao);
        sppRepo.createVersion(
            uint8(latestRelease),
            address(sppSetup),
            "dummy build metadata",
            "dummy release metadata"
        );

        resetPrank(deployer);
        // check version was created correctly
        assertEq(sppRepo.latestRelease(), latestRelease, "release");
        assertEq(sppRepo.buildCount(uint8(latestRelease)), latestBuild + 1, "build");

        _labelContracts();
    }

    function _labelContracts() internal {
        vm.label(address(sppRepo), "SPP_Repo");
        vm.label(address(adminRepo), "Admin_Repo");
        vm.label(address(multisigRepo), "Multisig_Repo");
        vm.label(address(managementDao), "Management_DAO");
        vm.label(address(psp), "PSP");
        vm.label(address(daoFactory), "DaoFactory");
        vm.label(address(multisigSetup), "Multisig_Setup");
    }

    function getContractAddress(string memory _baseKey) public view returns (address) {
        string memory _json = _getOsxDeployments(network);

        string memory _contractKey = _buildDeploymentCtrKey(protocolVersion, _baseKey);

        if (!vm.keyExistsJson(_json, _contractKey)) {
            revert UnsupportedNetwork(network);
        }
        return vm.parseJsonAddress(_json, _contractKey);
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

        // admin plugin data
        bytes memory adminData = abi.encode(
            deployer,
            IPlugin.TargetConfig({target: address(0), operation: IPlugin.Operation.Call})
        );

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

        (dao, installedPlugins) = daoFactory.createDao(daoSettings, pluginSettings);

        vm.label(address(dao), "DAO");
        vm.label(installedPlugins[0].plugin, "AdminPlugin");
    }

    function _installMultisigAndRevokeRoot(DAO dao) internal returns (address plugin) {
        resetPrank(address(dao));
        bytes memory multisigData = abi.encode(
            members,
            MultisigSettings({onlyListed: true, minApprovals: 2}),
            IPlugin.TargetConfig({target: address(0), operation: IPlugin.Operation.Call}),
            "dummy multisig metadata"
        );

        uint8 latestRelease = multisigRepo.latestRelease();
        uint256 latestBuild = multisigRepo.buildCount(latestRelease);
        PluginSetupRef memory multisigSetupRef = PluginSetupRef({
            versionTag: PluginRepo.Tag({release: latestRelease, build: uint16(latestBuild)}),
            pluginSetupRepo: multisigRepo
        });

        IPluginSetup.PreparedSetupData memory preparedSetupData;

        (plugin, preparedSetupData) = psp.prepareInstallation(
            address(dao),
            PluginSetupProcessor.PrepareInstallationParams(multisigSetupRef, multisigData)
        );

        // grant temporary root permission to psp
        dao.grant(address(dao), address(psp), dao.ROOT_PERMISSION_ID());

        // Apply plugin.
        psp.applyInstallation(
            address(dao),
            PluginSetupProcessor.ApplyInstallationParams(
                multisigSetupRef,
                plugin,
                preparedSetupData.permissions,
                hashHelpers(preparedSetupData.helpers)
            )
        );

        // revoke root permission to the psp
        dao.revoke(address(dao), address(psp), dao.ROOT_PERMISSION_ID());

        // revoke execute permission to the plugin
        dao.revoke(address(dao), plugin, dao.EXECUTE_PERMISSION_ID());

        resetPrank(deployer);
    }

    function _installSPP(
        DAO dao,
        bytes memory sppData
    ) internal returns (address plugin, address[] memory helpers) {
        resetPrank(address(dao));
        uint8 latestRelease = sppRepo.latestRelease();
        uint256 latestBuild = sppRepo.buildCount(latestRelease);
        PluginSetupRef memory sppSetupRef = PluginSetupRef({
            versionTag: PluginRepo.Tag({release: latestRelease, build: uint16(latestBuild)}),
            pluginSetupRepo: sppRepo
        });

        IPluginSetup.PreparedSetupData memory preparedSetupData;
        (plugin, preparedSetupData) = psp.prepareInstallation(
            address(dao),
            PluginSetupProcessor.PrepareInstallationParams(sppSetupRef, sppData)
        );

        helpers = preparedSetupData.helpers;

        // grant temporary root permission to psp
        dao.grant(address(dao), address(psp), dao.ROOT_PERMISSION_ID());

        // Apply plugin.
        psp.applyInstallation(
            address(dao),
            PluginSetupProcessor.ApplyInstallationParams(
                sppSetupRef,
                plugin,
                preparedSetupData.permissions,
                hashHelpers(preparedSetupData.helpers)
            )
        );

        // revoke root permission to the psp
        dao.revoke(address(dao), address(psp), dao.ROOT_PERMISSION_ID());
        resetPrank(deployer);
    }

    function _uninstallSPP(DAO dao, address plugin, address[] memory currentHelpers) internal {
        resetPrank(address(dao));
        uint8 latestRelease = sppRepo.latestRelease();
        uint256 latestBuild = sppRepo.buildCount(latestRelease);
        PluginSetupRef memory sppSetupRef = PluginSetupRef({
            versionTag: PluginRepo.Tag({release: latestRelease, build: uint16(latestBuild)}),
            pluginSetupRepo: sppRepo
        });

        PermissionLib.MultiTargetPermission[] memory permissions = psp.prepareUninstallation(
            address(dao),
            PluginSetupProcessor.PrepareUninstallationParams(
                sppSetupRef,
                IPluginSetup.SetupPayload(plugin, currentHelpers, bytes(""))
            )
        );

        // grant temporary root permission to psp
        dao.grant(address(dao), address(psp), dao.ROOT_PERMISSION_ID());

        // Apply plugin.
        psp.applyUninstallation(
            address(dao),
            PluginSetupProcessor.ApplyUninstallationParams(plugin, sppSetupRef, permissions)
        );

        // revoke root permission to the psp
        dao.revoke(address(dao), address(psp), dao.ROOT_PERMISSION_ID());
        resetPrank(deployer);
    }

    function resetPrank(address msgSender) public {
        vm.stopPrank();
        vm.startPrank(msgSender);
    }
}
