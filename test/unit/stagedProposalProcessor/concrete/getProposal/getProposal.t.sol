// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {StagedConfiguredSharedTest} from "../../../../StagedConfiguredSharedTest.t.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";

contract GetProposal_SPP_UnitTest is StagedConfiguredSharedTest {
    function test_WhenNonExistentProposal() external {
        SPP.Proposal memory emptyProposal;

        SPP.Proposal memory proposal = sppPlugin.getProposal(NON_EXISTENT_PROPOSAL_ID);

        // it should return empty proposal.
        assertEq(proposal, emptyProposal);
    }

    function test_WhenExistentProposal() external {
        // create proposal
        bytes32 proposalId = sppPlugin.createProposal({
            _actions: _createDummyActions(),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE
        });
        SPP.Proposal memory expectedProposal = SPP.Proposal({
            allowFailureMap: 0,
            creator: users.manager,
            lastStageTransition: START_DATE,
            metadata: DUMMY_METADATA,
            currentStage: 0,
            stageConfigIndex: sppPlugin.getCurrentConfigIndex(),
            executed: false,
            actions: _createDummyActions()
        });

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        // it should return correct proposal.
        assertEq(proposal, expectedProposal);
    }
}
