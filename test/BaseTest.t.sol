// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {Test} from "forge-std/Test.sol";

import {Users} from "./utils/Types.sol";
import {Events} from "./utils/Events.sol";
import {Target} from "./utils/Target.sol";
import {Fuzzers} from "./utils/Fuzzers.sol";
import {Constants} from "./utils/Constants.sol";
import {Assertions} from "./utils/Assertions.sol";
import {PluginA} from "./utils/dummy-plugins/PluginA.sol";
import {TrustedForwarder} from "../src/utils/TrustedForwarder.sol";
import {AlwaysTrueCondition} from "../src/utils/AlwaysTrueCondition.sol";
import {StagedProposalProcessor as SPP} from "../src/StagedProposalProcessor.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";
import {
    PluginUUPSUpgradeable
} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "forge-std/console.sol";

contract BaseTest is Assertions, Constants, Events, Fuzzers, Test {
    // variables
    Users internal users;

    // contracts
    IDAO internal dao;
    SPP internal sppPlugin;
    TrustedForwarder internal trustedForwarder;
    Target internal target;

    // helpers
    uint64 internal maxAdvance = MAX_ADVANCE;
    uint64 internal minAdvance = MIN_ADVANCE;
    uint64 internal voteDuration = VOTE_DURATION;

    uint16 internal approvalThreshold = 1;
    uint16 internal vetoThreshold = 1;

    SPP.ProposalType internal proposalType = SPP.ProposalType.Approval;

    PluginUUPSUpgradeable.TargetConfig internal defaultTargetConfig;

    bytes[][] internal defaultCreationParams;

    function setUp() public virtual {
        // deploy external needed contracts
        trustedForwarder = new TrustedForwarder();
        target = new Target();

        // Create users for testing.
        users.manager = _createUser("manager");
        users.alice = _createUser("Alice");
        users.bob = _createUser("Bob");
        users.unauthorized = _createUser("unauthorized");

        // set up dao and plugin
        _setupDaoAndPluginHelper();

        // label contracts
        vm.label({account: address(dao), newLabel: "DAO"});
        vm.label({account: address(sppPlugin), newLabel: "SPP"});
        vm.label({account: address(trustedForwarder), newLabel: "Executor"});
        vm.label({account: address(target), newLabel: "Target"});
    }

    function createProxyAndCall(address _logic, bytes memory _data) public returns (address) {
        return address(new ERC1967Proxy(_logic, _data));
    }

    function resetPrank(address msgSender) public {
        vm.stopPrank();
        vm.startPrank(msgSender);
    }

    // ==== HELPERS ====

    // virtual function to be override if harness spp or similar is needed
    function _setupDaoAndPluginHelper() internal virtual {
        address sppAddress = address(new SPP());
        _setUpDaoAndPlugin(sppAddress);
    }

    function _setUpDaoAndPlugin(address sppAddr) internal {
        vm.startPrank({msgSender: users.manager});

        // create DAO.
        dao = IDAO(
            createProxyAndCall(
                address(new DAO()),
                abi.encodeCall(DAO.initialize, ("", users.manager, address(0x0), ""))
            )
        );

        defaultTargetConfig.target = address(dao);
        defaultTargetConfig.operation = PluginUUPSUpgradeable.Operation.Call;

        // create SPP plugin.
        sppPlugin = SPP(
            createProxyAndCall(
                sppAddr,
                abi.encodeCall(
                    SPP.initialize,
                    (
                        dao,
                        address(trustedForwarder),
                        new SPP.Stage[](0),
                        DUMMY_METADATA,
                        defaultTargetConfig
                    )
                )
            )
        );

        // grant permissions
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](4);

        // grant update stage permission on SPP plugin to the DAO
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(sppPlugin),
            who: users.manager,
            condition: PermissionLib.NO_CONDITION,
            permissionId: sppPlugin.UPDATE_STAGES_PERMISSION_ID()
        });

        // grant execute permission on the dao to the SPP plugin
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(dao),
            who: address(sppPlugin),
            condition: PermissionLib.NO_CONDITION,
            permissionId: DAO(payable(address(dao))).EXECUTE_PERMISSION_ID()
        });

        // grant update metadata permission on SPP plugin to the manager
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(sppPlugin),
            who: users.manager,
            condition: PermissionLib.NO_CONDITION,
            permissionId: sppPlugin.UPDATE_METADATA_PERMISSION_ID()
        });

        // grant permission for creating proposals on the spp to the manager
        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(sppPlugin),
            who: users.manager,
            condition: PermissionLib.NO_CONDITION,
            permissionId: sppPlugin.CREATE_PROPOSAL_PERMISSION_ID()
        });

        DAO(payable(address(dao))).applyMultiTargetPermissions(permissions);
    }

    function _createUser(string memory name) internal returns (address payable) {
        address payable user = payable(makeAddr(name));
        return user;
    }

    function _createDummyStages(
        uint256 _stageCount,
        bool _plugin1Manual,
        bool _plugin2Manual,
        bool _plugin3Manual
    ) internal returns (SPP.Stage[] memory stages) {
        address _plugin1 = address(new PluginA(address(trustedForwarder)));
        address _plugin2 = address(new PluginA(address(trustedForwarder)));
        address _plugin3 = address(new PluginA(address(trustedForwarder)));

        SPP.Plugin[] memory _plugins1 = new SPP.Plugin[](2);
        _plugins1[0] = _createPluginStruct(_plugin1, _plugin1Manual);
        _plugins1[1] = _createPluginStruct(_plugin2, _plugin2Manual);

        SPP.Plugin[] memory _plugins2 = new SPP.Plugin[](1);
        _plugins2[0] = _createPluginStruct(_plugin3, _plugin3Manual);

        stages = new SPP.Stage[](_stageCount);
        for (uint i; i < _stageCount; i++) {
            if (i == 0) stages[i] = _createStageStruct(_plugins1);
            else stages[i] = _createStageStruct(_plugins2);
        }
    }

    function _createPluginStruct(
        address _pluginAddr,
        bool _isManual
    ) internal view virtual returns (SPP.Plugin memory plugin) {
        plugin = SPP.Plugin({
            pluginAddress: _pluginAddr,
            isManual: _isManual,
            allowedBody: _pluginAddr,
            proposalType: proposalType
        });
    }

    function _createStageStruct(
        SPP.Plugin[] memory _plugins
    ) internal view virtual returns (SPP.Stage memory stage) {
        stage = SPP.Stage({
            plugins: _plugins,
            maxAdvance: maxAdvance,
            minAdvance: minAdvance,
            voteDuration: voteDuration,
            approvalThreshold: approvalThreshold,
            vetoThreshold: vetoThreshold
        });
    }

    function _createDummyActions() internal view returns (IDAO.Action[] memory actions) {
        // action 1
        actions = new IDAO.Action[](2);
        actions[0].to = address(target);
        actions[0].value = 0;
        actions[0].data = abi.encodeCall(target.setValue, TARGET_VALUE);

        // action 2
        actions[1].to = address(target);
        actions[1].value = 0;
        actions[1].data = abi.encodeCall(target.setAddress, TARGET_ADDRESS);
    }

    function _configureStagesAndCreateDummyProposal(
        bytes memory _metadata
    ) internal returns (uint256 proposalId) {
        // setup stages
        SPP.Stage[] memory stages = _createDummyStages(2, false, false, false);
        sppPlugin.updateStages(stages);

        // create proposal
        IDAO.Action[] memory actions = _createDummyActions();
        proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: _metadata,
            _startDate: START_DATE,
            _data: defaultCreationParams
        });
    }

    function _executeStageProposals(uint256 _stage) internal {
        // execute proposals on first stage
        SPP.Stage[] memory stages = sppPlugin.getStages();

        for (uint256 i; i < stages[_stage].plugins.length; i++) {
            PluginA(stages[_stage].plugins[i].pluginAddress).execute({_proposalId: 0});
        }
    }
}
