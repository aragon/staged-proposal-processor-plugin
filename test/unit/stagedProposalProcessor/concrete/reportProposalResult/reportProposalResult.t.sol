// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {Errors} from "../../../../../src/libraries/Errors.sol";
import {StagedConfiguredSharedTest} from "../../../../StagedConfiguredSharedTest.t.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";

import {IDAO} from "@aragon/osx-commons-contracts-new/src/dao/IDAO.sol";

contract ReportProposalResult_SPP_UnitTest is StagedConfiguredSharedTest {
    bytes32 internal proposalId;

    modifier givenExistentProposal() {
        // create proposal
        proposalId = sppPlugin.createProposal({
            _actions: _createDummyActions(),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE
        });
        _;
    }

    modifier whenStageDurationHasNotPassed() {
        _;
    }

    modifier whenTheCallerIsAnAllowedBody() {
        _;
    }

    function test_WhenShouldTryAdvanceStage()
        external
        givenExistentProposal
        whenStageDurationHasNotPassed
        whenTheCallerIsAnAllowedBody
    {
        bool _tryAdvance = true;

        // it should not call advanceProposal function.
        // todo this function is not working with internal functions, wait for foundry support response.
        // vm.expectCall({
        //     callee: address(sppPlugin),
        //     data: abi.encodeCall(sppPlugin.advanceProposal, (proposalId)),
        //     count: 1
        // });

        // it should emit event.
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResult(proposalId, users.manager);

        sppPlugin.reportProposalResult({
            _proposalId: proposalId,
            _proposalType: SPP.ProposalType.Approval,
            _tryAdvance: _tryAdvance
        });

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        // it should record the result.
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

    function test_WhenShouldNotTryAdvanceStage()
        external
        givenExistentProposal
        whenStageDurationHasNotPassed
        whenTheCallerIsAnAllowedBody
    {
        bool _tryAdvance = false;

        // todo this function is not working with internal functions, wait for foundry support response.
        // it should not call advanceProposal function.
        // vm.expectCall({
        //     callee: address(sppPlugin),
        //     data: abi.encodeCall(sppPlugin.advanceProposal, (proposalId)),
        //     count: 0
        // });

        // it should emit event.
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalResult(proposalId, users.manager);

        sppPlugin.reportProposalResult({
            _proposalId: proposalId,
            _proposalType: SPP.ProposalType.Approval,
            _tryAdvance: _tryAdvance
        });

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        // it should record the result.
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
        whenStageDurationHasNotPassed
    {
        // todo TBD
        // it should not record the result.
        vm.skip(true);
    }

    function test_RevertWhen_StageDurationHasPassed() external givenExistentProposal {
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        // pass the stage duration.
        vm.warp(proposal.lastStageTransition + STAGE_DURATION + 1);

        // it should revert.
        vm.expectRevert(abi.encodeWithSelector(Errors.StageDurationAlreadyPassed.selector));
        sppPlugin.reportProposalResult({
            _proposalId: proposalId,
            _proposalType: SPP.ProposalType.Approval,
            _tryAdvance: true
        });
    }

    function test_GivenNonExistentProposal() external {
        // todo TBD

        // it should reverts.
        vm.skip(true);
    }
}
