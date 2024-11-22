// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";

import {Users} from "./utils/Types.sol";
import {Events} from "./utils/Events.sol";
import {Target} from "./utils/Target.sol";
import {Fuzzers} from "./utils/Fuzzers.sol";
import {Constants} from "./utils/Constants.sol";
import {Assertions} from "./utils/Assertions.sol";
import {Permissions} from "../src/libraries/Permissions.sol";
import {PluginA} from "./utils/dummy-plugins/PluginA/PluginA.sol";
import {TrustedForwarder} from "../src/utils/TrustedForwarder.sol";
import {StagedProposalProcessor as SPP} from "../src/StagedProposalProcessor.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract BaseTest is Assertions, Constants, Events, Fuzzers, Test {
    // variables
    Users internal users;
    address allowedBody;

    // contracts
    IDAO internal dao;
    SPP internal sppPlugin;
    TrustedForwarder internal trustedForwarder;
    Target internal target;

    // helpers
    uint64 internal maxAdvance = MAX_ADVANCE;
    uint64 internal minAdvance = MIN_ADVANCE;
    uint64 internal voteDuration = VOTE_DURATION;
    bool internal cancellable;
    bool internal editable;

    uint16 internal approvalThreshold = 1;
    uint16 internal vetoThreshold = 1;

    SPP.ResultType internal resultType = SPP.ResultType.Approval;

    IPlugin.TargetConfig internal defaultTargetConfig;

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
        allowedBody = users.manager;

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
        defaultTargetConfig.operation = IPlugin.Operation.Call;

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
            memory permissions = new PermissionLib.MultiTargetPermission[](8);

        // grant update stage permission on SPP plugin to the DAO
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(sppPlugin),
            who: users.manager,
            condition: PermissionLib.NO_CONDITION,
            permissionId: Permissions.UPDATE_STAGES_PERMISSION_ID
        });

        // grant execute permission on the dao to the SPP plugin
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(dao),
            who: address(sppPlugin),
            condition: PermissionLib.NO_CONDITION,
            permissionId: Permissions.EXECUTE_PERMISSION_ID
        });

        // grant update metadata permission on SPP plugin to the manager
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(sppPlugin),
            who: users.manager,
            condition: PermissionLib.NO_CONDITION,
            permissionId: Permissions.SET_METADATA_PERMISSION_ID
        });

        // grant permission for creating proposals on the spp to the manager
        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(sppPlugin),
            who: users.manager,
            condition: PermissionLib.NO_CONDITION,
            permissionId: Permissions.CREATE_PROPOSAL_PERMISSION_ID
        });

        // grant permission for execute proposals on the spp to the manager
        permissions[4] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(sppPlugin),
            who: users.manager,
            condition: PermissionLib.NO_CONDITION,
            permissionId: Permissions.EXECUTE_PERMISSION_ID
        });

        // grant permission for execute proposals on the spp to the manager
        permissions[5] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(sppPlugin),
            who: users.manager,
            condition: PermissionLib.NO_CONDITION,
            permissionId: Permissions.ADVANCE_PERMISSION_ID
        });

        // grant cancel permission on the spp to the manager
        permissions[6] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(sppPlugin),
            who: users.manager,
            condition: PermissionLib.NO_CONDITION,
            permissionId: Permissions.CANCEL_PERMISSION_ID
        });

        // grant edit permission on the spp to the manager
        permissions[7] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: address(sppPlugin),
            who: users.manager,
            condition: PermissionLib.NO_CONDITION,
            permissionId: Permissions.EDIT_PERMISSION_ID
        });

        DAO(payable(address(dao))).applyMultiTargetPermissions(permissions);
    }

    function _createUser(string memory name) internal returns (address payable) {
        address payable user = payable(makeAddr(name));
        return user;
    }

    function _createDummyStages(
        uint256 _stageCount,
        bool _body1Manual,
        bool _body2Manual,
        bool _body3Manual
    ) internal returns (SPP.Stage[] memory stages) {
        defaultTargetConfig.target = address(trustedForwarder);
        defaultTargetConfig.operation = IPlugin.Operation.Call;
        address body1Addr = address(new PluginA(defaultTargetConfig));
        address body2Addr = address(new PluginA(defaultTargetConfig));
        address body3Addr = address(new PluginA(defaultTargetConfig));

        SPP.Body[] memory stage1Bodies = new SPP.Body[](2);
        stage1Bodies[0] = _createBodyStruct(body1Addr, _body1Manual);
        stage1Bodies[1] = _createBodyStruct(body2Addr, _body2Manual);

        SPP.Body[] memory stage2Bodies = new SPP.Body[](1);
        stage2Bodies[0] = _createBodyStruct(body3Addr, _body3Manual);

        stages = new SPP.Stage[](_stageCount);
        for (uint i; i < _stageCount; i++) {
            if (i == 0) stages[i] = _createStageStruct(stage1Bodies);
            else stages[i] = _createStageStruct(stage2Bodies);
        }
    }

    function _createCustomStages(
        uint256 _stageCount,
        bool _body1Manual,
        bool _body2Manual,
        bool _body3Manual,
        address _executor,
        IPlugin.Operation _operation,
        bool _tryAdvance
    ) internal returns (SPP.Stage[] memory stages) {
        IPlugin.TargetConfig memory targetConfig;
        targetConfig.target = address(_executor);
        targetConfig.operation = _operation;

        address body1Addr = address(new PluginA(targetConfig));
        address body2Addr = address(new PluginA(targetConfig));
        address body3Addr = address(new PluginA(targetConfig));

        SPP.Body[] memory _body1 = new SPP.Body[](2);
        _body1[0] = _createCustomBodyStruct(body1Addr, _body1Manual, _tryAdvance);
        _body1[1] = _createCustomBodyStruct(body2Addr, _body2Manual, _tryAdvance);

        SPP.Body[] memory _body2 = new SPP.Body[](1);
        _body2[0] = _createCustomBodyStruct(body3Addr, _body3Manual, _tryAdvance);

        stages = new SPP.Stage[](_stageCount);
        for (uint i; i < _stageCount; i++) {
            if (i == 0) stages[i] = _createStageStruct(_body1);
            else stages[i] = _createStageStruct(_body2);
        }
    }

    function _createBodyStruct(
        address _bodyAddr,
        bool _isManual
    ) internal view virtual returns (SPP.Body memory body) {
        body = SPP.Body({
            addr: _bodyAddr,
            isManual: _isManual,
            tryAdvance: true,
            resultType: resultType
        });
    }

    function _createCustomBodyStruct(
        address _bodyAddr,
        bool _isManual,
        bool _tryAdvance
    ) internal view virtual returns (SPP.Body memory body) {
        body = SPP.Body({
            addr: _bodyAddr,
            isManual: _isManual,
            tryAdvance: _tryAdvance,
            resultType: resultType
        });
    }

    function _createStageStruct(
        SPP.Body[] memory _bodies
    ) internal view virtual returns (SPP.Stage memory stage) {
        // console.log("cancellable", cancellable);
        stage = SPP.Stage({
            bodies: _bodies,
            maxAdvance: maxAdvance,
            minAdvance: minAdvance,
            voteDuration: voteDuration,
            approvalThreshold: approvalThreshold,
            vetoThreshold: vetoThreshold,
            cancelable: cancellable,
            editable: editable
        });
    }

    function _createDummyActions() internal view returns (Action[] memory actions) {
        // action 1
        actions = new Action[](2);
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
        Action[] memory actions = _createDummyActions();
        proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: _metadata,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });
    }

    function _executeStageProposals(uint256 _stage) internal {
        // execute proposals on first stage
        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());

        for (uint256 i; i < stages[_stage].bodies.length; i++) {
            PluginA(stages[_stage].bodies[i].addr).execute({_proposalId: 0});
        }
    }

    function _getSetupPermissions() internal pure returns (bytes32[] memory permissionList) {
        permissionList = new bytes32[](10);

        permissionList[0] = Permissions.UPDATE_STAGES_PERMISSION_ID;
        permissionList[1] = Permissions.EXECUTE_PERMISSION_ID;
        permissionList[2] = Permissions.SET_TRUSTED_FORWARDER_PERMISSION_ID;
        permissionList[3] = Permissions.SET_TARGET_CONFIG_PERMISSION_ID;
        permissionList[4] = Permissions.SET_METADATA_PERMISSION_ID;
        permissionList[5] = Permissions.CREATE_PROPOSAL_PERMISSION_ID;
        permissionList[6] = Permissions.CANCEL_PERMISSION_ID;
        permissionList[7] = Permissions.ADVANCE_PERMISSION_ID;
        permissionList[8] = Permissions.EXECUTE_PERMISSION_ID;
        permissionList[9] = Permissions.UPDATE_RULES_PERMISSION_ID;
    }

    function _encodeStateBitmap(SPP.ProposalState _proposalState) internal pure returns (bytes32) {
        return bytes32(1 << uint8(_proposalState));
    }
}
