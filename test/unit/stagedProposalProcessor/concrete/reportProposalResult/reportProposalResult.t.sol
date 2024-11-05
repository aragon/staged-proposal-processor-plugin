// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {Errors} from "../../../../../src/libraries/Errors.sol";
import {PluginA} from "../../../../utils/dummy-plugins/PluginA/PluginA.sol";
import {EXECUTE_PROPOSAL_PERMISSION_ID} from "../../../../utils/Permissions.sol";
import {StagedConfiguredSharedTest} from "../../../../StagedConfiguredSharedTest.t.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {Executor} from "@aragon/osx-commons-contracts/src/executors/Executor.sol";

contract ReportProposalResult_SPP_UnitTest is StagedConfiguredSharedTest {
    uint256 internal proposalId;
    bool _tryAdvance;

    modifier givenExistentProposal() {
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

    modifier whenVoteDurationHasNotPassed() {
        _;
    }

    modifier whenTheCallerIsAnAllowedBody() {
        // impersonate the allowed body
        resetPrank(allowedBody);
        _;
    }

    function test_RevertWhen_ReportingForNotCurrentStage()
        external
        givenExistentProposal
        whenVoteDurationHasNotPassed
        whenTheCallerIsAnAllowedBody
    {
        // it should revert.

        uint16 randomStageId = 5;
        vm.expectRevert(abi.encodeWithSelector(Errors.StageIdInvalid.selector, 0, randomStageId));
        sppPlugin.reportProposalResult({
            _proposalId: proposalId,
            _stageId: randomStageId,
            _resultType: SPP.ResultType.Approval,
            _tryAdvance: _tryAdvance
        });
    }

    modifier whenShouldTryAdvanceStage() {
        _tryAdvance = true;
        _;
    }

    modifier whenCallerIsTrustedForwarder() {
        _;
    }

    modifier whenProposalIsInLastStage() {
        SPP.Stage[] memory stages = sppPlugin.getStages();
        // address bodyAddress = stages[0].bodies[0].addr;

        SPP.Proposal memory oldProposal = sppPlugin.getProposal(proposalId);
        // advance the timer to allow the proposal to be advanced
        vm.warp(oldProposal.lastStageTransition + stages[0].minAdvance + 1);

        // execute the sub proposal to report the result and advance to first stage
        PluginA(stages[0].bodies[0].addr).execute({_proposalId: 0});

        _;
    }

    function test_WhenBodyHasNoExecutePermission()
        external
        givenExistentProposal
        whenVoteDurationHasNotPassed
        whenTheCallerIsAnAllowedBody
        whenShouldTryAdvanceStage
        whenCallerIsTrustedForwarder
        whenProposalIsInLastStage
    {
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        SPP.Stage[] memory stages = sppPlugin.getStages();
        address bodyAddress = stages[1].bodies[0].addr;

        vm.warp(proposal.lastStageTransition + stages[1].minAdvance + 1);

        // execute the sub proposal to report the result and advance to last stage
        PluginA(bodyAddress).execute({_proposalId: 0});

        // check result was recorded
        assertEq(
            sppPlugin.getBodyResult(proposalId, proposal.currentStage, bodyAddress),
            SPP.ResultType.Approval,
            "resultType"
        );

        // check proposal was not executed
        assertFalse(sppPlugin.getProposal(proposalId).executed, "executed");
    }

    function test_WhenBodyHasExecutePermission()
        external
        givenExistentProposal
        whenVoteDurationHasNotPassed
        whenTheCallerIsAnAllowedBody
        whenShouldTryAdvanceStage
        whenCallerIsTrustedForwarder
        whenProposalIsInLastStage
    {
        // it should record the result.
        // it execute proposal.

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        SPP.Stage[] memory stages = sppPlugin.getStages();
        address bodyAddress = stages[1].bodies[0].addr;

        // grant permission to the plugin
        DAO(payable(address(dao))).grant(
            address(sppPlugin),
            bodyAddress,
            EXECUTE_PROPOSAL_PERMISSION_ID
        );

        vm.warp(proposal.lastStageTransition + stages[1].minAdvance + 1);

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

    function test_WhenProposalIsNotInLastStage()
        external
        givenExistentProposal
        whenVoteDurationHasNotPassed
        whenTheCallerIsAnAllowedBody
        whenShouldTryAdvanceStage
        whenCallerIsTrustedForwarder
    {
        // it should use the sender stored in the call data.
        // it should record the result.
        // it should emit event proposal result reported.
        // it should call advanceProposal function and emit event.

        SPP.Stage[] memory stages = sppPlugin.getStages();
        address bodyAddress = stages[0].bodies[0].addr;

        SPP.Proposal memory oldProposal = sppPlugin.getProposal(proposalId);
        // advance the timer to allow the proposal to be advanced
        vm.warp(oldProposal.lastStageTransition + stages[0].minAdvance + 1);

        // check event was emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, 0, bodyAddress);
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalAdvanced(proposalId, 1);

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

    modifier whenCallerIsExecutorUsingDelegatecall() {
        _;
    }

    modifier givenProposalIsInLastStage() {
        SPP.Stage[] memory stages = sppPlugin.getStages();
        // address bodyAddress = stages[0].bodies[0].addr;

        SPP.Proposal memory oldProposal = sppPlugin.getProposal(proposalId);
        // advance the timer to allow the proposal to be advanced
        vm.warp(oldProposal.lastStageTransition + stages[0].minAdvance + 1);

        // execute the sub proposal to report the result and advance to first stage
        PluginA(stages[0].bodies[0].addr).execute({_proposalId: 0});

        _;
    }

    function test_GivenBodyHasNoExecutePermission()
        external
        givenExistentProposal
        whenVoteDurationHasNotPassed
        whenTheCallerIsAnAllowedBody
        whenShouldTryAdvanceStage
        whenCallerIsExecutorUsingDelegatecall
        givenProposalIsInLastStage
    {
        // it should record the result.
        // it execute proposal.
        // it should not revert.

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        SPP.Stage[] memory stages = sppPlugin.getStages();
        address bodyAddress = stages[1].bodies[0].addr;

        vm.warp(proposal.lastStageTransition + stages[1].minAdvance + 1);

        // execute the sub proposal to report the result and advance to last stage
        PluginA(bodyAddress).execute({_proposalId: 0});

        // check result was recorded
        assertEq(
            sppPlugin.getBodyResult(proposalId, proposal.currentStage, bodyAddress),
            SPP.ResultType.Approval,
            "resultType"
        );

        // check proposal was not executed
        assertFalse(sppPlugin.getProposal(proposalId).executed, "executed");
    }

    function test_GivenBodyHasExecutePermission()
        external
        givenExistentProposal
        whenVoteDurationHasNotPassed
        whenTheCallerIsAnAllowedBody
        whenShouldTryAdvanceStage
        whenCallerIsExecutorUsingDelegatecall
        givenProposalIsInLastStage
    {
        // it should record the result.
        // it execute proposal.

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        SPP.Stage[] memory stages = sppPlugin.getStages();
        address bodyAddress = stages[1].bodies[0].addr;

        // grant permission to the plugin
        DAO(payable(address(dao))).grant(
            address(sppPlugin),
            bodyAddress,
            EXECUTE_PROPOSAL_PERMISSION_ID
        );

        vm.warp(proposal.lastStageTransition + stages[1].minAdvance + 1);

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

    function test_GivenProposalIsNotInLastStage()
        external
        givenExistentProposal
        whenVoteDurationHasNotPassed
        whenTheCallerIsAnAllowedBody
        whenShouldTryAdvanceStage
        whenCallerIsExecutorUsingDelegatecall
    {
        // it should use the msg.sender that is the plugin.
        // it should record the result.
        // it should emit event proposal result reported.
        // it should call advanceProposal function and emit event.

        // define new executor
        Executor executor = new Executor();

        // update stages to configure them with executor and create new proposal
        proposalId = _updateStagesAndCreateNewProposal(
            address(executor),
            IPlugin.Operation.DelegateCall
        );

        SPP.Stage[] memory stages = sppPlugin.getStages();
        address bodyAddress = stages[0].bodies[0].addr;

        SPP.Proposal memory oldProposal = sppPlugin.getProposal(proposalId);
        // advance the timer to allow the proposal to be advanced
        vm.warp(oldProposal.lastStageTransition + stages[0].minAdvance + 1);

        // check event was emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, 0, bodyAddress);
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalAdvanced(proposalId, 1);

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

    function test_WhenProposalCanBeAdvanced()
        external
        givenExistentProposal
        whenVoteDurationHasNotPassed
        whenTheCallerIsAnAllowedBody
        whenShouldTryAdvanceStage
    {
        // it should record the result.
        // it should emit event proposal result reported.
        // it should call advanceProposal function and emit event.

        SPP.Stage[] memory stages = sppPlugin.getStages();

        // check function was called
        // todo this function is not working with internal functions, wait for foundry support response.
        // vm.expectCall({
        //     callee: address(sppPlugin),
        //     data: abi.encodeCall(sppPlugin.advanceProposal, (proposalId)),
        //     count: 1
        // });

        // check event was emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, 0, allowedBody);
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalAdvanced(proposalId, 1);

        SPP.Proposal memory proposalOld = sppPlugin.getProposal(proposalId);

        // advance the timer
        vm.warp(proposalOld.lastStageTransition + stages[0].minAdvance + 1);

        sppPlugin.reportProposalResult({
            _proposalId: proposalId,
            _stageId: 0,
            _resultType: SPP.ResultType.Approval,
            _tryAdvance: _tryAdvance
        });

        // check result was recorded
        SPP.Proposal memory proposalNew = sppPlugin.getProposal(proposalId);
        assertEq(
            sppPlugin.getBodyResult(proposalId, proposalOld.currentStage, allowedBody),
            SPP.ResultType.Approval,
            "resultType"
        );

        // check proposal was advanced
        assertEq(proposalNew.currentStage, proposalOld.currentStage + 1, "currentStage");
    }

    function test_WhenProposalCanNotBeAdvanced()
        external
        givenExistentProposal
        whenVoteDurationHasNotPassed
        whenTheCallerIsAnAllowedBody
        whenShouldTryAdvanceStage
    {
        // it should record the result.
        // it should emit event proposal result reported.
        // it should not call advanceProposal function nor emit event.

        // check event was emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, 0, allowedBody);

        sppPlugin.reportProposalResult({
            _proposalId: proposalId,
            _stageId: 0,
            _resultType: SPP.ResultType.Approval,
            _tryAdvance: _tryAdvance
        });

        // check result was recorded
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        assertEq(
            sppPlugin.getBodyResult(proposalId, proposal.currentStage, allowedBody),
            SPP.ResultType.Approval,
            "resultType"
        );

        // check proposal stage is has not advanced
        assertEq(proposal.currentStage, 0, "currentStage");
    }

    modifier whenShouldNotTryAdvanceStage() {
        _tryAdvance = false;
        _;
    }

    function test_WhenShouldNotTryAdvanceStage()
        external
        givenExistentProposal
        whenVoteDurationHasNotPassed
        whenTheCallerIsAnAllowedBody
    {
        // it should record the result.
        // it should emit event.
        // it should not call advanceProposal function.

        // todo this function is not working with internal functions, wait for foundry support response.
        // check function call was not made
        // vm.expectCall({
        //     callee: address(sppPlugin),
        //     data: abi.encodeCall(sppPlugin.advanceProposal, (proposalId)),
        //     count: 0
        // });

        // check event
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, 0, allowedBody);

        sppPlugin.reportProposalResult({
            _proposalId: proposalId,
            _stageId: 0,
            _resultType: SPP.ResultType.Approval,
            _tryAdvance: _tryAdvance
        });

        // check result was recorded
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        assertEq(
            sppPlugin.getBodyResult(proposalId, proposal.currentStage, allowedBody),
            SPP.ResultType.Approval,
            "resultType"
        );
        // check proposal stage is has not advanced
        assertEq(proposal.currentStage, 0, "currentStage");
    }

    function test_GivenCallerIsTrustedForwarder()
        external
        givenExistentProposal
        whenVoteDurationHasNotPassed
        whenTheCallerIsAnAllowedBody
        whenShouldNotTryAdvanceStage
    {
        // it should use the sender stored in the call data.
        // it should record the result.
        // it should emit event proposal result reported.
        // it should not call advanceProposal function nor emit event.

        // update stages to configure them with tryAdvance = false and create new proposal
        proposalId = _updateStagesAndCreateNewProposal(
            address(trustedForwarder),
            IPlugin.Operation.Call
        );

        SPP.Stage[] memory stages = sppPlugin.getStages();
        address bodyAddress = stages[0].bodies[0].addr;

        SPP.Proposal memory oldProposal = sppPlugin.getProposal(proposalId);

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

        // check proposal was advanced
        assertEq(newProposal.currentStage, oldProposal.currentStage, "currentStage");
    }

    function test_GivenCallerIsExecutorUsingDelegatecall()
        external
        givenExistentProposal
        whenVoteDurationHasNotPassed
        whenTheCallerIsAnAllowedBody
        whenShouldNotTryAdvanceStage
    {
        // it should use the msg.sender that is the plugin.
        // it should record the result.
        // it should emit event proposal result reported.
        // it should not call advanceProposal function nor emit event.

        // define new executor
        Executor executor = new Executor();

        // update stages to configure them with executor and create new proposal
        proposalId = _updateStagesAndCreateNewProposal(
            address(executor),
            IPlugin.Operation.DelegateCall
        );

        SPP.Stage[] memory stages = sppPlugin.getStages();
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

        // check proposal was not advanced
        assertEq(newProposal.currentStage, oldProposal.currentStage, "currentStage");
    }

    function test_WhenTheCallerIsNotAnAllowedBody()
        external
        givenExistentProposal
        whenVoteDurationHasNotPassed
    {
        // it should record the result for historical data.
        // it should not record the result in the right proposal path.

        // impersonate the unauthorized user
        resetPrank(users.unauthorized);
        sppPlugin.reportProposalResult({
            _proposalId: proposalId,
            _stageId: 0,
            _resultType: SPP.ResultType.Approval,
            _tryAdvance: _tryAdvance
        });

        // check result was recorded
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        assertEq(
            sppPlugin.getBodyResult(proposalId, proposal.currentStage, allowedBody),
            SPP.ResultType.None,
            "resultType"
        );
        assertEq(
            sppPlugin.getBodyResult(proposalId, proposal.currentStage, users.unauthorized),
            SPP.ResultType.Approval,
            "resultType"
        );
    }

    function test_WhenVoteDurationHasPassed() external givenExistentProposal {
        // it should record the result.
        // it should emit event.

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        // pass the stage duration.
        vm.warp(proposal.lastStageTransition + VOTE_DURATION + 1);

        // check event
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, 0, allowedBody);

        sppPlugin.reportProposalResult({
            _proposalId: proposalId,
            _stageId: 0,
            _resultType: SPP.ResultType.Approval,
            _tryAdvance: _tryAdvance
        });

        // check result was recorded
        proposal = sppPlugin.getProposal(proposalId);
        assertEq(
            sppPlugin.getBodyResult(proposalId, proposal.currentStage, allowedBody),
            SPP.ResultType.Approval,
            "resultType"
        );
    }

    function test_RevertGiven_NonExistentProposal() external {
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
