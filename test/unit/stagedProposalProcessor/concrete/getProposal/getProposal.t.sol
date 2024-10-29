// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {StagedConfiguredSharedTest} from "../../../../StagedConfiguredSharedTest.t.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";

contract GetProposal_SPP_UnitTest is StagedConfiguredSharedTest {
    function test_WhenNonExistentProposal() external {
        // it should return empty proposal.

        SPP.Proposal memory emptyProposal;

        // check proposal is correct
        SPP.Proposal memory proposal = sppPlugin.getProposal(NON_EXISTENT_PROPOSAL_ID);
        assertEq(proposal, emptyProposal, "proposal");
    }

    function test_WhenExistentProposal() external {
        // it should return correct proposal.

        // create proposal
        uint256 proposalId = sppPlugin.createProposal({
            _actions: _createDummyActions(),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });
        SPP.Proposal memory expectedProposal = SPP.Proposal({
            allowFailureMap: 0,
            lastStageTransition: START_DATE,
            currentStage: 0,
            stageConfigIndex: sppPlugin.getCurrentConfigIndex(),
            executed: false,
            actions: _createDummyActions(),
            targetConfig: defaultTargetConfig
        });

        // check proposal is correct
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        assertEq(proposal, expectedProposal, "proposal");
    }
}
