// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../BaseTest.t.sol";
import {Errors} from "../../../../src/libraries/Errors.sol";
import {PluginA} from "../../../utils/dummy-plugins/PluginA.sol";
import {StagedProposalProcessor as SPP} from "../../../../src/StagedProposalProcessor.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

contract AdvanceProposal_SPP_IntegrationTest is BaseTest {
    modifier givenProposalExists() {
        _;
    }

    modifier whenProposalCanAdvance() {
        _;
    }

    function test_WhenProposalIsInLastStage() external givenProposalExists whenProposalCanAdvance {
        // it should execute the proposal.

        uint256 proposalId = _configureStagesAndCreateDummyProposal(DUMMY_METADATA);

        uint256 initialStage;

        // execute proposals on first stage
        _executeStageProposals(initialStage);

        // advance to last stage
        vm.warp(VOTE_DURATION + START_DATE);
        sppPlugin.advanceProposal(proposalId);

        uint64 lastStageTransition = sppPlugin.getProposal(proposalId).lastStageTransition;

        // execute proposals on first stage
        _executeStageProposals(initialStage + 1);

        // advance last stage
        vm.warp(lastStageTransition + VOTE_DURATION + START_DATE);
        sppPlugin.advanceProposal(proposalId);

        // check proposal executed
        assertTrue(sppPlugin.getProposal(proposalId).executed, "executed");

        // check actions executed
        assertEq(target.val(), TARGET_VALUE, "targetValue");
        assertEq(target.ctrAddress(), TARGET_ADDRESS, "ctrAddress");
    }

    modifier whenProposalIsNotInLastStage() {
        _;
    }

    modifier whenAllPluginsOnNextStageAreNonManual() {
        // configure stages (one of them non-manual)
        SPP.Stage[] memory stages = _createDummyStages(2, false, false, false);
        sppPlugin.updateStages(stages);

        _;
    }

    modifier whenSomeSubProposalNeedExtraParams() {
        // configure in the plugin that extra params are needed.
        PluginA(sppPlugin.getStages()[1].plugins[0].pluginAddress).setNeedExtraParams(true);

        _;
    }

    function test_WhenExtraParamsAreNotProvided()
        external
        givenProposalExists
        whenProposalCanAdvance
        whenProposalIsNotInLastStage
        whenAllPluginsOnNextStageAreNonManual
        whenSomeSubProposalNeedExtraParams
    {
        // it should emit event.
        // it should advance proposal.
        // it should not create sub proposals since extra param was not provided.

        // create proposal
        Action[] memory actions = _createDummyActions();
        uint256 proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });
        uint256 initialStage;

        // execute proposals on first stage
        _executeStageProposals(initialStage);

        vm.warp(VOTE_DURATION + START_DATE);

        // check event emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalAdvanced(proposalId, initialStage + 1);

        sppPlugin.advanceProposal(proposalId);

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        SPP.Stage[] memory stages = sppPlugin.getStages();

        // check proposal advanced
        assertEq(proposal.currentStage, initialStage + 1, "currentStage");

        // check sub proposal was not created
        assertEq(
            PluginA(stages[initialStage + 1].plugins[0].pluginAddress).proposalCount(),
            0,
            "proposalsCount"
        );
    }

    function test_WhenExtraParamsAreProvided()
        external
        givenProposalExists
        whenProposalCanAdvance
        whenProposalIsNotInLastStage
        whenAllPluginsOnNextStageAreNonManual
        whenSomeSubProposalNeedExtraParams
    {
        // it should emit event.
        // it should advance proposal.
        // it should create sub proposals with correct extra params.

        // create custom params
        bytes[][] memory customCreationParam = new bytes[][](2);
        customCreationParam[0] = new bytes[](2);
        customCreationParam[0][0] = abi.encodePacked("data1");
        customCreationParam[0][1] = abi.encodePacked("data2");
        customCreationParam[1] = new bytes[](1);
        customCreationParam[1][0] = abi.encodePacked("data3");

        // create proposal
        Action[] memory actions = _createDummyActions();
        uint256 proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: customCreationParam
        });
        uint256 initialStage;

        // execute proposals on first stage
        _executeStageProposals(initialStage);

        vm.warp(VOTE_DURATION + START_DATE);

        // check event emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalAdvanced(proposalId, initialStage + 1);

        sppPlugin.advanceProposal(proposalId);

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        // check proposal advanced
        assertEq(proposal.currentStage, initialStage + 1, "currentStage");

        SPP.Stage[] memory stages = sppPlugin.getStages();

        // check sub proposal created
        assertEq(
            PluginA(stages[initialStage + 1].plugins[0].pluginAddress).proposalCount(),
            1,
            "proposalsCount"
        );

        // should set the extra params on sub proposals
        assertEq(
            PluginA(stages[initialStage + 1].plugins[0].pluginAddress).extraParams(0),
            customCreationParam[1][0],
            "extraParams"
        );
    }

    function test_WhenExtraParamsAreProvidedAndAreBig()
        external
        givenProposalExists
        whenProposalCanAdvance
        whenProposalIsNotInLastStage
        whenAllPluginsOnNextStageAreNonManual
        whenSomeSubProposalNeedExtraParams
    {
        // it should emit event.
        // it should advance proposal.
        // it should create sub proposals with correct extra params.

        // create custom params
        bytes[][] memory customCreationParam = new bytes[][](2);
        customCreationParam[0] = new bytes[](2);
        customCreationParam[0][0] = abi.encodePacked(
            "data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1"
        );
        customCreationParam[0][1] = abi.encodePacked(
            "data2data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1"
        );
        customCreationParam[1] = new bytes[](1);
        customCreationParam[1][0] = abi.encodePacked(
            "data3data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1data1"
        );

        // create proposal
        Action[] memory actions = _createDummyActions();
        uint256 proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: customCreationParam
        });
        uint256 initialStage;

        // execute proposals on first stage
        _executeStageProposals(initialStage);

        vm.warp(VOTE_DURATION + START_DATE);

        // check event emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalAdvanced(proposalId, initialStage + 1);

        sppPlugin.advanceProposal(proposalId);

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        // check proposal advanced
        assertEq(proposal.currentStage, initialStage + 1, "currentStage");

        SPP.Stage[] memory stages = sppPlugin.getStages();

        // check sub proposal created
        assertEq(
            PluginA(stages[initialStage + 1].plugins[0].pluginAddress).proposalCount(),
            1,
            "proposalsCount"
        );

        // should set the extra params on sub proposals
        assertEq(
            PluginA(stages[initialStage + 1].plugins[0].pluginAddress).extraParams(0),
            customCreationParam[1][0],
            "extraParams"
        );
    }

    function test_WhenExtraParamsAreProvidedButNotEnoughParams()
        external
        givenProposalExists
        whenProposalCanAdvance
        whenProposalIsNotInLastStage
        whenAllPluginsOnNextStageAreNonManual
        whenSomeSubProposalNeedExtraParams
    {
        // it should emit event.
        // it should advance proposal.
        // it should not create sub proposals since extra param was not provided.

        // create custom params
        bytes[][] memory customCreationParam = new bytes[][](2);
        customCreationParam[0] = new bytes[](2);
        customCreationParam[0][0] = abi.encodePacked("data1");
        customCreationParam[0][1] = abi.encodePacked("data2");
        // second stage has a plugin but set no extra params
        customCreationParam[1] = new bytes[](0);

        // create proposal
        Action[] memory actions = _createDummyActions();
        uint256 proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: customCreationParam
        });
        uint256 initialStage;

        // execute proposals on first stage
        _executeStageProposals(initialStage);

        vm.warp(VOTE_DURATION + START_DATE);

        // check event emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalAdvanced(proposalId, initialStage + 1);

        sppPlugin.advanceProposal(proposalId);

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        // check proposal advanced
        assertEq(proposal.currentStage, initialStage + 1, "currentStage");

        SPP.Stage[] memory stages = sppPlugin.getStages();

        // check sub proposal was not created
        assertEq(
            PluginA(stages[initialStage + 1].plugins[0].pluginAddress).proposalCount(),
            0,
            "proposalsCount"
        );
    }

    function test_WhenNoneSubProposalNeedExtraParams()
        external
        givenProposalExists
        whenProposalCanAdvance
        whenProposalIsNotInLastStage
        whenAllPluginsOnNextStageAreNonManual
    {
        // it should emit event.
        // it should advance proposal.
        // it should create sub proposals.

        // create proposal
        Action[] memory actions = _createDummyActions();
        uint256 proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });
        uint256 initialStage;

        // execute proposals on first stage
        _executeStageProposals(initialStage);

        vm.warp(VOTE_DURATION + START_DATE);

        // check event emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalAdvanced(proposalId, initialStage + 1);

        sppPlugin.advanceProposal(proposalId);

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        SPP.Stage[] memory stages = sppPlugin.getStages();

        // check proposal advanced
        assertEq(proposal.currentStage, initialStage + 1, "currentStage");

        // check sub proposal created
        assertEq(
            PluginA(stages[initialStage + 1].plugins[0].pluginAddress).proposalCount(),
            1,
            "proposalsCount"
        );
    }

    function test_WhenSomePluginsOnNextStageAreManual()
        external
        givenProposalExists
        whenProposalCanAdvance
        whenProposalIsNotInLastStage
    {
        // it should emit events.
        // it should advance proposal.
        // it should not create sub proposals.

        // configure stages (one of them non-manual)
        SPP.Stage[] memory stages = _createDummyStages(2, false, true, true);
        sppPlugin.updateStages(stages);

        // create proposal
        Action[] memory actions = _createDummyActions();
        uint256 proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });

        uint256 initialStage;
        // execute proposals on first stage
        _executeStageProposals(initialStage);

        vm.warp(VOTE_DURATION + START_DATE);

        // check event emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalAdvanced(proposalId, initialStage + 1);
        sppPlugin.advanceProposal(proposalId);

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        // check proposal advanced
        assertEq(proposal.currentStage, initialStage + 1, "currentStage");

        // check sub proposal not created
        assertEq(
            PluginA(stages[initialStage + 1].plugins[0].pluginAddress).proposalCount(),
            0,
            "proposalsCount"
        );
    }

    function test_RevertWhen_ProposalCanNotAdvance() external givenProposalExists {
        // it should revert.

        // configure stages
        SPP.Stage[] memory stages = _createDummyStages(2, false, false, false);
        sppPlugin.updateStages(stages);

        // create proposal
        uint256 proposalId = sppPlugin.createProposal({
            _actions: _createDummyActions(),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });

        // check proposal can not advance
        assertFalse(sppPlugin.canProposalAdvance(proposalId), "canAdvanceProposal");

        vm.expectRevert(abi.encodeWithSelector(Errors.ProposalCannotAdvance.selector, proposalId));
        sppPlugin.advanceProposal(proposalId);
    }

    function test_RevertGiven_ProposalDoesNotExist() external {
        // it should revert.

        vm.expectRevert(
            abi.encodeWithSelector(Errors.ProposalNotExists.selector, NON_EXISTENT_PROPOSAL_ID)
        );
        sppPlugin.advanceProposal(NON_EXISTENT_PROPOSAL_ID);
    }
}
