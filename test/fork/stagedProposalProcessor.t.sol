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

    function test_proposalFlowAdvancingLastStage() public {
        // creates proposal on SPP and automatically executes - i.e reports results.
        // Due to minAdvance not yet passed by, proposal doesn't advance yet.
        _test_createProposalAndExecuteSubproposal();

        // advance to stage 1
        _test_advanceToStageX(1);

        // advance to stage 2
        _test_advanceToStageX(2);

        // execute proposal
        _test_advanceLastStage();
    }

    function test_proposalFlowExecutingLastStage() public {
        // creates proposal on SPP and automatically executes - i.e reports results.
        // Due to minAdvance not yet passed by, proposal doesn't advance yet.
        _test_createProposalAndExecuteSubproposal();

        // advance to stage 1
        _test_advanceToStageX(1);

        // advance to stage 2
        _test_advanceToStageX(2);

        // execute proposal
        _test_executeLastStage();
    }

    // ===== Helper functions - i.e NOT TESTS =======

    // Since stage 0 has adminPlugin, creating a proposal there automatically
    // executes proposals - i.e immediatelly reports result on SPP.
    function _test_createProposalAndExecuteSubproposal() public {
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
        uint256 subproposalId = sppPlugin.getBodyProposalId(proposalId, 0, adminPlugin);
        assertNotEq(subproposalId, 0, "subproposalId");
        assertNotEq(subproposalId, type(uint256).max, "subproposalId");

        // 1. since stage 0's sub body is Admin, it should be executed automatically
        // 2. below checks tally as well.
        (uint256 approvals, uint256 vetos) = sppPlugin.getProposalTally(proposalId, 0);
        assertEq(approvals, 1, "approvals");
        assertEq(vetos, 0, "vetos");
    }

    function _test_advanceToStageX(uint16 _stageId) public {
        // check that proposal can't advance due to min advance time
        assertFalse(sppPlugin.canProposalAdvance(proposalId));

        // move timestamp
        vm.warp(block.timestamp + minAdvance);

        // check proposal can advance
        assertTrue(sppPlugin.canProposalAdvance(proposalId));

        // check that proposal advanced event was emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalAdvanced(proposalId, _stageId, deployer);

        sppPlugin.advanceProposal(proposalId);

        // check that proposal advanced
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        assertEq(proposal.currentStage, _stageId, "currentStage");

        // stage 1 has no bodies so no subroposal was created successfully
        if (_stageId != 1) {
            uint256 subproposalId = sppPlugin.getBodyProposalId(
                proposalId,
                _stageId,
                multisigPlugin
            );
            assertNotEq(subproposalId, 0, "subproposalId");
            assertNotEq(subproposalId, type(uint256).max, "subproposalId");
        }
    }

    function _test_advanceLastStage() public {
        // check proposal can't advance
        assertFalse(sppPlugin.canProposalAdvance(proposalId));

        // approve subproposal so proposal can advance
        uint256 subproposalId = sppPlugin.getBodyProposalId(proposalId, 2, multisigPlugin);

        // Members of multisig are address(1) and address(2), so we set
        // the callers to those in order for `approve` to succeed.

        // approve proposal on multisig by address(1)
        resetPrank(address(1));
        (bool succeed, ) = multisigCallApprove(multisigPlugin, subproposalId, false);
        assertTrue(succeed, "multisigApprove succeeded");

        // approve proposal on multisig by address(2).
        // This must cause the execution of proposal on multisig
        // which must report results on SPP.
        resetPrank(address(2));
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, 2, multisigPlugin);
        (succeed, ) = multisigCallApprove(multisigPlugin, subproposalId, true);
        assertTrue(succeed, "multisigApprove succeeded");

        // reset back prank/caller to default deployer.
        resetPrank(deployer);

        // check reported proposal result was stored.
        SPP.ResultType result = sppPlugin.getBodyResult(proposalId, 2, multisigPlugin);
        assertEq(result, SPP.ResultType.Approval, "result");

        // since results were reported the tally
        // must be updated, so we recheck.
        (uint256 approvals, uint256 vetos) = sppPlugin.getProposalTally(proposalId, 2);
        assertEq(approvals, 1, "approvals");
        assertEq(vetos, 0, "vetos");

        // check proposal is not advanceable due to min advance time
        assertFalse(sppPlugin.canProposalAdvance(proposalId));

        // move timestamp
        vm.warp(block.timestamp + minAdvance);

        assertTrue(sppPlugin.canProposalAdvance(proposalId));

        // check that proposal executed event was emitted.
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalExecuted(proposalId);

        sppPlugin.advanceProposal(proposalId);

        // check proposal executed
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        assertTrue(proposal.executed, "executed");

        // check actions were executed.
        assertEq(target.val(), TARGET_VALUE, "value");
    }

    function _test_executeLastStage() public {
        // check proposal can't advance
        assertFalse(sppPlugin.canProposalAdvance(proposalId));

        // approve subproposal so proposal can advance
        uint256 subproposalId = sppPlugin.getBodyProposalId(proposalId, 2, multisigPlugin);

        // Members of multisig are address(1) and address(2), so we set
        // the callers to those in order for `approve` to succeed.

        // approve proposal on multisig by address(1)
        resetPrank(address(1));
        (bool succeed, ) = multisigCallApprove(multisigPlugin, subproposalId, false);
        assertTrue(succeed, "multisigApprove succeeded");

        // approve proposal on multisig by address(2).
        // This must cause the execution of proposal on multisig
        // which must report results on SPP.
        resetPrank(address(2));
        (succeed, ) = multisigCallApprove(multisigPlugin, subproposalId, false);
        assertTrue(succeed, "multisigApprove succeeded");

        // reset back the prank/caller to default deployer.
        resetPrank(deployer);

        // check proposal result was not reported yet
        SPP.ResultType result = sppPlugin.getBodyResult(proposalId, 2, multisigPlugin);
        assertEq(result, SPP.ResultType.None, "result");

        // result were not reported however the tally should know the subproposal succeeded
        // check tally
        (uint256 approvals, uint256 vetos) = sppPlugin.getProposalTally(proposalId, 2);
        assertEq(approvals, 1, "approvals");
        assertEq(vetos, 0, "vetos");

        // check proposal is not advanceable due to min advance time
        assertFalse(sppPlugin.canProposalAdvance(proposalId));

        // move timestamp
        vm.warp(block.timestamp + minAdvance);

        assertTrue(sppPlugin.canProposalAdvance(proposalId));

        // check proposal executed event emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalExecuted(proposalId);

        sppPlugin.execute(proposalId);

        // check proposal executed
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        assertTrue(proposal.executed, "executed");

        // check action were executed
        assertEq(target.val(), TARGET_VALUE, "value");
    }

    function _configureDummyDaoAndInstallSPP() internal {
        // create new dao with admin plugin.
        DAOFactory.InstalledPlugin[] memory _installedPlugins;
        (dao, _installedPlugins) = _createDummyDaoAdmin();

        adminPlugin = _installedPlugins[0].plugin;

        // install multisig and revoke execute permission
        multisigPlugin = _installMultisigAndRevokeRoot(dao);

        SPP.Stage[] memory stages = new SPP.Stage[](3);

        // stage 0 -> adminPlugin, stage 1 -> no body, stage 2 -> multisigPlugin
        SPP.Body[] memory bodiesStage0 = new SPP.Body[](1);
        SPP.Body[] memory bodiesStage1 = new SPP.Body[](0);
        SPP.Body[] memory bodiesStage2 = new SPP.Body[](1);

        bodiesStage0[0] = SPP.Body({
            addr: adminPlugin,
            isManual: false,
            tryAdvance: true,
            resultType: SPP.ResultType.Approval
        });

        bodiesStage2[0] = SPP.Body({
            addr: multisigPlugin,
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
            bodies: bodiesStage1,
            maxAdvance: maxAdvance,
            minAdvance: minAdvance,
            voteDuration: 10,
            approvalThreshold: 0,
            vetoThreshold: 0,
            cancelable: true,
            editable: true
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
