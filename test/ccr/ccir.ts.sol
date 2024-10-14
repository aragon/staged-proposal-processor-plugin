// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {Test, Vm} from "forge-std/Test.sol";

import {StagedProposalProcessor as SPP} from "../../src/StagedProposalProcessor.sol";
import {PluginSetupProcessor} from "@aragon/osx-new/framework/plugin/setup/PluginSetupProcessor.sol";
import {ENSSubdomainRegistrar} from "@aragon/osx-new/framework/utils/ens/ENSSubdomainRegistrar.sol";

import {PluginRepo} from "@aragon/osx-new/framework/plugin/repo/PluginRepo.sol";
import {MajorityVotingBase} from "@aragon/token-voting/MajorityVotingBase.sol";
import {Action, IExecutor} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";


import {
IERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import {DAOFactory} from "@aragon/osx-new/framework/dao/DAOFactory.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAO} from "@aragon/osx-new/core/dao/DAO.sol";

import {DAORegistry} from "@aragon/osx-new/framework/dao/DAORegistry.sol";

//Multisig imports
import {Multisig} from "@aragon/multisig/Multisig.sol";
import {MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";

//Admin imports
import {Admin} from "@aragon/admin/Admin.sol";
import {AdminSetup} from "@aragon/admin/AdminSetup.sol";

//TokenVoting imports
import {TokenVoting} from "@aragon/token-voting/TokenVoting.sol";
import {IMajorityVoting} from "@aragon/token-voting/IMajorityVoting.sol";
import {TokenVotingSetup} from "@aragon/token-voting/TokenVotingSetup.sol";
import {GovernanceERC20} from "@aragon/token-voting/ERC20/governance/GovernanceERC20.sol";

import {
    GovernanceWrappedERC20
} from "@aragon/token-voting/ERC20/governance/GovernanceWrappedERC20.sol";

import {
PluginSetupRef,
hashHelpers
} from "@aragon/osx-new/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {StagedProposalProcessorSetup} from "../../src/StagedProposalProcessorSetup.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {
PluginUUPSUpgradeable
} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";
import {PermissionManager} from "@aragon/osx-new/core/permission/PermissionManager.sol";

import {PluginRepoFactory as IPluginRepoFactory} from "@aragon/osx-new/framework/plugin/repo/PluginRepoFactory.sol";
import "forge-std/console.sol";
import {BaseTest} from "./../BaseTest.t.sol";
import {TrustedForwarder} from "../../src/utils/TrustedForwarder.sol";
import {Target} from '../utils/Target.sol';
import {PluginRepoRegistry} from "@aragon/osx-new/framework/plugin/repo/PluginRepoRegistry.sol";

contract SppIntegrationTest is BaseTest {

    DAOFactory public daoFactory;
    IPluginRepoFactory public pluginRepoFactory = IPluginRepoFactory(0x07f49c49Ce2A99CF7C28F66673d406386BDD8Ff4);

    PluginSetupProcessor public psp = PluginSetupProcessor(0xC24188a73dc09aA7C721f96Ad8857B469C01dC9f);
    DAORegistry public daoRegistry = DAORegistry(0x308a1DC5020c4B5d992F5543a7236c465997fecB);


    PluginRepo public multisigPluginRepo;
    PluginRepo public tokenVotingRepo;
    PluginRepo public sppRepo;
    PluginRepo public adminRepo;

    address public sppPluginAddress;
    address public tokenvotingPluginAddr;
    address public multisigPluginAddr;

    address public adminPlugin;

    error LogNotFound(bytes32 topic);

    function setUp() override public {
        setupPluginRepo();
        createDaoWithAuthPlugin();
        trustedForwarder = new TrustedForwarder();
        target = new Target();
//        setupDaoRegistry();
    }

//    function setupDaoRegistry() internal {
//        IDAO managementDao = IDAO(
//            createProxyAndCall(
//                address(new DAO()),
//                abi.encodeCall(DAO.initialize, ("", address(this), address(0x0), ""))
//            )
//        );
//
//        daoRegistry = createProxyAndCall(
//            address(new DAORegistry()),
//            abi.encodeCall(DAORegistry.initialize, (address(managementDao), ENSSubdomainRegistrar(0x11C12ECfdDa98e19D765904DCe1Ac2C0504F64c5)))
//        );
//
//        PluginRepoRegistry repoRegistry = createProxyAndCall(
//            address(new PluginRepoRegistry()),
//            abi.encodeCall(PluginRepoRegistry.initialize, (address(managementDao), ENSSubdomainRegistrar(0x11C12ECfdDa98e19D765904DCe1Ac2C0504F64c5)))
//        );
//
//        IPluginRepoFactory pluginRepoFactory = new IPluginRepoFactory(repoRegistry);
//
//        daoFactory = new DAOFactory(daoRegistry, psp);
//
//        managementDao.grant(address(daoRegistry), address(daoFactory), keccak256("REGISTER_DAO_PERMISSION"));
//        managementDao.grant(address(repoRegistry), address(pluginRepoFactory), keccak256("REGISTER_PLUGIN_REPO_PERMISSION"));
//    }

    function setupPluginRepo() internal {
        console.log("Setting up Plugin Repos");

        // create admin repo
        adminRepo = pluginRepoFactory.createPluginRepo("admingio", address(this));
        AdminSetup adminSetup = new AdminSetup();
        adminRepo.createVersion(1, address(adminSetup), "dummy", "dummy");

        // create spp repo
        sppRepo = pluginRepoFactory.createPluginRepo("sppgio", address(this));
        StagedProposalProcessorSetup sppSetup = new StagedProposalProcessorSetup();
        sppRepo.createVersion(1, address(sppSetup), "dummy", "dummy");

        // create multisig repo
        multisigPluginRepo = pluginRepoFactory.createPluginRepo("multisiggio", address(this));
        MultisigSetup multisigSetup = new MultisigSetup();
        multisigPluginRepo.createVersion(1, address(multisigSetup), "dummy", "dummy");

        // create tokenvoting repo
        tokenVotingRepo = pluginRepoFactory.createPluginRepo("tokenvotinggio", address(this));

        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings({
            receivers: new address[](0),
            amounts: new uint256[](0)
        });

        TokenVotingSetup tokenVotingSetup = new TokenVotingSetup(
            new GovernanceERC20(IDAO(address(0)), "nn", "nn", mintSettings),
            new GovernanceWrappedERC20(IERC20Upgradeable(address(0)), "nn", "nn")
        );

        tokenVotingRepo.createVersion(1, address(tokenVotingSetup), "dummy", "dummy");
    }

    function findLog(Vm.Log[] memory logs, bytes32 topic) public pure returns (Vm.Log memory) {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == topic) {
                return logs[i];
            }
        }
        revert LogNotFound(topic);
    }

    function createDaoWithAuthPlugin() internal {

        daoFactory = new DAOFactory(daoRegistry, psp);

        DAOFactory.DAOSettings memory daoSettings = DAOFactory.DAOSettings({
            trustedForwarder: address(0),
            daoURI: "nothing",
            subdomain: "awesome",
            metadata: bytes("0x11")
        });

        DAOFactory.PluginSettings[] memory pluginSettings = new DAOFactory.PluginSettings[](1);

        PluginUUPSUpgradeable.TargetConfig memory targetConfig = PluginUUPSUpgradeable
            .TargetConfig({target: address(0), operation: PluginUUPSUpgradeable.Operation.Call});

        pluginSettings[0] = DAOFactory.PluginSettings({
            pluginSetupRef: PluginSetupRef(PluginRepo.Tag(1, 1), PluginRepo(adminRepo)),
            data: abi.encode(address(this), targetConfig)
        });

        address managementDAO = 0xCa834B3F404c97273f34e108029eEd776144d324;

        vm.prank(address(managementDAO));

        DAO(payable(managementDAO)).grant(address(daoRegistry), address(daoFactory), keccak256("REGISTER_DAO_PERMISSION"));

        vm.stopPrank();

        vm.recordLogs();

        dao = IDAO(address(daoFactory.createDao(daoSettings, pluginSettings)));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        // InstallationApplied
        Vm.Log memory log = findLog(
            logs,
            bytes32(0x74e616c7264536b98a5ec234d051ae6ce1305bf05c85f9ddc112364440ccf129)
        );

        adminPlugin = address(uint160(uint256(log.topics[2])));
    }

    function getPSPPrepareInstallationAction(
        PluginSetupProcessor.PrepareInstallationParams memory _params
    ) internal view returns (Action memory) {
        return Action({
            to: address(psp),
            value: 0,
            data: abi.encodeCall(PluginSetupProcessor.prepareInstallation, (address(dao), _params))
        });
    }

    function getMultisigPrepareInstallationParams()
    public
    view
    returns (PluginSetupProcessor.PrepareInstallationParams memory)
    {
        address[] memory members = new address[](1);
        members[0] = address(this);

        Multisig.MultisigSettings memory settings = Multisig.MultisigSettings({
            onlyListed: true,
            minApprovals: 1
        });

        PluginUUPSUpgradeable.TargetConfig memory targetConfig = PluginUUPSUpgradeable
            .TargetConfig({target: address(trustedForwarder), operation: PluginUUPSUpgradeable.Operation.DelegateCall});

        return
            PluginSetupProcessor.PrepareInstallationParams(
            PluginSetupRef(PluginRepo.Tag(1, 1), PluginRepo(multisigPluginRepo)),
            abi.encode(members, settings, targetConfig, bytes("0x11"))
        );
    }

    function getTokenVotingPrepareInstallationParams()
    public
    view
    returns (PluginSetupProcessor.PrepareInstallationParams memory)
    {
        MajorityVotingBase.VotingSettings memory votingsettings = MajorityVotingBase
            .VotingSettings({
            votingMode: MajorityVotingBase.VotingMode.EarlyExecution,
            supportThreshold: 1,
            minParticipation: 1,
            minDuration: 61 minutes,
            minProposerVotingPower: 0
        });

        TokenVotingSetup.TokenSettings memory tokenSettings = TokenVotingSetup.TokenSettings({
            addr: address(0),
            name: "gio",
            symbol: "symbol"
        });

        address[] memory receivers = new address[](1);
        receivers[0] = address(this);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;

        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings({
            receivers: receivers,
            amounts: amounts
        });

        PluginUUPSUpgradeable.TargetConfig memory targetConfig = PluginUUPSUpgradeable
            .TargetConfig({target: address(trustedForwarder), operation: PluginUUPSUpgradeable.Operation.DelegateCall});

        uint256 minApprovals = 0;

        return
            PluginSetupProcessor.PrepareInstallationParams(
            PluginSetupRef(PluginRepo.Tag(1, 1), PluginRepo(tokenVotingRepo)),
            abi.encode(votingsettings, tokenSettings, mintSettings, targetConfig, minApprovals)
        );
    }

    function getSPPPrepareInstallationParams()
    public
    view
    returns (PluginSetupProcessor.PrepareInstallationParams memory)
    {
        PluginUUPSUpgradeable.TargetConfig memory targetConfig = PluginUUPSUpgradeable
            .TargetConfig({target: address(0), operation: PluginUUPSUpgradeable.Operation.Call});

        SPP.Stage[] memory stages = new SPP.Stage[](0);

        return PluginSetupProcessor.PrepareInstallationParams(
            PluginSetupRef(PluginRepo.Tag(1, 1), PluginRepo(sppRepo)),
            abi.encode(stages, bytes("0x11"), targetConfig)
        );
    }

    function setupDao() internal returns(SPP.Stage[] memory,address) {
        Action[] memory prepareInstallActions = new Action[](3);

        prepareInstallActions[0] = getPSPPrepareInstallationAction(getMultisigPrepareInstallationParams());
        prepareInstallActions[1] = getPSPPrepareInstallationAction(getTokenVotingPrepareInstallationParams());
        prepareInstallActions[2] = getPSPPrepareInstallationAction(getSPPPrepareInstallationParams());
        vm.recordLogs();
        Admin(adminPlugin).executeProposal(bytes("0x11"), prepareInstallActions, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // InstallationApplied

        bytes32 eventSelector = keccak256(
            "Executed(address,bytes32,(address,uint256,bytes)[],uint256,uint256,bytes[])"
        );

        Vm.Log memory log = findLog(logs, eventSelector);

        (, , , , bytes[] memory results) = abi.decode(
            log.data,
            (bytes32, Action[], uint256, uint256, bytes[])
        );

        PluginRepo[] memory repos = new PluginRepo[](3);
        repos[0] = multisigPluginRepo;
        repos[1] = tokenVotingRepo;
        repos[2] = sppRepo;

        Action[] memory installActions = new Action[](7);

        installActions[0] = Action({
            to: address(dao),
            value: 0,
            data: abi.encodeCall(PermissionManager.setApplyTargetMethodGrantee, (address(psp)))
        });

        installActions[1] = Action({
            to: address(dao),
            value: 0,
            data: abi.encodeCall(
                PermissionManager.grant,
                (address(dao), address(psp), keccak256("APPLY_TARGET_PERMISSION"))
            )
        });

        installActions[5] = Action({
            to: address(dao),
            value: 0,
            data: abi.encodeCall(
                PermissionManager.revoke,
                (address(dao), address(psp), keccak256("APPLY_TARGET_PERMISSION"))
            )
        });

        for (uint256 i = 0; i < results.length; i++) {
            (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData) = abi.decode(
                results[i],
                (address, IPluginSetup.PreparedSetupData)
            );

            if (i == 0) multisigPluginAddr = plugin;
            if (i == 1) tokenvotingPluginAddr = plugin;
            if (i == 2) sppPluginAddress = plugin;

            console.log("======");
            console.log(plugin);

            installActions[i + 2] = Action({
                to: address(psp),
                value: 0,
                data: abi.encodeCall(
                    psp.applyInstallation,
                    (
                        address(dao),
                        PluginSetupProcessor.ApplyInstallationParams(
                        PluginSetupRef(PluginRepo.Tag(1, 1), repos[i]),
                        plugin,
                        preparedSetupData.permissions,
                        hashHelpers(preparedSetupData.helpers)
                    )
                    )
                )
            });
        }

        SPP.Stage[] memory stages = new SPP.Stage[](2);
        SPP.Plugin[] memory stage1Plugins = new SPP.Plugin[](1);
        SPP.Plugin[] memory stage2Plugins = new SPP.Plugin[](1);

        stage1Plugins[0] = SPP.Plugin({
            pluginAddress: multisigPluginAddr,
            isManual: false,
            allowedBody: multisigPluginAddr,
            proposalType: SPP.ProposalType.Approval
        });

        stage2Plugins[0] = SPP.Plugin({
            pluginAddress: tokenvotingPluginAddr,
            isManual: false,
            allowedBody: tokenvotingPluginAddr,
            proposalType: SPP.ProposalType.Approval
        });

        SPP.Stage memory stage1 = SPP.Stage({
            plugins: stage1Plugins,
            minAdvance: 10 minutes,
            maxAdvance: 20 minutes,
            voteDuration: 15 minutes,
            approvalThreshold: 1,
            vetoThreshold: 0
        });

        SPP.Stage memory stage2 = SPP.Stage({
            plugins: stage2Plugins,
            minAdvance: 10 minutes,
            maxAdvance: 20 minutes,
            voteDuration: 100 minutes,
            approvalThreshold: 1,
            vetoThreshold: 0
        });

        stages[0] = stage1;
        stages[1] = stage2;

        installActions[6] = Action({
            to: sppPluginAddress,
            value: 0,
            data: abi.encodeCall(SPP.updateStages, (stages))
        });

        Admin(adminPlugin).executeProposal(bytes("0x11"), installActions, 0);

        SPP.Stage[] memory _stages = SPP(sppPluginAddress).getStages();
        return (_stages, sppPluginAddress);
    }

    function test_creating_proposal() public {
        (SPP.Stage[] memory stages, address sppPlugin) = setupDao();

        console.log("SPP Plugin Address: %s", sppPlugin);
        console.log("Multisig Plugin Address: %s", multisigPluginAddr);
        console.log("TokenVoting Plugin Address: %s", tokenvotingPluginAddr);
        console.log("Dao Address: %s", address(dao));

        PermissionLib.MultiTargetPermission[]
        memory permissions = new PermissionLib.MultiTargetPermission[](5);

        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: sppPlugin,
            who: address(this),
            condition: PermissionLib.NO_CONDITION,
            permissionId: SPP(sppPlugin).UPDATE_METADATA_PERMISSION_ID()
        });

        // grant permission for creating proposals on the spp to the manager
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(sppPlugin),
            who: address(this),
            condition: PermissionLib.NO_CONDITION,
            permissionId: SPP(sppPlugin).CREATE_PROPOSAL_PERMISSION_ID()
        });

        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(multisigPluginAddr),
            who: address(sppPlugin),
            condition: PermissionLib.NO_CONDITION,
            permissionId: SPP(sppPlugin).CREATE_PROPOSAL_PERMISSION_ID()
        });

        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(tokenvotingPluginAddr),
            who: address(sppPlugin),
            condition: PermissionLib.NO_CONDITION,
            permissionId: SPP(sppPlugin).CREATE_PROPOSAL_PERMISSION_ID()
        });

        permissions[4] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: sppPlugin,
            who: address(this),
            condition: PermissionLib.NO_CONDITION,
            permissionId: SPP(sppPlugin).SET_TRUSTED_FORWARDER_PERMISSION_ID()
        });

        Action[] memory setPermissionActions = new Action[](1);

        setPermissionActions[0] = Action({
            to: address(dao),
            value: 0,
            data: abi.encodeCall(
                PermissionManager.applyMultiTargetPermissions,
                (permissions)
            )
        });

        Admin(adminPlugin).executeProposal(bytes("0x11"), setPermissionActions, 0);

        Action[] memory actions = _createDummyActions();

        bytes[][] memory extraParams = new bytes[][](0);

        uint256 tagBlockTimestamp = block.timestamp;

        vm.roll(block.number + 2);

        vm.recordLogs();

        uint256 proposalId = SPP(sppPlugin).createProposal(
            DUMMY_METADATA,
            actions,
            uint64(0),
            uint64(0),
            abi.encode(extraParams)
        );

        uint256 subProposalIdStage1 = SPP(sppPlugin).pluginProposalIds(
            proposalId,
            0,
            multisigPluginAddr
        );

        tagBlockTimestamp = tagBlockTimestamp + 10 minutes + 1 seconds;

        vm.warp(tagBlockTimestamp);

        Multisig(multisigPluginAddr).approve(subProposalIdStage1, true);

        vm.warp(tagBlockTimestamp + 11 minutes);

        uint256 subProposalIdStage2 = SPP(sppPluginAddress).pluginProposalIds(
            proposalId,
            1,
            tokenvotingPluginAddr
        );

        TokenVoting(tokenvotingPluginAddr).vote(
            subProposalIdStage2,
            IMajorityVoting.VoteOption.Yes,
            true
        );
    }
}