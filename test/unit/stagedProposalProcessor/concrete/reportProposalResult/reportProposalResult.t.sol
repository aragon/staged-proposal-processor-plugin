// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {Errors} from "../../../../../src/libraries/Errors.sol";
import {PluginA} from "../../../../utils/dummy-plugins/PluginA.sol";
import {StagedConfiguredSharedTest} from "../../../../StagedConfiguredSharedTest.t.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";

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

    function test_WhenCallerIsTrustedForwarder()
        external
        givenExistentProposal
        whenVoteDurationHasNotPassed
    {
        // it should use the sender stored in the call data. (the sender should be the plugin address)
        // it should record the result.
        // it should emit event proposal result reported.

        SPP.Stage[] memory stages = sppPlugin.getStages();
        address pluginAddress = stages[0].plugins[0].pluginAddress;

        // check event was emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, pluginAddress);

        // execute the sub proposal to report the result
        PluginA(pluginAddress).execute({_proposalId: 0});

        // check result was recorded
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        assertTrue(
            sppPlugin.getPluginResult(
                proposalId,
                proposal.currentStage,
                SPP.ProposalType.Approval,
                pluginAddress
            ),
            "pluginResult"
        );
    }

    function test_WhenCallerIsExecutorUsingDelegatecall()
        external
        givenExistentProposal
        whenVoteDurationHasNotPassed
    {
        // it should use the msg.sender that is the plugin.
        // it should record the result.
        // it should emit event proposal result reported.

        // define new executor
        Executor executor = new Executor();

        // update stages to configure them with executor
        sppPlugin.updateStages(
            _createCustomStages({
                _stageCount: 2,
                _plugin1Manual: false,
                _plugin2Manual: false,
                _plugin3Manual: false,
                _allowedBody: address(0),
                executor: address(executor),
                operation: IPlugin.Operation.DelegateCall
            })
        );

        // create new proposal
        proposalId = sppPlugin.createProposal({
            _actions: _createDummyActions(),
            _allowFailureMap: 0,
            _metadata: "dummy metadata1",
            _startDate: START_DATE,
            _data: defaultCreationParams
        });

        SPP.Stage[] memory stages = sppPlugin.getStages();
        address pluginAddress = stages[0].plugins[0].pluginAddress;

        // check event was emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, pluginAddress);

        // execute the sub proposal to report the result
        PluginA(pluginAddress).execute({_proposalId: 0});

        // check result was recorded
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        assertTrue(
            sppPlugin.getPluginResult(
                proposalId,
                proposal.currentStage,
                SPP.ProposalType.Approval,
                pluginAddress
            ),
            "pluginResult"
        );
    }

    modifier whenTheCallerIsAnAllowedBody() {
        // impersonate the allowed body
        resetPrank(allowedBody);
        _;
    }

    modifier whenShouldTryAdvanceStage() {
        _tryAdvance = true;
        _;
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
        emit ProposalResultReported(proposalId, allowedBody);
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalAdvanced(proposalId, 1);

        SPP.Proposal memory proposalOld = sppPlugin.getProposal(proposalId);

        // advance the timer
        vm.warp(proposalOld.lastStageTransition + stages[0].minAdvance + 1);

        sppPlugin.reportProposalResult({
            _proposalId: proposalId,
            _proposalType: SPP.ProposalType.Approval,
            _tryAdvance: _tryAdvance
        });

        // check result was recorded
        assertTrue(
            sppPlugin.getPluginResult(
                proposalId,
                proposalOld.currentStage,
                SPP.ProposalType.Approval,
                allowedBody
            ),
            "pluginResult"
        );

        // check proposal was advanced
        SPP.Proposal memory proposalNew = sppPlugin.getProposal(proposalId);
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
        emit ProposalResultReported(proposalId, allowedBody);

        sppPlugin.reportProposalResult({
            _proposalId: proposalId,
            _proposalType: SPP.ProposalType.Approval,
            _tryAdvance: _tryAdvance
        });

        // check result was recorded
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        assertTrue(
            sppPlugin.getPluginResult(
                proposalId,
                proposal.currentStage,
                SPP.ProposalType.Approval,
                allowedBody
            ),
            "pluginResult"
        );

        // check proposal stage is has not advanced
        assertEq(proposal.currentStage, 0, "currentStage");
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
        emit ProposalResultReported(proposalId, allowedBody);

        sppPlugin.reportProposalResult({
            _proposalId: proposalId,
            _proposalType: SPP.ProposalType.Approval,
            _tryAdvance: _tryAdvance
        });

        // check result was recorded
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        assertTrue(
            sppPlugin.getPluginResult(
                proposalId,
                proposal.currentStage,
                SPP.ProposalType.Approval,
                allowedBody
            ),
            "pluginResult"
        );
        // check proposal stage is has not advanced
        assertEq(proposal.currentStage, 0, "currentStage");
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
            _proposalType: SPP.ProposalType.Approval,
            _tryAdvance: false
        });

        // check result was recorded
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        assertFalse(
            sppPlugin.getPluginResult(
                proposalId,
                proposal.currentStage,
                SPP.ProposalType.Approval,
                users.manager
            ),
            "pluginResult allowedBody"
        );
        assertTrue(
            sppPlugin.getPluginResult(
                proposalId,
                proposal.currentStage,
                SPP.ProposalType.Approval,
                users.unauthorized
            ),
            "pluginResult notAllowedBody"
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
        emit ProposalResultReported(proposalId, users.manager);

        sppPlugin.reportProposalResult({
            _proposalId: proposalId,
            _proposalType: SPP.ProposalType.Approval,
            _tryAdvance: false
        });

        // check result was recorded
        proposal = sppPlugin.getProposal(proposalId);
        assertTrue(
            sppPlugin.getPluginResult(
                proposalId,
                proposal.currentStage,
                SPP.ProposalType.Approval,
                users.manager
            ),
            "pluginResult"
        );
    }

    function test_RevertGiven_NonExistentProposal() external {
        // it should revert.

        vm.expectRevert(
            abi.encodeWithSelector(Errors.ProposalNotExists.selector, NON_EXISTENT_PROPOSAL_ID)
        );
        sppPlugin.reportProposalResult({
            _proposalId: NON_EXISTENT_PROPOSAL_ID,
            _proposalType: SPP.ProposalType.Approval,
            _tryAdvance: false
        });
    }
}
