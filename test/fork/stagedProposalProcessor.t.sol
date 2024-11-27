// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ForkBaseTest} from "./ForkBaseTest.t.sol";
import {StagedProposalProcessor as SPP} from "../../src/StagedProposalProcessor.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Permissions} from "../../src/libraries/Permissions.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {
    RuledCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/extensions/RuledCondition.sol";

import {console} from "forge-std/console.sol";

contract StagedProposalProcessor_ForkTest is ForkBaseTest {
    DAO internal dao;
    address internal adminPlugin;
    address internal multisigPlugin;
    SPP internal sppPlugin;

    uint256 proposalId;

    uint64 minAdvance = 30;
    uint64 maxAdvance = 100;

    function setUp() public override {
        super.setUp();

        _configureDummyDaoAndInstallSPP();

        // move blocks because some proposals can not be created on the same block the plugin is installed
        vm.roll(block.number + 4);
    }

    function test_proposalFlow() public {
        // create proposal
        _test_createProposal();

        // advance to stage 1
        _test_advanceToStageX(1);

        // advance to stage 2
        _test_advanceToStageX(2);

        // execute proposal
        _test_advanceLastStage();
    }

    function _test_createProposal() public {
        uint64 startDate = uint64(block.timestamp);
        bytes memory testMetadata = "test proposal metadata";
        Action[] memory actions = new Action[](1);
        actions[0].to = address(target);
        actions[0].value = 0;
        actions[0].data = abi.encodeCall(target.setValue, TARGET_VALUE);

        // check proposal creation event was emitted

        vm.expectEmit({
            checkTopic1: false,
            checkTopic2: true,
            checkTopic3: true,
            checkData: true,
            emitter: address(sppPlugin)
        });
        emit ProposalCreated({
            proposalId: 0,
            creator: deployer,
            startDate: startDate,
            endDate: 0,
            metadata: testMetadata,
            actions: actions,
            allowFailureMap: 0
        });

        // check sub proposal creation event was emitted

        // todo check why this log is failing
        // vm.expectEmit({
        //     checkTopic1: false,
        //     checkTopic2: false,
        //     checkTopic3: false,
        //     checkData: false,
        //     emitter: address(sppPlugin)
        // });

        // emit SPP.SubProposalCreated({
        //     proposalId: 0,
        //     stageId: 0,
        //     body: adminPlugin,
        //     bodyProposalId: 0
        // });

        proposalId = sppPlugin.createProposal({
            _metadata: testMetadata,
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: startDate,
            _proposalParams: new bytes[][](0)
        });

        // check proposal
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        assertEq(
            proposal,
            SPP.Proposal({
                allowFailureMap: 0,
                lastStageTransition: startDate,
                actions: actions,
                stageConfigIndex: 1,
                currentStage: 0,
                executed: false,
                canceled: false,
                targetConfig: IPlugin.TargetConfig({
                    target: address(dao),
                    operation: IPlugin.Operation.Call
                }),
                creator: deployer
            }),
            "proposal"
        );

        // check subproposal id was stored
        assertNotEq(sppPlugin.getBodyProposalId(proposalId, 0, adminPlugin), 0, "subproposalId");
    }

    function _test_advanceToStageX(uint16 _stageId) public {
        // check proposal can't advance due to min advance time

        assertFalse(sppPlugin.canProposalAdvance(proposalId));

        // move timestamp
        vm.warp(block.timestamp + minAdvance);

        // check proposal can advance
        assertTrue(sppPlugin.canProposalAdvance(proposalId));

        // check proposal advanced event emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalAdvanced(proposalId, _stageId);

        sppPlugin.advanceProposal(proposalId);

        // check proposal advanced
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        assertEq(proposal.currentStage, _stageId, "currentStage");

        // stage 1 has no bodies so no subroposal was created successfully
        if (_stageId != 1) {
            assertNotEq(
                sppPlugin.getBodyProposalId(proposalId, _stageId, multisigPlugin),
                0,
                "subproposalId"
            );

            assertNotEq(
                sppPlugin.getBodyProposalId(proposalId, _stageId, multisigPlugin),
                type(uint256).max,
                "subproposalId"
            );
        }
    }

    function _test_advanceLastStage() public {
        // check proposal can't advance

        assertFalse(sppPlugin.canProposalAdvance(proposalId));

        // approve subproposal so proposal can advance

        uint256 subproposalId = sppPlugin.getBodyProposalId(proposalId, 2, multisigPlugin);

        resetPrank(address(1));
        multisigPlugin.call(abi.encodeWithSignature("approve(uint256,bool)", subproposalId, false));

        resetPrank(address(2));
        // should report results
        // emit ProposalResultReported event

        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, 2, multisigPlugin);
        multisigPlugin.call(abi.encodeWithSignature("approve(uint256,bool)", subproposalId, true));

        resetPrank(deployer);

        // check proposal is not advanceable due to min advance time
        assertFalse(sppPlugin.canProposalAdvance(proposalId));

        // move timestamp
        vm.warp(block.timestamp + minAdvance);

        assertTrue(sppPlugin.canProposalAdvance(proposalId));

        // check proposal executed event emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalExecuted(proposalId);

        sppPlugin.advanceProposal(proposalId);

        // check proposal executed
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        assertTrue(proposal.executed, "executed");

        // todo check actions were executed
    }

    function _configureDummyDaoAndInstallSPP() internal {
        // get new dao
        DAOFactory.InstalledPlugin[] memory _installedPlugins;
        (dao, _installedPlugins) = _createDummyDaoAdmin();

        adminPlugin = _installedPlugins[0].plugin;

        // install multisig and revoke execute permission
        multisigPlugin = _installMultisigAndRevokeRoot(dao);

        SPP.Stage[] memory stages = new SPP.Stage[](3);
        SPP.Body[] memory bodiesStage0 = new SPP.Body[](1);
        bodiesStage0[0] = SPP.Body({
            addr: adminPlugin,
            isManual: false,
            tryAdvance: true,
            resultType: SPP.ResultType.Approval
        });
        stages[0] = SPP.Stage({
            bodies: bodiesStage0,
            maxAdvance: maxAdvance,
            minAdvance: minAdvance,
            voteDuration: 10,
            approvalThreshold: 1,
            vetoThreshold: 0,
            cancelable: false,
            editable: false
        });
        stages[1] = SPP.Stage({
            bodies: new SPP.Body[](0),
            maxAdvance: maxAdvance,
            minAdvance: minAdvance,
            voteDuration: 10,
            approvalThreshold: 0,
            vetoThreshold: 0,
            cancelable: true,
            editable: true
        });
        SPP.Body[] memory bodiesStage2 = new SPP.Body[](1);
        bodiesStage2[0] = SPP.Body({
            addr: multisigPlugin,
            isManual: false,
            tryAdvance: true,
            resultType: SPP.ResultType.Approval
        });
        stages[2] = SPP.Stage({
            bodies: bodiesStage2,
            maxAdvance: maxAdvance,
            minAdvance: minAdvance,
            voteDuration: 10,
            approvalThreshold: 1,
            vetoThreshold: 0,
            cancelable: false,
            editable: false
        });
        RuledCondition.Rule[] memory rules = new RuledCondition.Rule[](0);
        bytes memory sppData = abi.encode(
            "dummy spp metadata",
            stages,
            rules,
            IPlugin.TargetConfig({target: address(0), operation: IPlugin.Operation.Call})
        );

        // install spp
        (address sppPluginAdr, ) = _installSPP(dao, sppData);
        sppPlugin = SPP(sppPluginAdr);

        resetPrank(address(dao));

        // grant proposal creation permission on the admin plugin to the spp
        dao.grant(adminPlugin, address(sppPlugin), Permissions.CREATE_PROPOSAL_PERMISSION_ID);
        // grant also execute permission because admin plugin automatically executes
        dao.grant(adminPlugin, address(sppPlugin), Permissions.EXECUTE_PROPOSAL_PERMISSION_ID);

        // grant proposal creation permission on the multisig plugin to the spp
        dao.grant(multisigPlugin, address(sppPlugin), Permissions.CREATE_PROPOSAL_PERMISSION_ID);

        resetPrank(deployer);
    }
}

interface IMultisig {
    struct ProposalParameters {
        uint16 minApprovals;
        uint64 snapshotBlock;
        uint64 startDate;
        uint64 endDate;
    }

    function approve(uint256 _proposalId, bool _tryExecution) external;

    function canApprove(uint256 _proposalId, address _account) external view returns (bool);

    function getProposal(
        uint256 _proposalId
    )
        external
        view
        returns (
            bool executed,
            uint16 approvals,
            ProposalParameters memory parameters,
            Action[] memory actions,
            uint256 allowFailureMap,
            IPlugin.TargetConfig memory targetConfig
        );

    function lastMultisigSettingsChange() external view returns (uint64);
}
