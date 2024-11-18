// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BaseTest} from "../../../BaseTest.t.sol";
import {Errors} from "../../../../src/libraries/Errors.sol";

contract HasSucceeded_SPP_IntegrationTest is BaseTest {
    uint256 proposalId;

    modifier whenExistentProposal() {
        proposalId = _configureStagesAndCreateDummyProposal(DUMMY_METADATA);
        _;
    }

    function test_WhenProposalWasExecuted() external whenExistentProposal {
        // it should return true.

        // execute proposals on stage 0
        _executeStageProposals(0);

        // advance to last stage
        vm.warp(VOTE_DURATION + START_DATE);
        sppPlugin.advanceProposal(proposalId);

        // execute proposals on last stage
        _executeStageProposals(1);

        // move timestamp
        vm.warp(sppPlugin.getProposal(proposalId).lastStageTransition + VOTE_DURATION + START_DATE);

        // execute proposal
        sppPlugin.advanceProposal(proposalId);

        bool hasSucceeded = sppPlugin.hasSucceeded(uint256(proposalId));
        assertTrue(hasSucceeded, "hasSucceeded");
    }

    modifier whenProposalIsInLastStage() {
        _executeStageProposals(0);

        // advance to last stage
        vm.warp(VOTE_DURATION + START_DATE);
        sppPlugin.advanceProposal(proposalId);
        _;
    }

    modifier whenProposalHasVetoThreshold() {
        _;
    }

    function test_WhenVotingPeriodHasNotPassed()
        external
        whenExistentProposal
        whenProposalIsInLastStage
        whenProposalHasVetoThreshold
    {
        // it should return false.

        // execute proposals on stage 0
        _executeStageProposals(0);

        // don't move timestamp
        bool hasSucceeded = sppPlugin.hasSucceeded(uint256(proposalId));
        assertFalse(hasSucceeded, "hasSucceeded");
    }

    function test_WhenThresholdIsMet() external whenExistentProposal whenProposalIsInLastStage {
        // it returns true.

        // execute proposals on last stage so it can be advanced
        _executeStageProposals(1);

        uint64 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // move timestamp
        vm.warp(lastStageTransition + VOTE_DURATION + START_DATE);

        bool hasSucceeded = sppPlugin.hasSucceeded(uint256(proposalId));
        assertTrue(hasSucceeded, "hasSucceeded");
    }

    function test_WhenThresholdIsNotMet() external whenExistentProposal whenProposalIsInLastStage {
        // it returns false.

        bool hasSucceeded = sppPlugin.hasSucceeded(uint256(proposalId));
        assertFalse(hasSucceeded, "hasSucceeded");
    }

    function test_WhenProposalIsNotInLastStage() external whenExistentProposal {
        // it should return false.

        bool hasSucceeded = sppPlugin.hasSucceeded(uint256(proposalId));
        assertFalse(hasSucceeded, "hasSucceeded");
    }

    function test_RevertWhen_NonExistentProposal() external {
        // it should revert.
        vm.expectRevert(
            abi.encodeWithSelector(Errors.NonexistentProposal.selector, NON_EXISTENT_PROPOSAL_ID)
        );

        sppPlugin.hasSucceeded(uint256(NON_EXISTENT_PROPOSAL_ID));
    }
}
