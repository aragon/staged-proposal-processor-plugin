// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../BaseTest.t.sol";
import {PluginA} from "../../../utils/dummy-plugins/PluginA.sol";
import {StagedConfiguredSharedTest} from "../../../StagedConfiguredSharedTest.t.sol";
import {StagedProposalProcessor as SPP} from "../../../../src/StagedProposalProcessor.sol";

import {IDAO} from "@aragon/osx-commons-contracts-new/src/dao/IDAO.sol";

contract CanProposalAdvance_SPP_IntegrationTest is BaseTest {
    bytes32 proposalId;

    modifier whenExistentProposal() {
        _confStagesAndCreateProposal();
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
        vm.warp(lastStageTransition + MAX_ADVANCE + 1);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    function test_WhenProposalIsExecuted() external whenExistentProposal {
        // it should return false.

        uint256 initialStage;

        // execute proposals on first stage
        _executeStageProposals(initialStage);

        // advance to last stage
        vm.warp(STAGE_DURATION + 1);
        sppPlugin.advanceProposal(proposalId);

        uint64 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // execute proposals on first stage
        _executeStageProposals(initialStage + 1);

        // advance last stage
        vm.warp(lastStageTransition + STAGE_DURATION + 1);
        sppPlugin.advanceProposal(proposalId);

        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    modifier whenMinAdvanceIsLowerThanStageDuration() {
        _;
    }

    modifier whenVetoStageThresholdIsNotZero() {
        _;
    }

    function test_WhenStageDurationIsNotReached()
        external
        whenMinAdvanceIsLowerThanStageDuration
        whenVetoStageThresholdIsNotZero
        whenExistentProposal
    {
        // it should return false.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // reach min advance duration but not stage duration
        vm.warp(lastStageTransition + minAdvance + 1);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    modifier whenStageDurationIsReached() {
        _;
    }

    modifier proposalTypeVeto() {
        proposalType = SPP.ProposalType.Veto;
        _;
    }

    function test_whenMinAdvanceIsLowerThanStageDuration_WhenVetoThresholdIsMet()
        external
        proposalTypeVeto
        whenMinAdvanceIsLowerThanStageDuration
        whenVetoStageThresholdIsNotZero
        whenStageDurationIsReached
        whenExistentProposal
    {
        // it should return false.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // execute proposals on first stage to reach veto threshold
        _executeStageProposals(0);

        // reach min advance duration but not stage duration
        vm.warp(lastStageTransition + stageDuration + 1);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    modifier whenVetoThresholdIsNotMet() {
        _;
    }

    function test_whenVetoStageThresholdIsNotZero_WhenApprovalThresholdIsMet()
        external
        whenMinAdvanceIsLowerThanStageDuration
        whenVetoStageThresholdIsNotZero
        whenStageDurationIsReached
        whenVetoThresholdIsNotMet
        whenExistentProposal
    {
        // it should return true.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // execute proposals on first stage to reach veto threshold
        _executeStageProposals(0);

        // reach stage duration
        vm.warp(lastStageTransition + stageDuration + 1);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertTrue(_canProposalAdvance, "canProposalAdvance");
    }

    function test_whenVetoStageThresholdIsNotZero_WhenApprovalThresholdIsNotMet()
        external
        whenMinAdvanceIsLowerThanStageDuration
        whenVetoStageThresholdIsNotZero
        whenStageDurationIsReached
        whenVetoThresholdIsNotMet
        whenExistentProposal
    {
        // it should return false.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // reach stage duration
        vm.warp(lastStageTransition + stageDuration + 1);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    modifier whenVetoStageThresholdIsZero() {
        vetoThreshold = 0;
        _;
    }

    function test_whenVetoStageThresholdIsZero_WhenApprovalThresholdIsMet()
        external
        whenMinAdvanceIsLowerThanStageDuration
        whenVetoStageThresholdIsZero
        whenExistentProposal
    {
        // it should return true.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // execute proposals on first stage to reach veto threshold
        _executeStageProposals(0);

        // reach min advance duration but not stage duration
        vm.warp(lastStageTransition + stageDuration + 1);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertTrue(_canProposalAdvance, "canProposalAdvance");
    }

    function test_whenVetoStageThresholdIsZero_WhenApprovalThresholdIsNotMet()
        external
        whenMinAdvanceIsLowerThanStageDuration
        whenVetoStageThresholdIsZero
        whenExistentProposal
    {
        // it should return false.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // reach min advance duration but not stage duration
        vm.warp(lastStageTransition + stageDuration + 1);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    modifier whenMinAdvanceIsBiggerThanStageDuration() {
        minAdvance = STAGE_DURATION;
        stageDuration = MIN_ADVANCE;
        _;
    }

    function test_WhenStageDurationIsReachedButMinAdvanceIsNotReached()
        external
        whenMinAdvanceIsBiggerThanStageDuration
        whenExistentProposal
    {
        // it should return false.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // reach min advance duration but not stage duration
        vm.warp(lastStageTransition + stageDuration + 1);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    modifier whenStageDurationAndMinAdvanceAreReached() {
        _;
    }

    function test_whenMinAdvanceIsBiggerThanStageDuration_WhenVetoThresholdIsMet()
        external
        proposalTypeVeto
        whenMinAdvanceIsBiggerThanStageDuration
        whenStageDurationAndMinAdvanceAreReached
        whenVetoStageThresholdIsNotZero
        whenExistentProposal
    {
        // it should return false.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // execute proposals on first stage to reach veto threshold
        _executeStageProposals(0);

        // reach min advance and stage duration
        vm.warp(lastStageTransition + minAdvance + 1);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    function test_whenVetoStageThresholdIsNotZero_GivenApprovalThresholdIsMet()
        external
        whenMinAdvanceIsBiggerThanStageDuration
        whenStageDurationAndMinAdvanceAreReached
        whenVetoStageThresholdIsNotZero
        whenVetoThresholdIsNotMet
        whenExistentProposal
    {
        // it should return true.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // execute proposals on first stage to reach veto threshold
        _executeStageProposals(0);

        // reach min advance and stage duration
        vm.warp(lastStageTransition + minAdvance + 1);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertTrue(_canProposalAdvance, "canProposalAdvance");
    }

    function test_whenVetoStageThresholdIsNotZero_GivenApprovalThresholdIsNotMet()
        external
        whenMinAdvanceIsBiggerThanStageDuration
        whenStageDurationAndMinAdvanceAreReached
        whenVetoStageThresholdIsNotZero
        whenVetoThresholdIsNotMet
        whenExistentProposal
    {
        // it should return false.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // reach min advance and stage duration
        vm.warp(lastStageTransition + minAdvance + 1);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    function test_whenVetoStageThresholdIsZero_GivenApprovalThresholdIsMet()
        external
        whenMinAdvanceIsBiggerThanStageDuration
        whenStageDurationAndMinAdvanceAreReached
        whenVetoStageThresholdIsZero
        whenExistentProposal
    {
        // it should return true.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // execute proposals on first stage to reach veto threshold
        _executeStageProposals(0);

        // reach min advance and stage duration
        vm.warp(lastStageTransition + minAdvance + 1);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertTrue(_canProposalAdvance, "canProposalAdvance");
    }

    function test_whenVetoStageThresholdIsZero_GivenApprovalThresholdIsNotMet()
        external
        whenMinAdvanceIsBiggerThanStageDuration
        whenStageDurationAndMinAdvanceAreReached
        whenVetoStageThresholdIsZero
        whenExistentProposal
    {
        // it should return false.

        uint256 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // reach min advance and stage duration
        vm.warp(lastStageTransition + minAdvance + 1);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    function test_WhenNonExistentProposal() external {
        // todo TBD
        // it should return false.
        vm.skip(true);
    }

    function _executeStageProposals(uint256 _stage) internal {
        // execute proposals on first stage
        SPP.Stage[] memory stages = sppPlugin.getStages();

        for (uint256 i; i < stages[_stage].plugins.length; i++) {
            PluginA(stages[_stage].plugins[i].pluginAddress).execute({_proposalId: 0});
        }
    }

    function _confStagesAndCreateProposal() internal {
        // setup stages
        SPP.Stage[] memory stages = _createDummyStages(2, false, false, false);
        sppPlugin.updateStages(stages);

        // create proposal
        IDAO.Action[] memory actions = _createDummyActions();
        proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE
        });
    }
}
