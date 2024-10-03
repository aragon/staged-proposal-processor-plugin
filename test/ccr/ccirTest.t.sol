

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {Test, Vm} from "forge-std/Test.sol";

import {Target} from "../utils/Target.sol";
import {StagedProposalProcessor as SPP} from "../../src/StagedProposalProcessor.sol";
import {PluginRepo} from "@aragon/osx-new/framework/plugin/repo/PluginRepo.sol";
import {
PluginSetupProcessor
} from "@aragon/osx-new/framework/plugin/setup/PluginSetupProcessor.sol";
import {IPluginRepoFactory} from "./IPluginRepoFactory.sol";
import {
IERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";

import {DAO} from "@aragon/osx-new/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {
PluginUUPSUpgradeable
} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";

import {Multisig} from "@aragon/multisig/Multisig.sol";
import {DAORegistry} from "@aragon/osx-new/framework/dao/DAORegistry.sol";
import {PermissionManager} from "@aragon/osx-new/core/permission/PermissionManager.sol";

import {Admin} from "@aragon/admin/Admin.sol";

import {TokenVoting} from "@aragon/token-voting/TokenVoting.sol";
import {MajorityVotingBase} from "@aragon/token-voting/MajorityVotingBase.sol";

import {TokenVotingSetup} from "@aragon/token-voting/TokenVotingSetup.sol";

import {GovernanceERC20} from "@aragon/token-voting/ERC20/governance/GovernanceERC20.sol";
import {
GovernanceWrappedERC20
} from "@aragon/token-voting/ERC20/governance/GovernanceWrappedERC20.sol";

import {
PluginSetupRef,
hashHelpers
} from "@aragon/osx-new/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

import {
PluginUUPSUpgradeable
} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";

import "forge-std/console.sol";
import {Helper} from "./helper.sol";

contract GiorgiFlow is Test, Helper {
    function setUp() public virtual {
        pluginRepoFactory = IPluginRepoFactory(
            vm.parseJsonAddress(getOsxConfigs(), ".['v1.3.0'].PluginRepoFactory.address")
        );

        psp = PluginSetupProcessor(
            vm.parseJsonAddress(getOsxConfigs(), ".['v1.3.0'].PluginSetupProcessor.address")
        );

        DAORegistry daoRegistry = DAORegistry(
            vm.parseJsonAddress(getOsxConfigs(), ".['v1.3.0'].DAORegistryProxy.address")
        );

        // create spp, tokenvoting, multisig, admin repos
        createPluginRepos();

        (dao, adminPl) = createDAOWithAdminPlugin(daoRegistry, psp);
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
            .TargetConfig({target: address(dao), operation: PluginUUPSUpgradeable.Operation.Call});

        return
            PluginSetupProcessor.PrepareInstallationParams(
            PluginSetupRef(PluginRepo.Tag(1, 1), PluginRepo(multisigPluginRepo)),
            abi.encode(members, settings, targetConfig)
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
            minDuration: 100 minutes,
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
            .TargetConfig({target: address(dao), operation: PluginUUPSUpgradeable.Operation.Call});

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
            .TargetConfig({target: address(dao), operation: PluginUUPSUpgradeable.Operation.Call});

        SPP.Stage[] memory stages = new SPP.Stage[](0);

        return
            PluginSetupProcessor.PrepareInstallationParams(
            PluginSetupRef(PluginRepo.Tag(1, 1), PluginRepo(sppRepo)),
            abi.encode(stages, bytes("0x11"), targetConfig)
        );
    }

    struct Action {
        address to;
        uint256 value;
        bytes data;
    }

    event Executed(
        address indexed actor,
        bytes32 callId,
        Action[] actions,
        uint256 allowFailureMap,
        uint256 failureMap,
        bytes[] execResults
    );

    function test_fuckMe() public {
        IDAO.Action[] memory prepareInstallActions = new IDAO.Action[](3);
        prepareInstallActions[0] = getPSPPrepareInstallationAction(
            getMultisigPrepareInstallationParams()
        );
        prepareInstallActions[1] = getPSPPrepareInstallationAction(
            getTokenVotingPrepareInstallationParams()
        );
        prepareInstallActions[2] = getPSPPrepareInstallationAction(
            getSPPPrepareInstallationParams()
        );

        vm.recordLogs();

        Admin(adminPl).executeProposal(bytes("0x11"), prepareInstallActions, 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        // InstallationApplied
        Vm.Log memory log = findLog(logs, Executed.selector);

        (, , , , bytes[] memory results) = abi.decode(
            log.data,
            (bytes32, IDAO.Action[], uint256, uint256, bytes[])
        );
        console.log(results.length);

        PluginRepo[] memory repos = new PluginRepo[](3);
        repos[0] = multisigPluginRepo;
        repos[1] = tokenVotingRepo;
        repos[2] = sppRepo;

        IDAO.Action[] memory installActions = new IDAO.Action[](7);

        installActions[0] = IDAO.Action({
            to: address(dao),
            value: 0,
            data: abi.encodeCall(PermissionManager.setApplyTargetMethodGrantee, (address(psp)))
        });

        installActions[1] = IDAO.Action({
            to: address(dao),
            value: 0,
            data: abi.encodeCall(
                PermissionManager.grant,
                (address(dao), address(psp), keccak256("APPLY_TARGET_PERMISSION"))
            )
        });

        installActions[5] = IDAO.Action({
            to: address(dao),
            value: 0,
            data: abi.encodeCall(
                PermissionManager.revoke,
                (address(dao), address(psp), keccak256("APPLY_TARGET_PERMISSION"))
            )
        });

        address sppPluginAddress;
        address tokenvotingPluginAddr;
        address multisigPluginAddr;

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

            installActions[i + 2] = IDAO.Action({
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
            voteDuration: 15 minutes,
            approvalThreshold: 1,
            vetoThreshold: 0
        });

        stages[0] = stage1;
        stages[1] = stage2;

        installActions[6] = IDAO.Action({
            to: sppPluginAddress,
            value: 0,
            data: abi.encodeCall(SPP.updateStages, (stages))
        });

        Admin(adminPl).executeProposal(bytes("0x11"), installActions, 0);

        SPP.Stage[] memory _stages = SPP(sppPluginAddress).getStages();
        console.log(_stages.length);
    }
}