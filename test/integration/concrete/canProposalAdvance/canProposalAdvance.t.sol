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
        _configureStagesAndCreateProposal();
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
        vm.warp(voteDuration + 1);
        sppPlugin.advanceProposal(proposalId);

        uint64 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // execute proposals on first stage
        _executeStageProposals(initialStage + 1);

        // advance last stage
        vm.warp(lastStageTransition + voteDuration + 1);
        sppPlugin.advanceProposal(proposalId);

        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    modifier whenMinAdvanceIsLowerThanVoteDuration() {
        _;
    }

    modifier whenVetoStageThresholdIsNotZero() {
        _;
    }

    function test_WhenStageDurationIsNotReached()
        external
        whenMinAdvanceIsLowerThanVoteDuration
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

    modifier whenVoteDurationIsReached() {
        _;
    }

    modifier proposalTypeVeto() {
        proposalType = SPP.ProposalType.Veto;
        _;
    }

    function test_whenMinAdvanceIsLowerThanVoteDuration_WhenVetoThresholdIsMet()
        external
        proposalTypeVeto
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
        vm.warp(lastStageTransition + voteDuration + 1);
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
        vm.warp(lastStageTransition + voteDuration + 1);
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

        // reach stage duration
        vm.warp(lastStageTransition + voteDuration + 1);
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
        vm.warp(lastStageTransition + voteDuration + 1);
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

        // reach min advance duration but not stage duration
        vm.warp(lastStageTransition + voteDuration + 1);
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
        vm.warp(lastStageTransition + voteDuration + 1);
        bool _canProposalAdvance = sppPlugin.canProposalAdvance(proposalId);

        assertFalse(_canProposalAdvance, "canProposalAdvance");
    }

    modifier whenVoteDurationAndMinAdvanceAreReached() {
        _;
    }

    function test_whenMinAdvanceIsBiggerThanVoteDuration_WhenVetoThresholdIsMet()
        external
        proposalTypeVeto
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
        vm.warp(lastStageTransition + minAdvance + 1);
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
        vm.warp(lastStageTransition + minAdvance + 1);
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

        // reach min advance and stage duration
        vm.warp(lastStageTransition + minAdvance + 1);
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
        vm.warp(lastStageTransition + minAdvance + 1);
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

    // ==== HELPERS ====
    function _executeStageProposals(uint256 _stage) internal {
        // execute proposals on first stage
        SPP.Stage[] memory stages = sppPlugin.getStages();

        for (uint256 i; i < stages[_stage].plugins.length; i++) {
            PluginA(stages[_stage].plugins[i].pluginAddress).execute({_proposalId: 0});
        }
    }

    function _configureStagesAndCreateProposal() internal {
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
