// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";

import {Target} from "../utils/Target.sol";
import {Events} from "../utils/Events.sol";
import {Fuzzers} from "../utils/Fuzzers.sol";
import {Constants} from "../utils/Constants.sol";
import {Assertions} from "../utils/Assertions.sol";
import {TrustedForwarder} from "../utils/TrustedForwarder.sol";
import {PluginSettings} from "../../src/utils/PluginSettings.sol";
import {StagedProposalProcessor as SPP} from "../../src/StagedProposalProcessor.sol";
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

contract ForkBaseTest is Assertions, Constants, Events, Fuzzers, Test {
    uint256 internal deployerPrivateKey =
        vm.envOr(
            "DEPLOYER_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
    string internal networkRpcUrl = vm.envString("RPC_URL");

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
    Target internal target;

    TrustedForwarder internal trustedForwarder;

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
        sppRepo = PluginRepo(vm.envAddress("SPP_PLUGIN_REPO_ADDRESS"));
        adminRepo = PluginRepo(vm.envAddress("ADMIN_PLUGIN_REPO_ADDRESS"));
        multisigRepo = PluginRepo(vm.envAddress("MULTISIG_PLUGIN_REPO_ADDRESS"));
        managementDao = vm.envAddress("MANAGEMENT_DAO_ADDRESS");
        psp = PluginSetupProcessor(vm.envAddress("PLUGIN_SETUP_PROCESSOR_ADDRESS"));
        daoFactory = DAOFactory(vm.envAddress("DAO_FACTORY_ADDRESS"));

        // derive multisigSetup from the latest version in the repo
        PluginRepo.Tag memory latestTag = PluginRepo.Tag({
            release: multisigRepo.latestRelease(),
            build: uint16(multisigRepo.buildCount(multisigRepo.latestRelease()))
        });
        multisigSetup = PluginUpgradeableSetup(multisigRepo.getVersion(latestTag).pluginSetup);

        target = new Target();
        trustedForwarder = new TrustedForwarder();

        sppSetup = _resolveVersionUnderTest();

        _labelContracts();
    }

    /// @notice The version every fork test exercises: build `VERSION_BUILD` of the SPP repo.
    function sppVersionUnderTest() internal view returns (PluginSetupRef memory ref) {
        ref.pluginSetupRepo = sppRepo;
        ref.versionTag = PluginRepo.Tag({
            release: PluginSettings.VERSION_RELEASE,
            build: PluginSettings.VERSION_BUILD
        });
    }

    /// @dev Uses the on-chain setup once this version is published, so the tests check what DAOs
    ///      actually upgrade to. Before that, publishes a setup built from this source as the next
    ///      build, which only lines up with `VERSION_BUILD` when the fork holds every earlier build.
    function _resolveVersionUnderTest() private returns (SPPSetup) {
        uint8 release = PluginSettings.VERSION_RELEASE;
        uint16 build = PluginSettings.VERSION_BUILD;
        uint256 publishedBuilds = sppRepo.buildCount(release);

        if (publishedBuilds >= build) {
            return
                SPPSetup(
                    sppRepo.getVersion(PluginRepo.Tag({release: release, build: build})).pluginSetup
                );
        }

        assertEq(publishedBuilds, build - 1, "fork is missing builds before the version under test");

        SPPSetup setup = new SPPSetup(new SPP());
        resetPrank(managementDao);
        sppRepo.createVersion(release, address(setup), "dummy build metadata", "dummy release metadata");
        resetPrank(deployer);

        assertEq(sppRepo.buildCount(release), build, "version under test published");
        return setup;
    }

    function _labelContracts() internal {
        vm.label(address(sppRepo), "SPP_Repo");
        vm.label(address(adminRepo), "Admin_Repo");
        vm.label(address(multisigRepo), "Multisig_Repo");
        vm.label(address(managementDao), "Management_DAO");
        vm.label(address(psp), "PSP");
        vm.label(address(daoFactory), "DaoFactory");
        vm.label(address(multisigSetup), "Multisig_Setup");
        vm.label(address(target), "Target");
        vm.label(address(trustedForwarder), "TrustedForwarder");
    }

    function _createDummyDaoAdmin()
        internal
        returns (DAO dao, DAOFactory.InstalledPlugin[] memory installedPlugins)
    {
        DAOFactory.DAOSettings memory daoSettings = DAOFactory.DAOSettings({
            trustedForwarder: address(0),
            daoURI: "dummy dao description",
            subdomain: "test-dao-some-unique-subdomain",
            metadata: "dummy metadata"
        });

        // admin plugin data
        bytes memory adminData = abi.encode(
            deployer,
            IPlugin.TargetConfig({target: address(0), operation: IPlugin.Operation.Call})
        );

        DAOFactory.PluginSettings[] memory pluginSettings = new DAOFactory.PluginSettings[](1);

        pluginSettings[0] = DAOFactory.PluginSettings({
            pluginSetupRef: getPluginSetupRef(adminRepo),
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
            IPlugin.TargetConfig({
                target: address(trustedForwarder),
                operation: IPlugin.Operation.Call
            }),
            "dummy multisig metadata"
        );

        PluginSetupRef memory multisigSetupRef = getPluginSetupRef(multisigRepo);

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

        vm.label(plugin, "MultisigPlugin");
    }

    function _installSPP(
        DAO dao,
        bytes memory sppData
    ) internal returns (address plugin, address[] memory helpers) {
        resetPrank(address(dao));
        PluginSetupRef memory sppSetupRef = sppVersionUnderTest();

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

        assertEq(_proxyImpl(plugin), sppSetup.implementation(), "installed the version under test");

        // set trusted forwarder
        SPP(plugin).setTrustedForwarder(address(trustedForwarder));

        // revoke root permission to the psp
        dao.revoke(address(dao), address(psp), dao.ROOT_PERMISSION_ID());
        resetPrank(deployer);

        vm.label(plugin, "SPPPlugin");
    }

    function _uninstallSPP(DAO dao, address plugin, address[] memory currentHelpers) internal {
        resetPrank(address(dao));
        PluginSetupRef memory sppSetupRef = sppVersionUnderTest();

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

    /// @dev EIP-1967 impl slot: bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1).
    function _proxyImpl(address _proxy) internal view returns (address) {
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        return address(uint160(uint256(vm.load(_proxy, slot))));
    }

    function getPluginSetupRef(
        PluginRepo _pluginRepo
    ) internal view returns (PluginSetupRef memory) {
        uint8 latestRelease = _pluginRepo.latestRelease();
        uint256 latestBuild = _pluginRepo.buildCount(latestRelease);

        return
            PluginSetupRef({
                versionTag: PluginRepo.Tag({release: latestRelease, build: uint16(latestBuild)}),
                pluginSetupRepo: _pluginRepo
            });
    }

    function multisigCallApprove(
        address _multisig,
        uint256 _proposalId,
        bool _tryExecute
    ) internal returns (bool success, bytes memory data) {
        (success, data) = _multisig.call(
            abi.encodeWithSignature("approve(uint256,bool)", _proposalId, _tryExecute)
        );
    }

    function resetPrank(address msgSender) public {
        vm.stopPrank();
        vm.startPrank(msgSender);
    }
}
