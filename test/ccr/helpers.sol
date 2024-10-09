//// SPDX-License-Identifier: UNLICENSED
//pragma solidity ^0.8.8;
//
//import {Test, Vm} from "forge-std/Test.sol";
//
//import {StagedProposalProcessor as SPP} from "../../src/StagedProposalProcessor.sol";
//import {PluginSetupProcessor} from "@aragon/osx-new/framework/plugin/setup/PluginSetupProcessor.sol";
//import {PluginRepo} from "@aragon/osx-new/framework/plugin/repo/PluginRepo.sol";
//import {PluginRepoFactory} from "@aragon/osx-new/framework/plugin/repo/PluginRepoFactory.sol";
//import {
//IERC20Upgradeable
//} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
//
//import {DAOFactory} from "@aragon/osx-new/framework/dao/DAOFactory.sol";
//
//import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
//import {DAO} from "@aragon/osx-new/core/dao/DAO.sol";
//
//import {
//PluginUUPSUpgradeable
//} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";
//import {DAORegistry} from "@aragon/osx-new/framework/dao/DAORegistry.sol";
//
////Multisig imports
//import {Multisig} from "@aragon/multisig/Multisig.sol";
//import {MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";
//
////Admin imports
//import {Admin} from "@aragon/admin/Admin.sol";
//import {AdminSetup} from "@aragon/admin/AdminSetup.sol";
//
////TokenVoting imports
//import {TokenVoting} from "@aragon/token-voting/TokenVoting.sol";
//import {TokenVotingSetup} from "@aragon/token-voting/TokenVotingSetup.sol";
//import {GovernanceERC20} from "@aragon/token-voting/ERC20/governance/GovernanceERC20.sol";
//
//import {
//    GovernanceWrappedERC20
//} from "@aragon/token-voting/ERC20/governance/GovernanceWrappedERC20.sol";
//
//import {
//PluginSetupRef,
//hashHelpers
//} from "@aragon/osx-new/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
//import {StagedProposalProcessorSetup} from "../../src/StagedProposalProcessorSetup.sol";
//
//import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
//import {
//PluginUUPSUpgradeable
//} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";
//
//import {PluginRepoFactory as IPluginRepoFactory} from "@aragon/osx-new/framework/plugin/repo/PluginRepoFactory.sol";
//import "forge-std/console.sol";
//
//contract Helper is Test {
//
//    IPluginRepoFactory public pluginRepoFactory;
//    PluginSetupProcessor public psp;
//
//    // contracts
//    IDAO internal dao;
//
//    uint256 internal deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
//    address internal immutable deployer = vm.addr(deployerPrivateKey);
//
//    PluginRepo public multisigPluginRepo;
//    PluginRepo public tokenVotingRepo;
//    PluginRepo public sppRepo;
//    PluginRepo public adminRepo;
//
//    address public adminPl;
//
//    error LogNotFound(bytes32 topic);
//
//    function createPluginRepos() public {
//        multisigPluginRepo = pluginRepoFactory.createPluginRepo("multisiggio", address(this));
//        MultisigSetup multisigSetup = new MultisigSetup();
//        multisigPluginRepo.createVersion(1, address(multisigSetup), "dummy", "dummy");
//
//        // create tokenvoting repo
//        tokenVotingRepo = pluginRepoFactory.createPluginRepo("tokenvotinggio", address(this));
//        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings({
//            receivers: new address[](0),
//            amounts: new uint256[](0)
//        });
//
//        TokenVotingSetup tokenVotingSetup = new TokenVotingSetup(
//            new GovernanceERC20(IDAO(address(0)), "nn", "nn", mintSettings),
//            new GovernanceWrappedERC20(IERC20Upgradeable(address(0)), "nn", "nn")
//        );
//
//        tokenVotingRepo.createVersion(1, address(tokenVotingSetup), "dummy", "dummy");
//
//        // create SPP repo
//        sppRepo = pluginRepoFactory.createPluginRepo("sppgio", address(this));
//        StagedProposalProcessorSetup sppSetup = new StagedProposalProcessorSetup();
//        sppRepo.createVersion(1, address(sppSetup), "dummy", "dummy");
//
//        // create AdminRepo
//        adminRepo = pluginRepoFactory.createPluginRepo("admingio", address(this));
//        AdminSetup adminSetup = new AdminSetup();
//        adminRepo.createVersion(1, address(adminSetup), "dummy", "dummy");
//    }
//
//    function createDAOWithAdminPlugin(
//        DAORegistry _daoRegistry,
//        PluginSetupProcessor _psp
//    ) public returns (IDAO, address) {
//        DAOFactory daoFactory = new DAOFactory(_daoRegistry, _psp);
//
//        DAOFactory.DAOSettings memory daoSettings = DAOFactory.DAOSettings({
//            trustedForwarder: address(0),
//            daoURI: "nothing",
//            subdomain: "awesome",
//            metadata: bytes("0x11")
//        });
//
//        DAOFactory.PluginSettings[] memory pluginSettings = new DAOFactory.PluginSettings[](1);
//        pluginSettings[0] = DAOFactory.PluginSettings({
//            pluginSetupRef: PluginSetupRef(PluginRepo.Tag(1, 1), PluginRepo(adminRepo)),
//            data: abi.encode(address(this))
//        });
//
//        // daofactory calls daoRegistry which is already deployed, so this daoFactory needs permission on it.
//        address daoRegistry = vm.parseJsonAddress(getOsxConfigs(), ".['v1.3.0'].DAORegistryProxy.address");
//        address managementDAO = vm.parseJsonAddress(getOsxConfigs(), ".['v1.3.0'].ManagementDAOProxy.address");
//        vm.prank(address(managementDAO));
//        DAO(payable(managementDAO)).grant(daoRegistry, address(daoFactory), keccak256("REGISTER_DAO_PERMISSION"));
//
//        vm.recordLogs();

//        dao = IDAO(address(daoFactory.createDao(daoSettings, pluginSettings)));
//
//        Vm.Log[] memory logs = vm.getRecordedLogs();
//        // InstallationApplied
//        Vm.Log memory log = findLog(
//            logs,
//            bytes32(0x74e616c7264536b98a5ec234d051ae6ce1305bf05c85f9ddc112364440ccf129)
//        );
//
//        return (dao, address(uint160(uint256(log.topics[2]))));
//    }
//
//    function getPSPPrepareInstallationAction(
//        PluginSetupProcessor.PrepareInstallationParams memory _params
//    ) public view returns (Action memory) {
//        return Action({
//            to: address(psp),
//            value: 0,
//            data: abi.encodeCall(PluginSetupProcessor.prepareInstallation, (address(dao), _params))
//        });
//    }
//
//    function createProxyAndCall(address _logic, bytes memory _data) public returns (address) {
//        return address(new ERC1967Proxy(_logic, _data));
//    }
//
//    function getOsxConfigs() public view returns (string memory) {
//        string memory osxConfigsPath = string.concat(
//            vm.projectRoot(),
//            "/node_modules/@aragon/osx-commons-configs/dist/deployments/json/mainnet.json"
//        );
//        return vm.readFile(osxConfigsPath);
//    }
//
//    function findLog(Vm.Log[] memory logs, bytes32 topic) public pure returns (Vm.Log memory) {
//        for (uint256 i = 0; i < logs.length; i++) {
//            if (logs[i].topics[0] == topic) {
//                return logs[i];
//            }
//        }
//        revert LogNotFound(topic);
//    }
//}