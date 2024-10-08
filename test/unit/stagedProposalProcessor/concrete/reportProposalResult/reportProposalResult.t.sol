// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {Errors} from "../../../../../src/libraries/Errors.sol";
import {StagedConfiguredSharedTest} from "../../../../StagedConfiguredSharedTest.t.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";

contract ReportProposalResult_SPP_UnitTest is StagedConfiguredSharedTest {
    uint256 internal proposalId;

    modifier givenExistentProposal() {
        // create proposal
        proposalId = sppPlugin.createProposal({
            _actions: _createDummyActions(),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _data: defaultCreationParams
        });
        _;
    }

    modifier whenVoteDurationHasNotPassed() {
        _;
    }

    modifier whenTheCallerIsAnAllowedBody() {
        _;
    }

    modifier whenShouldTryAdvanceStage() {
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

        bool _tryAdvance = true;

        // check function was called
        // todo this function is not working with internal functions, wait for foundry support response.
        // vm.expectCall({
        //     callee: address(sppPlugin),
        //     data: abi.encodeCall(sppPlugin.advanceProposal, (proposalId)),
        //     count: 1
        // });

        // check event was emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, users.manager);
        emit ProposalAdvanced(proposalId, 1);

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
                users.manager
            ),
            "pluginResult"
        );
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

        // configure stage that needs 2 approvals
        approvalThreshold = 2;
        SPP.Stage[] memory stages = _createDummyStages(2, false, false, false);
        sppPlugin.updateStages(stages);

        // create proposal
        proposalId = sppPlugin.createProposal({
            _actions: _createDummyActions(),
            _allowFailureMap: 0,
            _metadata: "dummy metadata1",
            _startDate: START_DATE,
            _data: defaultCreationParams
        });
        bool _tryAdvance = true;

        // check event was emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, users.manager);

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
                users.manager
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
        bool _tryAdvance = false;

        // todo this function is not working with internal functions, wait for foundry support response.
        // check function call was not made
        // vm.expectCall({
        //     callee: address(sppPlugin),
        //     data: abi.encodeCall(sppPlugin.advanceProposal, (proposalId)),
        //     count: 0
        // });

        // check event
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResultReported(proposalId, users.manager);

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
                users.manager
            ),
            "pluginResult"
        );
    }

    function test_WhenTheCallerIsNotAnAllowedBody()
        external
        givenExistentProposal
        whenVoteDurationHasNotPassed
    {
        // it should record the result for historical data.
        // it should not record the result in the right proposal path.

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
