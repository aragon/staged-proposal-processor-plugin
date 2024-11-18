// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {BaseTest} from "../../../BaseTest.t.sol";
import {Errors} from "../../../../src/libraries/Errors.sol";

contract CanExecute_SPP_IntegrationTest is BaseTest {
    uint256 proposalId;

    modifier whenExistentProposal() {
        proposalId = _configureStagesAndCreateDummyProposal(DUMMY_METADATA);
        _;
    }

    modifier whenProposalIsInLastStage() {
        _executeStageProposals(0);

        // advance to last stage
        vm.warp(VOTE_DURATION + START_DATE);
        sppPlugin.advanceProposal(proposalId);
        _;
    }

    function test_WhenProposalCanAdvance() external whenExistentProposal whenProposalIsInLastStage {
        // it returns true.

        // execute proposals on last stage so it can be advanced
        _executeStageProposals(1);

        uint64 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // move timestamp
        vm.warp(lastStageTransition + VOTE_DURATION + START_DATE);

        bool canExecute = sppPlugin.canExecute(uint256(proposalId));
        assertTrue(canExecute, "canExecute");
    }

    function test_WhenProposalCanNotAdvance()
        external
        whenExistentProposal
        whenProposalIsInLastStage
    {
        // it returns false.

        bool canExecute = sppPlugin.canExecute(uint256(proposalId));
        assertFalse(canExecute, "canExecute");
    }

    function test_WhenProposalIsNotInLastStage() external whenExistentProposal {
        // it should revert.
        vm.expectRevert(
            abi.encodeWithSelector(Errors.NonexistentProposal.selector, NON_EXISTENT_PROPOSAL_ID)
        );

        sppPlugin.canExecute(uint256(NON_EXISTENT_PROPOSAL_ID));
    }

    function test_WhenNonExistentProposal() external {
        // it should revert.
        vm.expectRevert(
            abi.encodeWithSelector(Errors.NonexistentProposal.selector, NON_EXISTENT_PROPOSAL_ID)
        );

        sppPlugin.canExecute(uint256(NON_EXISTENT_PROPOSAL_ID));
    }
}
