// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Errors} from "../../../../../src/libraries/Errors.sol";
import {Permissions} from "../../../../../src/libraries/Permissions.sol";
import {PluginA} from "../../../../utils/dummy-plugins/PluginA/PluginA.sol";
import {StagedConfiguredSharedTest} from "../../../../StagedConfiguredSharedTest.t.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {Executor} from "@aragon/osx-commons-contracts/src/executors/Executor.sol";

contract ReportProposalResult_SPP_UnitTest is StagedConfiguredSharedTest {
    uint256 internal proposalId;
    uint16 internal stageId;
    bool _tryAdvance;

    modifier whenProposalExists() {
        // create proposal
        proposalId = sppPlugin.createProposal({
            _actions: _createDummyActions(),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });
        _;
    }

    modifier whenStageIdIsNotValid() {
        _;
    }

    function test_RevertWhen_StageIdBiggerThanCurrentStage()
        external
        whenProposalExists
        whenStageIdIsNotValid
    {
        // it should revert.

        // set stageId to a value bigger than current stage
        uint16 currentStage = sppPlugin.getProposal(proposalId).currentStage;
        stageId = currentStage + 1;

        vm.expectRevert(
            abi.encodeWithSelector(Errors.StageIdInvalid.selector, currentStage, stageId)
        );
        sppPlugin.reportProposalResult({
            _proposalId: proposalId,
            _stageId: stageId,
            _resultType: SPP.ResultType.Approval,
            _tryAdvance: _tryAdvance
        });
    }

    function test_RevertWhen_StageIdDoesNotExist()
        external
        whenProposalExists
        whenStageIdIsNotValid
    {
        // it should revert.

        // set stageId to a value that does not exist
        stageId = uint16(sppPlugin.getStages(sppPlugin.getCurrentConfigIndex()).length) + 1;
        uint16 currentStage = sppPlugin.getProposal(proposalId).currentStage;

        vm.expectRevert(
            abi.encodeWithSelector(Errors.StageIdInvalid.selector, currentStage, stageId)
        );
        sppPlugin.reportProposalResult({
            _proposalId: proposalId,
            _stageId: stageId,
            _resultType: SPP.ResultType.Approval,
            _tryAdvance: _tryAdvance
        });
    }

    modifier whenStageIdIsValid() {
        _;
    }

    modifier whenStageIdIsCurrentStage() {
        _;
    }

    function test_WhenVoteDurationHasPassed()
        external
        whenProposalExists
        whenStageIdIsValid
        whenStageIdIsCurrentStage
    {
        // it should record the result.
        // it should emit ProposalResultReported event.

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        // pass the stage duration.
        vm.warp(proposal.lastStageTransition + VOTE_DURATION + 1);

        address body = _stageBody(0);

        // check event
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, 0, body);

        resetPrank(body);
        sppPlugin.reportProposalResult({
            _proposalId: proposalId,
            _stageId: 0,
            _resultType: SPP.ResultType.Approval,
            _tryAdvance: _tryAdvance
        });

        // check result was recorded
        proposal = sppPlugin.getProposal(proposalId);
        assertEq(
            sppPlugin.getBodyResult(proposalId, proposal.currentStage, body),
            SPP.ResultType.Approval,
            "resultType"
        );
    }

    modifier whenVoteDurationHasNotPassed() {
        _;
    }

    modifier whenShouldTryAdvanceStage() {
        _tryAdvance = true;
        _;
    }

    modifier whenProposalIsAdvanceable() {
        _;
    }

    modifier whenProposalIsAtLastStage() {
        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());

        SPP.Proposal memory oldProposal = sppPlugin.getProposal(proposalId);
        // advance the timer to allow the proposal to be advanced
        vm.warp(oldProposal.lastStageTransition + stages[0].minAdvance + 1);

        // grant advance permission to pluginA to be able to advance to next stage
        address bodyAddress = stages[0].bodies[0].addr;

        DAO(payable(address(dao))).grant({
            _where: address(sppPlugin),
            _who: bodyAddress,
            _permissionId: Permissions.ADVANCE_PERMISSION_ID
        });

        // execute the sub proposal to report the result and advance to last stage (stage 1)
        PluginA(bodyAddress).execute({_proposalId: 0});

        // check proposal was advanced to stage 1
        assertEq(sppPlugin.getProposal(proposalId).currentStage, 1, "currentStage");

        stageId = 1;
        _;
    }

    modifier whenCallerIsTrustedForwarder() {
        _;
    }

    /// @dev generation function name `test_WhenSenderHasExecutePermission`
    function test_WhenCallerIsTrustedForwarderAndHasExecutePermission()
        external
        whenProposalExists
        whenStageIdIsValid
        whenStageIdIsCurrentStage
        whenVoteDurationHasNotPassed
        whenShouldTryAdvanceStage
        whenProposalIsAdvanceable
        whenProposalIsAtLastStage
        whenCallerIsTrustedForwarder
    {
        // it should use the sender stored in the call data.
        // it should record the result and emit ProposalResultReported event.
        // it should execute the proposal and emit ProposalExecuted event.

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());
        address bodyAddress = stages[1].bodies[0].addr;

        vm.warp(proposal.lastStageTransition + stages[1].minAdvance + 1);

        // grant execute permission to pluginA to be able to execute the proposal
        DAO(payable(address(dao))).grant({
            _where: address(sppPlugin),
            _who: bodyAddress,
            _permissionId: Permissions.EXECUTE_PROPOSAL_PERMISSION_ID
        });

        // check event
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, stageId, bodyAddress);

        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalExecuted(proposalId);

        // execute the sub proposal to report the result and advance to last stage
        PluginA(bodyAddress).execute({_proposalId: 0});

        // check result was recorded
        assertEq(
            sppPlugin.getBodyResult(proposalId, proposal.currentStage, bodyAddress),
            SPP.ResultType.Approval,
            "resultType"
        );

        // check proposal was executed
        assertTrue(sppPlugin.getProposal(proposalId).executed, "executed");
    }

    /// @dev generation function name `test_WhenSenderHasNoExecutePermission`
    function test_WhenCallerIsTrustedForwarderAndHasNoExecutePermission()
        external
        whenProposalExists
        whenStageIdIsValid
        whenStageIdIsCurrentStage
        whenVoteDurationHasNotPassed
        whenShouldTryAdvanceStage
        whenProposalIsAdvanceable
        whenProposalIsAtLastStage
        whenCallerIsTrustedForwarder
    {
        // it should use the sender stored in the call data.
        // it should record the result and emit ProposalResultReported event.
        // it should not execute the proposal.

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());
        address bodyAddress = stages[1].bodies[0].addr;

        vm.warp(proposal.lastStageTransition + stages[1].minAdvance + 1);

        // check event
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, stageId, bodyAddress);

        // execute the sub proposal to report the result and advance to last stage
        PluginA(bodyAddress).execute({_proposalId: 0});

        // check result was recorded
        assertEq(
            sppPlugin.getBodyResult(proposalId, proposal.currentStage, bodyAddress),
            SPP.ResultType.Approval,
            "resultType"
        );

        // check proposal was NOT executed
        assertFalse(sppPlugin.getProposal(proposalId).executed, "executed");
    }

    modifier whenCallerIsExecutorUsingDelegatecall() {
        // define new executor
        Executor executor = new Executor();

        // update stages to configure them with executor and create new proposal
        proposalId = _updateStagesAndCreateNewProposal(
            address(executor),
            IPlugin.Operation.DelegateCall
        );

        _;
    }

    /// @dev note the modifiers order `whenCallerIsExecutorUsingDelegatecall` must go before `whenProposalIsAtLastStage`
    ///       generated file order is `whenProposalIsAtLastStage` before `whenCallerIsExecutorUsingDelegatecall`
    /// @dev generation function name `test_WhenCallerHasExecutePermission`
    function test_WhenCallerIsExecutorUsingDelegatecallAndHasExecutePermission()
        external
        whenProposalExists
        whenStageIdIsValid
        whenStageIdIsCurrentStage
        whenVoteDurationHasNotPassed
        whenShouldTryAdvanceStage
        whenProposalIsAdvanceable
        whenCallerIsExecutorUsingDelegatecall
        whenProposalIsAtLastStage
    {
        // it should record the result and emit ProposalResultReported event.
        // it should execute the proposal and emit ProposalExecuted event.

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());
        address bodyAddress = stages[1].bodies[0].addr;

        // grant execute permission to the plugin
        DAO(payable(address(dao))).grant(
            address(sppPlugin),
            bodyAddress,
            Permissions.EXECUTE_PROPOSAL_PERMISSION_ID
        );

        vm.warp(proposal.lastStageTransition + stages[1].minAdvance + 1);

        // check event
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, stageId, bodyAddress);

        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalExecuted(proposalId);

        // execute the sub proposal to report the result and advance to last stage
        PluginA(bodyAddress).execute({_proposalId: 0});

        // check result was recorded
        assertEq(
            sppPlugin.getBodyResult(proposalId, proposal.currentStage, bodyAddress),
            SPP.ResultType.Approval,
            "resultType"
        );

        // check proposal was not executed
        assertTrue(sppPlugin.getProposal(proposalId).executed, "executed");
    }

    /// @dev note the modifiers order `whenCallerIsExecutorUsingDelegatecall` must go before `whenProposalIsAtLastStage`
    ///       generated file order is `whenProposalIsAtLastStage` before `whenCallerIsExecutorUsingDelegatecall`
    /// @dev generation function name `test_WhenCallerHasNoExecutePermission`
    function test_WhenCallerIsExecutorUsingDelegatecallAndHasNoExecutePermission()
        external
        whenProposalExists
        whenStageIdIsValid
        whenStageIdIsCurrentStage
        whenVoteDurationHasNotPassed
        whenShouldTryAdvanceStage
        whenProposalIsAdvanceable
        whenCallerIsExecutorUsingDelegatecall
        whenProposalIsAtLastStage
    {
        // it should record the result and emit ProposalResultReported event.
        // it should not execute the proposal.
        // it should not execute the proposal.

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());
        address bodyAddress = stages[1].bodies[0].addr;

        vm.warp(proposal.lastStageTransition + stages[1].minAdvance + 1);

        // check event
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, stageId, bodyAddress);

        // execute the sub proposal to report the result and advance to last stage
        PluginA(bodyAddress).execute({_proposalId: 0});

        // check result was recorded
        assertEq(
            sppPlugin.getBodyResult(proposalId, proposal.currentStage, bodyAddress),
            SPP.ResultType.Approval,
            "resultType"
        );

        // check proposal was NOT executed
        assertFalse(sppPlugin.getProposal(proposalId).executed, "executed");
    }

    modifier whenProposalIsNotAtLastStage() {
        _;
    }

    /// @dev generation function name `test_WhenSenderHasAdvancePermission`
    function test_WhenCallerIsTrustedForwarderAndHasAdvancePermission()
        external
        whenProposalExists
        whenStageIdIsValid
        whenStageIdIsCurrentStage
        whenVoteDurationHasNotPassed
        whenShouldTryAdvanceStage
        whenProposalIsAdvanceable
        whenProposalIsNotAtLastStage
        whenCallerIsTrustedForwarder
    {
        // it should use the sender stored in the call data.
        // it should record the result and emit ProposalResultReported event.
        // it should advance to next stage, create sub-proposals and emit ProposalAdvanced event.

        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());
        address bodyAddress = stages[0].bodies[0].addr;

        SPP.Proposal memory oldProposal = sppPlugin.getProposal(proposalId);
        // advance the timer to allow the proposal to be advanced
        vm.warp(oldProposal.lastStageTransition + stages[0].minAdvance + 1);

        // grant advance permission to pluginA to be able to advance to next stage
        DAO(payable(address(dao))).grant({
            _where: address(sppPlugin),
            _who: bodyAddress,
            _permissionId: Permissions.ADVANCE_PERMISSION_ID
        });

        // check event was emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, 0, bodyAddress);

        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalAdvanced(proposalId, 1, bodyAddress);

        // execute the sub proposal to report the result
        PluginA(bodyAddress).execute({_proposalId: 0});

        // check result was recorded
        SPP.Proposal memory newProposal = sppPlugin.getProposal(proposalId);
        assertEq(
            sppPlugin.getBodyResult(proposalId, oldProposal.currentStage, bodyAddress),
            SPP.ResultType.Approval,
            "resultType"
        );

        // check proposal was advanced
        assertEq(newProposal.currentStage, oldProposal.currentStage + 1, "currentStage");
    }

    /// @dev generation function name `test_WhenSenderHasNoAdvancePermission`
    function test_WhenCallerIsTrustedForwarderAndHasNoAdvancePermission()
        external
        whenProposalExists
        whenStageIdIsValid
        whenStageIdIsCurrentStage
        whenVoteDurationHasNotPassed
        whenShouldTryAdvanceStage
        whenProposalIsAdvanceable
        whenProposalIsNotAtLastStage
        whenCallerIsTrustedForwarder
    {
        // it should use the sender stored in the call data.
        // it should record the result and emit ProposalResultReported event.
        // it should not advance the proposal.

        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());
        address bodyAddress = stages[0].bodies[0].addr;

        SPP.Proposal memory oldProposal = sppPlugin.getProposal(proposalId);
        // advance the timer to allow the proposal to be advanced
        vm.warp(oldProposal.lastStageTransition + stages[0].minAdvance + 1);

        // check event was emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, 0, bodyAddress);

        // execute the sub proposal to report the result
        PluginA(bodyAddress).execute({_proposalId: 0});

        // check result was recorded
        SPP.Proposal memory newProposal = sppPlugin.getProposal(proposalId);
        assertEq(
            sppPlugin.getBodyResult(proposalId, oldProposal.currentStage, bodyAddress),
            SPP.ResultType.Approval,
            "resultType"
        );

        // check proposal was NOT advanced
        assertEq(newProposal.currentStage, oldProposal.currentStage, "currentStage");
    }

    /// @dev generation function name `test_WhenCallerHasAdvancePermission`
    function test_WhenCallerIsExecutorUsingDelegatecallAndHasAdvancePermission()
        external
        whenProposalExists
        whenStageIdIsValid
        whenStageIdIsCurrentStage
        whenVoteDurationHasNotPassed
        whenShouldTryAdvanceStage
        whenProposalIsAdvanceable
        whenProposalIsNotAtLastStage
        whenCallerIsExecutorUsingDelegatecall
    {
        // it should record the result and emit ProposalResultReported event.
        // it should advance to next stage, create sub-proposals and emit ProposalAdvanced event.

        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());
        address bodyAddress = stages[0].bodies[0].addr;

        SPP.Proposal memory oldProposal = sppPlugin.getProposal(proposalId);
        // advance the timer to allow the proposal to be advanced
        vm.warp(oldProposal.lastStageTransition + stages[0].minAdvance + 1);

        // grant advance permission to pluginA to be able to advance to next stage
        DAO(payable(address(dao))).grant({
            _where: address(sppPlugin),
            _who: bodyAddress,
            _permissionId: Permissions.ADVANCE_PERMISSION_ID
        });

        // check event was emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, 0, bodyAddress);

        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalAdvanced(proposalId, 1, bodyAddress);

        // execute the sub proposal to report the result
        PluginA(bodyAddress).execute({_proposalId: 0});

        // check result was recorded
        SPP.Proposal memory newProposal = sppPlugin.getProposal(proposalId);
        assertEq(
            sppPlugin.getBodyResult(proposalId, oldProposal.currentStage, bodyAddress),
            SPP.ResultType.Approval,
            "resultType"
        );

        // check proposal was advanced
        assertEq(newProposal.currentStage, oldProposal.currentStage + 1, "currentStage");
    }

    /// @dev generation function name `test_WhenCallerHasNoAdvancePermission`
    function test_WhenCallerIsExecutorUsingDelegatecallAndHasNoAdvancePermission()
        external
        whenProposalExists
        whenStageIdIsValid
        whenStageIdIsCurrentStage
        whenVoteDurationHasNotPassed
        whenShouldTryAdvanceStage
        whenProposalIsAdvanceable
        whenProposalIsNotAtLastStage
        whenCallerIsExecutorUsingDelegatecall
    {
        // it should record the result and emit ProposalResultReported event.
        // it should not advance the proposal.

        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());
        address bodyAddress = stages[0].bodies[0].addr;

        SPP.Proposal memory oldProposal = sppPlugin.getProposal(proposalId);
        // advance the timer to allow the proposal to be advanced
        vm.warp(oldProposal.lastStageTransition + stages[0].minAdvance + 1);

        // check event was emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, 0, bodyAddress);

        // execute the sub proposal to report the result
        PluginA(bodyAddress).execute({_proposalId: 0});

        // check result was recorded
        SPP.Proposal memory newProposal = sppPlugin.getProposal(proposalId);
        assertEq(
            sppPlugin.getBodyResult(proposalId, oldProposal.currentStage, bodyAddress),
            SPP.ResultType.Approval,
            "resultType"
        );

        // check proposal was NOT advanced
        assertEq(newProposal.currentStage, oldProposal.currentStage, "currentStage");
    }

    modifier whenProposalIsNotAdvanceable() {
        _;
    }

    /// @dev generation function name `test_GivenCallerIsTrustedForwarder1`
    function test_GivenIsNotAdvanceableAndCallerIsTrustedForwarder()
        external
        whenProposalExists
        whenStageIdIsValid
        whenStageIdIsCurrentStage
        whenVoteDurationHasNotPassed
        whenShouldTryAdvanceStage
        whenProposalIsNotAdvanceable
    {
        // it should use the sender stored in the call data.
        // it should record the result and emit ProposalResultReported event.

        address body = _stageBody(0);

        // check event was emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, 0, body);

        resetPrank(body);
        sppPlugin.reportProposalResult({
            _proposalId: proposalId,
            _stageId: 0,
            _resultType: SPP.ResultType.Approval,
            _tryAdvance: _tryAdvance
        });

        // check result was recorded
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        assertEq(
            sppPlugin.getBodyResult(proposalId, proposal.currentStage, body),
            SPP.ResultType.Approval,
            "resultType"
        );

        // check proposal was NOT advanced
        assertEq(proposal.currentStage, 0, "currentStage");
    }

    /// @dev generation function name `test_GivenCallerIsExecutorUsingDelegatecall1`
    function test_GivenIsNotAdvanceableAndCallerIsExecutorUsingDelegatecall()
        external
        whenProposalExists
        whenStageIdIsValid
        whenStageIdIsCurrentStage
        whenVoteDurationHasNotPassed
        whenShouldTryAdvanceStage
        whenProposalIsNotAdvanceable
    {
        // it should record the result and emit ProposalResultReported event.

        address body = _stageBody(0);

        // check event was emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, 0, body);

        resetPrank(body);
        sppPlugin.reportProposalResult({
            _proposalId: proposalId,
            _stageId: 0,
            _resultType: SPP.ResultType.Approval,
            _tryAdvance: _tryAdvance
        });

        // check result was recorded
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        assertEq(
            sppPlugin.getBodyResult(proposalId, proposal.currentStage, body),
            SPP.ResultType.Approval,
            "resultType"
        );

        // check proposal was NOT advanced
        assertEq(proposal.currentStage, 0, "currentStage");
    }

    modifier whenShouldNotTryAdvanceStage() {
        _tryAdvance = false;
        _;
    }

    function test_GivenCallerIsTrustedForwarder()
        external
        whenProposalExists
        whenStageIdIsValid
        whenStageIdIsCurrentStage
        whenVoteDurationHasNotPassed
        whenShouldNotTryAdvanceStage
    {
        // it should use the sender stored in the call data.
        // it should record the result.
        // it should emit ProposalResultReported event.
        // it should not call advanceProposal function.

        // todo this function is not working with internal functions, wait for foundry support response.
        // check function call was not made
        // vm.expectCall({
        //     callee: address(sppPlugin),
        //     data: abi.encodeCall(sppPlugin.advanceProposal, (proposalId)),
        //     count: 0
        // });

        address body = _stageBody(0);

        // check event
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, 0, body);

        resetPrank(body);
        sppPlugin.reportProposalResult({
            _proposalId: proposalId,
            _stageId: 0,
            _resultType: SPP.ResultType.Approval,
            _tryAdvance: _tryAdvance
        });

        // check result was recorded
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        assertEq(
            sppPlugin.getBodyResult(proposalId, proposal.currentStage, body),
            SPP.ResultType.Approval,
            "resultType"
        );
        // check proposal stage is has NOT advanced
        assertEq(proposal.currentStage, 0, "currentStage");
    }

    function test_GivenCallerIsExecutorUsingDelegatecall()
        external
        whenProposalExists
        whenStageIdIsValid
        whenStageIdIsCurrentStage
        whenVoteDurationHasNotPassed
        whenShouldNotTryAdvanceStage
    {
        // it should use the msg.sender that is the plugin.
        // it should record the result.
        // it should emit ProposalResultReported event.
        // it should not call advanceProposal function nor emit event.

        // define new executor
        Executor executor = new Executor();

        // update stages to configure them with executor and create new proposal
        proposalId = _updateStagesAndCreateNewProposal(
            address(executor),
            IPlugin.Operation.DelegateCall
        );

        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());
        address bodyAddress = stages[0].bodies[0].addr;

        SPP.Proposal memory oldProposal = sppPlugin.getProposal(proposalId);
        // advance the timer to allow the proposal to be advanced
        vm.warp(oldProposal.lastStageTransition + stages[0].minAdvance + 1);

        // todo this function is not working with internal functions, wait for foundry support response.
        // check function call was not made
        // vm.expectCall({
        //     callee: address(sppPlugin),
        //     data: abi.encodeCall(sppPlugin.advanceProposal, (proposalId)),
        //     count: 0
        // });

        // check event was emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, 0, bodyAddress);

        // execute the sub proposal to report the result
        PluginA(bodyAddress).execute({_proposalId: 0});

        // check result was recorded
        SPP.Proposal memory newProposal = sppPlugin.getProposal(proposalId);
        assertEq(
            sppPlugin.getBodyResult(proposalId, oldProposal.currentStage, bodyAddress),
            SPP.ResultType.Approval,
            "resultType"
        );

        // check proposal was NOT advanced
        assertEq(newProposal.currentStage, oldProposal.currentStage, "currentStage");
    }

    /// @dev used the modifier `whenProposalIsAtLastStage` to move the current stage
    function test_WhenStageIdLowerThanCurrentStage()
        external
        whenProposalExists
        whenStageIdIsValid
        whenProposalIsAtLastStage
    {
        // it should record the result.
        // it should emit ProposalResultReported event.

        // get current stage (should be 1)
        uint16 currentStage = sppPlugin.getProposal(proposalId).currentStage;
        stageId = currentStage - 1;

        address body = _stageBody(stageId);

        // check event was emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, stageId, body);

        // report results for the stage 0
        resetPrank(body);
        sppPlugin.reportProposalResult({
            _proposalId: proposalId,
            _stageId: stageId,
            _resultType: SPP.ResultType.Approval,
            _tryAdvance: _tryAdvance
        });

        // check result was recorded
        assertEq(
            sppPlugin.getBodyResult(proposalId, stageId, body),
            SPP.ResultType.Approval,
            "resultType"
        );
    }

    function test_RevertWhen_NonExistentProposal() external {
        // it should revert.

        vm.expectRevert(
            abi.encodeWithSelector(Errors.NonexistentProposal.selector, NON_EXISTENT_PROPOSAL_ID)
        );
        sppPlugin.reportProposalResult({
            _proposalId: NON_EXISTENT_PROPOSAL_ID,
            _stageId: 0,
            _resultType: SPP.ResultType.Approval,
            _tryAdvance: _tryAdvance
        });
    }

    modifier givenStageWithAnApproverAndAVetoer() {
        // one stage with two manual bodies: alice approves, bob vetoes
        SPP.Body[] memory bodies = new SPP.Body[](2);
        bodies[0] = SPP.Body({
            addr: users.alice,
            isManual: true,
            tryAdvance: false,
            resultType: SPP.ResultType.Approval
        });
        bodies[1] = SPP.Body({
            addr: users.bob,
            isManual: true,
            tryAdvance: false,
            resultType: SPP.ResultType.Veto
        });

        approvalThreshold = 1;
        vetoThreshold = 1;
        SPP.Stage[] memory stages = new SPP.Stage[](1);
        stages[0] = _createStageStruct(bodies);
        sppPlugin.updateStages(stages);

        proposalId = sppPlugin.createProposal({
            _actions: _createDummyActions(),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: new bytes[][](0)
        });
        _;
    }

    function test_RevertWhen_ApproverReportsVeto() external givenStageWithAnApproverAndAVetoer {
        // it should revert.

        _expectResultTypeNotAllowed(0, users.alice, SPP.ResultType.Veto);
        _report(users.alice, 0, SPP.ResultType.Veto);
    }

    function test_RevertWhen_VetoerReportsApproval() external givenStageWithAnApproverAndAVetoer {
        // it should revert.

        _expectResultTypeNotAllowed(0, users.bob, SPP.ResultType.Approval);
        _report(users.bob, 0, SPP.ResultType.Approval);
    }

    function test_WhenNonBodyReports() external givenStageWithAnApproverAndAVetoer {
        // it should ignore the report for every result type: no revert, no storage write, no event.

        _assertReportIsIgnored(users.unauthorized, 0, SPP.ResultType.None, false);
        _assertReportIsIgnored(users.unauthorized, 0, SPP.ResultType.Approval, false);
        _assertReportIsIgnored(users.unauthorized, 0, SPP.ResultType.Veto, false);
    }

    function test_WhenNonBodyReportsWithTryAdvance() external givenStageWithAnApproverAndAVetoer {
        // it should not execute an executable proposal, even with the permission to execute it.

        vm.warp(sppPlugin.getProposal(proposalId).lastStageTransition + VOTE_DURATION + 1);
        _report(users.alice, 0, SPP.ResultType.Approval);
        assertEq(
            uint8(sppPlugin.state(proposalId)),
            uint8(SPP.ProposalState.Advanceable),
            "advanceable"
        );

        resetPrank(users.manager);
        DAO(payable(address(dao))).grant(
            address(sppPlugin),
            users.unauthorized,
            Permissions.EXECUTE_PROPOSAL_PERMISSION_ID
        );

        _assertReportIsIgnored(users.unauthorized, 0, SPP.ResultType.Approval, true);

        assertFalse(sppPlugin.getProposal(proposalId).executed, "executed");
        assertEq(
            uint8(sppPlugin.state(proposalId)),
            uint8(SPP.ProposalState.Advanceable),
            "still advanceable"
        );
    }

    function testFuzz_WhenNonBodyReports(
        address _sender,
        uint8 _resultType
    ) external givenStageWithAnApproverAndAVetoer {
        // it should ignore the report of any address that is not a body of the stage.
        vm.assume(_sender != users.alice && _sender != users.bob);
        // the trusted forwarder would report on behalf of the address appended to the calldata
        vm.assume(_sender != address(trustedForwarder));

        SPP.ResultType reported = SPP.ResultType(bound(_resultType, 0, uint8(SPP.ResultType.Veto)));

        _assertReportIsIgnored(_sender, 0, reported, false);
    }

    function test_WhenBodyOfAnotherStageReports() external whenProposalExists {
        // it should ignore the report, as a body only counts on the stages it is listed in.

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        SPP.Stage[] memory stages = sppPlugin.getStages(proposal.stageConfigIndex);
        address stageOneBody = stages[1].bodies[0].addr;
        assertEq(uint8(stages[1].bodies[0].resultType), uint8(SPP.ResultType.Approval));

        _assertReportIsIgnored(stageOneBody, 0, SPP.ResultType.Approval, false);
        _assertReportIsIgnored(stageOneBody, 0, SPP.ResultType.None, false);
    }

    function test_RevertWhen_ForwardedSenderReportsTheOtherType()
        external
        givenStageWithAnApproverAndAVetoer
    {
        // it should check the sender stored in the call data, not the trusted forwarder.

        bytes memory callData = abi.encodePacked(
            abi.encodeCall(
                SPP.reportProposalResult,
                (proposalId, 0, SPP.ResultType.Approval, false)
            ),
            users.bob
        );

        resetPrank(address(trustedForwarder));
        (bool success, bytes memory result) = address(sppPlugin).call(callData);

        assertFalse(success, "forwarded report succeeded");
        assertEq(
            result,
            abi.encodeWithSelector(
                Errors.ResultTypeNotAllowed.selector,
                uint16(0),
                users.bob,
                uint8(SPP.ResultType.Approval)
            ),
            "revert data"
        );
    }

    function test_WhenBodiesReportTheirConfiguredType()
        external
        givenStageWithAnApproverAndAVetoer
    {
        // it should record both results, and re-reporting the same type is allowed.

        _report(users.alice, 0, SPP.ResultType.Approval);
        _report(users.bob, 0, SPP.ResultType.Veto);
        _report(users.bob, 0, SPP.ResultType.Veto);

        assertEq(
            sppPlugin.getBodyResult(proposalId, 0, users.alice),
            SPP.ResultType.Approval,
            "alice"
        );
        assertEq(sppPlugin.getBodyResult(proposalId, 0, users.bob), SPP.ResultType.Veto, "bob");
    }

    function test_WhenBodyRetractsItsResult() external givenStageWithAnApproverAndAVetoer {
        // it should clear the result, so the stage stops counting it.

        // a stage with a veto threshold can only advance once the vote duration has passed
        vm.warp(sppPlugin.getProposal(proposalId).lastStageTransition + VOTE_DURATION + 1);

        _report(users.alice, 0, SPP.ResultType.Approval);
        assertEq(
            uint8(sppPlugin.state(proposalId)),
            uint8(SPP.ProposalState.Advanceable),
            "advanceable after approval"
        );

        _report(users.alice, 0, SPP.ResultType.None);
        assertEq(
            sppPlugin.getBodyResult(proposalId, 0, users.alice),
            SPP.ResultType.None,
            "retracted"
        );
        assertEq(
            uint8(sppPlugin.state(proposalId)),
            uint8(SPP.ProposalState.Active),
            "active after retraction"
        );
    }

    /// @dev The first body of `_stageId` in the current config. Only a listed body's report counts.
    function _stageBody(uint16 _stageId) internal view returns (address) {
        return sppPlugin.getStages(sppPlugin.getCurrentConfigIndex())[_stageId].bodies[0].addr;
    }

    function _report(address _sender, uint16 _stageId, SPP.ResultType _resultType) internal {
        resetPrank(_sender);
        sppPlugin.reportProposalResult(proposalId, _stageId, _resultType, false);
    }

    /// @dev Reports as `_sender` and asserts the SPP ignored it: no storage write and no event.
    function _assertReportIsIgnored(
        address _sender,
        uint16 _stageId,
        SPP.ResultType _resultType,
        bool _tryAdvanceReport
    ) internal {
        resetPrank(_sender);
        vm.recordLogs();
        vm.record();

        sppPlugin.reportProposalResult(proposalId, _stageId, _resultType, _tryAdvanceReport);

        (, bytes32[] memory writes) = vm.accesses(address(sppPlugin));
        assertEq(writes.length, 0, "storage written");
        assertEq(vm.getRecordedLogs().length, 0, "event emitted");
    }

    function _expectResultTypeNotAllowed(
        uint16 _stageId,
        address _sender,
        SPP.ResultType _resultType
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ResultTypeNotAllowed.selector,
                _stageId,
                _sender,
                uint8(_resultType)
            )
        );
    }

    function _updateStagesAndCreateNewProposal(
        address _executor,
        IPlugin.Operation _operation
    ) internal returns (uint256 _proposalId) {
        // update stages to customize the configuration
        sppPlugin.updateStages(
            _createCustomStages({
                _stageCount: 2,
                _body1Manual: false,
                _body2Manual: false,
                _body3Manual: false,
                _executor: _executor,
                _operation: _operation,
                _tryAdvance: _tryAdvance
            })
        );

        // create new proposal
        _proposalId = sppPlugin.createProposal({
            _actions: _createDummyActions(),
            _allowFailureMap: 0,
            _metadata: "dummy metadata1",
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });
    }
}
