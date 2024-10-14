// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import  "forge-std/Script.sol";
import {DAORegistry} from "@aragon/osx-new/framework/dao/DAORegistry.sol";
import {DAOFactory} from "@aragon/osx-new/framework/dao/DAOFactory.sol";
import {PluginRepoFactory as IPluginRepoFactory} from "@aragon/osx-new/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginSetupProcessor} from "@aragon/osx-new/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginRepo} from "@aragon/osx-new/framework/plugin/repo/PluginRepo.sol";
import {StagedProposalProcessorSetup} from "../src/StagedProposalProcessorSetup.sol";
import {TokenVotingSetup} from "@aragon/token-voting/TokenVotingSetup.sol";
import {MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";
import {AdminSetup} from "@aragon/admin/AdminSetup.sol";


import {Multisig} from "@aragon/multisig/Multisig.sol";
import {Admin} from "@aragon/admin/Admin.sol";
import {TokenVoting} from "@aragon/token-voting/TokenVoting.sol";

import {DAO} from "@aragon/osx-new/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

import {
    GovernanceWrappedERC20
} from "@aragon/token-voting/ERC20/governance/GovernanceWrappedERC20.sol";

import {
    IERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import {
    PluginSetupRef,
    hashHelpers
} from "@aragon/osx-new/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

import {
PluginUUPSUpgradeable
} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";

import {GovernanceERC20} from "@aragon/token-voting/ERC20/governance/GovernanceERC20.sol";
import {TrustedForwarder} from "../src/utils/TrustedForwarder.sol";
import {Action, IExecutor} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {MajorityVotingBase} from "@aragon/token-voting/MajorityVotingBase.sol";
import {StagedProposalProcessor as SPP} from "../src/StagedProposalProcessor.sol";

contract SppInt is Script {
    DAOFactory public daoFactory;
    IPluginRepoFactory public pluginRepoFactory = IPluginRepoFactory(0x07f49c49Ce2A99CF7C28F66673d406386BDD8Ff4);

    PluginSetupProcessor public psp = PluginSetupProcessor(0xC24188a73dc09aA7C721f96Ad8857B469C01dC9f);
    DAORegistry public daoRegistry = DAORegistry(0x308a1DC5020c4B5d992F5543a7236c465997fecB);

    PluginRepo public multisigPluginRepo;
    PluginRepo public tokenVotingRepo;
    PluginRepo public sppRepo;
    PluginRepo public adminRepo;

    IDAO public dao;

    address public sppPluginAddress;
    address public tokenvotingPluginAddr;
    address public multisigPluginAddr;
    address public adminPlugin;

    TrustedForwarder public trustedForwarder;

    function setupPluginRepo() internal {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        vm.startBroadcast(privateKey);

        trustedForwarder = new TrustedForwarder();

        // create admin repo
        adminRepo = pluginRepoFactory.createPluginRepo("admingio", deployer);
        AdminSetup adminSetup = new AdminSetup();
        adminRepo.createVersion(1, address(adminSetup), "dummy", "dummy");
//
//        // create spp repo
        sppRepo = pluginRepoFactory.createPluginRepo("sppgio", deployer);
        StagedProposalProcessorSetup sppSetup = new StagedProposalProcessorSetup();
        sppRepo.createVersion(1, address(sppSetup), "dummy", "dummy");

        // create multisig repo
        multisigPluginRepo = pluginRepoFactory.createPluginRepo("multisiggio", deployer);
        MultisigSetup multisigSetup = new MultisigSetup();
        multisigPluginRepo.createVersion(1, address(multisigSetup), "dummy", "dummy");

        // create tokenvoting repo
        tokenVotingRepo = pluginRepoFactory.createPluginRepo("tokenvotinggio", deployer);

        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings({
            receivers: new address[](0),
            amounts: new uint256[](0)
        });

        TokenVotingSetup tokenVotingSetup = new TokenVotingSetup(
            new GovernanceERC20(IDAO(address(0)), "nn", "nn", mintSettings),
            new GovernanceWrappedERC20(IERC20Upgradeable(address(0)), "nn", "nn")
        );

        tokenVotingRepo.createVersion(1, address(tokenVotingSetup), "dummy", "dummy");

        vm.stopBroadcast();
    }

    function createDaoWithAuthPlugin() internal {

        vm.startBroadcast();

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

        vm.stopBroadcast();

        address managementDAO = 0xCa834B3F404c97273f34e108029eEd776144d324;

        vm.prank(address(managementDAO));

        DAO(payable(managementDAO)).grant(address(daoRegistry), address(daoFactory), keccak256("REGISTER_DAO_PERMISSION"));

        vm.stopPrank();

        vm.startBroadcast();

        dao = IDAO(address(daoFactory.createDao(daoSettings, pluginSettings)));

        vm.stopBroadcast();
    }

    function deployPlugins() public {
        setupPluginRepo();
        createDaoWithAuthPlugin();
    }

    function preparePlugins() public {
        Action[] memory prepareInstallActions = new Action[](3);

        prepareInstallActions[0] = getPSPPrepareInstallationAction(getMultisigPrepareInstallationParams());
        prepareInstallActions[1] = getPSPPrepareInstallationAction(getTokenVotingPrepareInstallationParams());
        prepareInstallActions[2] = getPSPPrepareInstallationAction(getSPPPrepareInstallationParams());

        Admin(adminPlugin).executeProposal(bytes("0x11"), prepareInstallActions, 0);
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
}
