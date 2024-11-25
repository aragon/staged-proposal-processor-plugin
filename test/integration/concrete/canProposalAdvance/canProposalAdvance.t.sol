// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {BaseTest} from "../../../BaseTest.t.sol";
import {Errors} from "../../../../src/libraries/Errors.sol";
import {PluginA} from "../../../utils/dummy-plugins/PluginA/PluginA.sol";
import {StagedProposalProcessor as SPP} from "../../../../src/StagedProposalProcessor.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

contract CanProposalAdvance_SPP_IntegrationTest is BaseTest {
    uint256 proposalId;

    modifier whenExistentProposal() {
        proposalId = _configureStagesAndCreateDummyProposal(DUMMY_METADATA);
        _;
    }

    function test_WhenMinAdvanceIsNotReached() external whenExistentProposal {
        // it should return false.

        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    function test_WhenMaxAdvanceIsReached() external whenExistentProposal {
        // it should return false.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // reach max advance
        vm.warp(lastStageTransition + MAX_ADVANCE + START_DATE);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    function test_WhenProposalIsExecuted() external whenExistentProposal {
        // it should return false.

        uint256 initialStage;

        // execute proposals on first stage
        _executeStageProposals(initialStage);

        // advance to last stage
        vm.warp(voteDuration + START_DATE);
        sppPlugin.advanceProposal(proposalId);

        uint64 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // execute proposals on first stage
        _executeStageProposals(initialStage + 1);

        // advance last stage
        vm.warp(lastStageTransition + voteDuration + START_DATE);
        sppPlugin.advanceProposal(proposalId);

        lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        vm.warp(lastStageTransition + voteDuration + START_DATE);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    modifier whenMinAdvanceIsLowerThanVoteDuration() {
        _;
    }

    modifier whenVetoStageThresholdIsNotZero() {
        _;
    }

    function test_WhenVoteDurationIsNotReached()
        external
        whenMinAdvanceIsLowerThanVoteDuration
        whenVetoStageThresholdIsNotZero
        whenExistentProposal
    {
        // it should return false.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // reach min advance duration but not stage duration
        vm.warp(lastStageTransition + minAdvance + START_DATE);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    modifier whenVoteDurationIsReached() {
        _;
    }

    modifier resultTypeVeto() {
        resultType = SPP.ResultType.Veto;
        _;
    }

    function test_whenMinAdvanceIsLowerThanVoteDuration_WhenVetoThresholdIsMet()
        external
        resultTypeVeto
        whenMinAdvanceIsLowerThanVoteDuration
        whenVetoStageThresholdIsNotZero
        whenVoteDurationIsReached
        whenExistentProposal
    {
        // it should return false.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // execute proposals on first stage to reach veto threshold
        _executeStageProposals(0);

        // reach min advance duration but not stage duration
        vm.warp(lastStageTransition + voteDuration + START_DATE);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    modifier whenVetoThresholdIsNotMet() {
        _;
    }

    function test_whenVetoStageThresholdIsNotZero_WhenApprovalThresholdIsMet()
        external
        whenMinAdvanceIsLowerThanVoteDuration
        whenVetoStageThresholdIsNotZero
        whenVoteDurationIsReached
        whenVetoThresholdIsNotMet
        whenExistentProposal
    {
        // it should return true.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // execute proposals on first stage to reach veto threshold
        _executeStageProposals(0);

        // reach stage duration
        vm.warp(lastStageTransition + voteDuration + START_DATE);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertTrue(_canProposalAdvance, "canProposalAdvance");
    }

    function test_whenVetoStageThresholdIsNotZero_WhenApprovalThresholdIsNotMet()
        external
        whenMinAdvanceIsLowerThanVoteDuration
        whenVetoStageThresholdIsNotZero
        whenVoteDurationIsReached
        whenVetoThresholdIsNotMet
        whenExistentProposal
    {
        // it should return false.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // make bodies not executable so the votes are not counted
        PluginA(sppPlugin.getStages(sppPlugin.getCurrentConfigIndex())[0].bodies[1].addr)
            .setCanExecuteResult(false);
        PluginA(sppPlugin.getStages(sppPlugin.getCurrentConfigIndex())[0].bodies[0].addr)
            .setCanExecuteResult(false);

        // reach stage duration
        vm.warp(lastStageTransition + voteDuration + START_DATE);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    modifier whenVetoStageThresholdIsZero() {
        vetoThreshold = 0;
        _;
    }

    function test_whenVetoStageThresholdIsZero_WhenApprovalThresholdIsMet()
        external
        whenMinAdvanceIsLowerThanVoteDuration
        whenVetoStageThresholdIsZero
        whenExistentProposal
    {
        // it should return true.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // execute proposals on first stage to reach veto threshold
        _executeStageProposals(0);

        // reach min advance duration but not stage duration
        vm.warp(lastStageTransition + voteDuration + START_DATE);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertTrue(_canProposalAdvance, "canProposalAdvance");
    }

    function test_whenVetoStageThresholdIsZero_WhenApprovalThresholdIsNotMet()
        external
        whenMinAdvanceIsLowerThanVoteDuration
        whenVetoStageThresholdIsZero
        whenExistentProposal
    {
        // it should return false.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // make bodies not executable so the votes are not counted
        PluginA(sppPlugin.getStages(sppPlugin.getCurrentConfigIndex())[0].bodies[1].addr)
            .setCanExecuteResult(false);
        PluginA(sppPlugin.getStages(sppPlugin.getCurrentConfigIndex())[0].bodies[0].addr)
            .setCanExecuteResult(false);

        // reach min advance duration but not stage duration
        vm.warp(lastStageTransition + voteDuration + START_DATE);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    modifier whenMinAdvanceIsBiggerThanVoteDuration() {
        minAdvance = VOTE_DURATION;
        voteDuration = MIN_ADVANCE;
        _;
    }

    function test_WhenVoteDurationIsReachedButMinAdvanceIsNotReached()
        external
        whenMinAdvanceIsBiggerThanVoteDuration
        whenExistentProposal
    {
        // it should return false.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // reach min advance duration but not stage duration
        vm.warp(lastStageTransition + voteDuration + START_DATE);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    modifier whenVoteDurationAndMinAdvanceAreReached() {
        _;
    }

    function test_whenMinAdvanceIsBiggerThanVoteDuration_WhenVetoThresholdIsMet()
        external
        resultTypeVeto
        whenMinAdvanceIsBiggerThanVoteDuration
        whenVoteDurationAndMinAdvanceAreReached
        whenVetoStageThresholdIsNotZero
        whenExistentProposal
    {
        // it should return false.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // execute proposals on first stage to reach veto threshold
        _executeStageProposals(0);

        // reach min advance and stage duration
        vm.warp(lastStageTransition + minAdvance + START_DATE);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    function test_whenVetoStageThresholdIsNotZero_GivenApprovalThresholdIsMet()
        external
        whenMinAdvanceIsBiggerThanVoteDuration
        whenVoteDurationAndMinAdvanceAreReached
        whenVetoStageThresholdIsNotZero
        whenVetoThresholdIsNotMet
        whenExistentProposal
    {
        // it should return true.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // execute proposals on first stage to reach veto threshold
        _executeStageProposals(0);

        // reach min advance and stage duration
        vm.warp(lastStageTransition + minAdvance + START_DATE);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertTrue(_canProposalAdvance, "canProposalAdvance");
    }

    function test_whenVetoStageThresholdIsNotZero_GivenApprovalThresholdIsNotMet()
        external
        whenMinAdvanceIsBiggerThanVoteDuration
        whenVoteDurationAndMinAdvanceAreReached
        whenVetoStageThresholdIsNotZero
        whenVetoThresholdIsNotMet
        whenExistentProposal
    {
        // it should return false.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // make bodies not executable so the votes are not counted
        PluginA(sppPlugin.getStages(sppPlugin.getCurrentConfigIndex())[0].bodies[1].addr)
            .setCanExecuteResult(false);
        PluginA(sppPlugin.getStages(sppPlugin.getCurrentConfigIndex())[0].bodies[0].addr)
            .setCanExecuteResult(false);

        // reach min advance and stage duration
        vm.warp(lastStageTransition + minAdvance + START_DATE);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    function test_whenVetoStageThresholdIsZero_GivenApprovalThresholdIsMet()
        external
        whenMinAdvanceIsBiggerThanVoteDuration
        whenVoteDurationAndMinAdvanceAreReached
        whenVetoStageThresholdIsZero
        whenExistentProposal
    {
        // it should return true.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // execute proposals on first stage to reach veto threshold
        _executeStageProposals(0);

        // reach min advance and stage duration
        vm.warp(lastStageTransition + minAdvance + START_DATE);

        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertTrue(_canProposalAdvance, "canProposalAdvance");
    }

    function test_whenVetoStageThresholdIsZero_GivenApprovalThresholdIsNotMet()
        external
        whenMinAdvanceIsBiggerThanVoteDuration
        whenVoteDurationAndMinAdvanceAreReached
        whenVetoStageThresholdIsZero
        whenExistentProposal
    {
        // it should return false.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // make bodies not executable so the votes are not counted
        PluginA(sppPlugin.getStages(sppPlugin.getCurrentConfigIndex())[0].bodies[1].addr)
            .setCanExecuteResult(false);
        PluginA(sppPlugin.getStages(sppPlugin.getCurrentConfigIndex())[0].bodies[0].addr)
            .setCanExecuteResult(false);

        // reach min advance and stage duration
        vm.warp(lastStageTransition + minAdvance + START_DATE);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    function test_RevertWhen_NonExistentProposal() external {
        // it should revert.

        vm.expectRevert(
            abi.encodeWithSelector(Errors.NonexistentProposal.selector, NON_EXISTENT_PROPOSAL_ID)
        );

        sppPlugin.canProposalAdvance(NON_EXISTENT_PROPOSAL_ID);
    }
}
