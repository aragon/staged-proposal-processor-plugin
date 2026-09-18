// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {BaseTest} from "../../../BaseTest.t.sol";
import {Errors} from "../../../../src/libraries/Errors.sol";
import {Permissions} from "../../../../src/libraries/Permissions.sol";
import {PluginA} from "../../../utils/dummy-plugins/PluginA/PluginA.sol";
import {StagedProposalProcessor as SPP} from "../../../../src/StagedProposalProcessor.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

contract AdvanceProposal_SPP_IntegrationTest is BaseTest {
    uint256 proposalId;

    modifier givenProposalExists() {
        _;
    }

    modifier whenProposalCanAdvance() {
        _;
    }

    modifier whenProposalIsInLastStage() {
        proposalId = _configureStagesAndCreateDummyProposal(DUMMY_METADATA);
        uint16 initialStage;

        // execute proposals on first stage
        _executeStageProposals(initialStage);

        // advance to last stage
        vm.warp(VOTE_DURATION + START_DATE);
        sppPlugin.advanceProposal(proposalId);

        // execute proposals on first stage
        _executeStageProposals(initialStage + 1);

        _;
    }

    function test_RevertWhen_CallerHasNoExecutePermission()
        external
        givenProposalExists
        whenProposalCanAdvance
        whenProposalIsInLastStage
    {
        // it should revert.
        resetPrank(users.unauthorized);
        vm.warp(sppPlugin.getProposal(proposalId).lastStageTransition + VOTE_DURATION + START_DATE);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ProposalExecutionForbidden.selector, proposalId)
        );
        sppPlugin.advanceProposal(proposalId);
    }

    function test_WhenCallerHasExecutePermission()
        external
        givenProposalExists
        whenProposalCanAdvance
        whenProposalIsInLastStage
    {
        // it should emit ProposalExecuted event.
        // it should execute the proposal.

        // advance last stage
        vm.warp(sppPlugin.getProposal(proposalId).lastStageTransition + VOTE_DURATION + START_DATE);

        // check event emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalExecuted(proposalId);

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
        PluginA(sppPlugin.getStages(sppPlugin.getCurrentConfigIndex())[1].bodies[0].addr)
            .setNeedExtraParams(true);

        _;
    }

    function test_RevertWhen_ExtraParamsAreNotProvided()
        external
        givenProposalExists
        whenProposalCanAdvance
        whenProposalIsNotInLastStage
        whenAllPluginsOnNextStageAreNonManual
        whenSomeSubProposalNeedExtraParams
    {
        // it should revert since the sub-body reverts when the extra param is not provided.
        // it should not advance the proposal.
        // it should not create sub proposals.

        // create proposal
        Action[] memory actions = _createDummyActions();
        proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });
        uint16 initialStage;

        // execute proposals on first stage
        _executeStageProposals(initialStage);

        vm.warp(VOTE_DURATION + START_DATE);

        // the next stage's body reverts, which is rethrown naming that body.
        address failingBody = sppPlugin
        .getStages(sppPlugin.getCurrentConfigIndex())[initialStage + 1].bodies[0].addr;

        vm.expectRevert(_subProposalCreationFailed(failingBody, "needExtraParams"));

        sppPlugin.advanceProposal(proposalId);

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());

        // check proposal did not advance
        assertEq(proposal.currentStage, initialStage, "currentStage");

        // check sub proposal was not created
        assertEq(
            PluginA(stages[initialStage + 1].bodies[0].addr).proposalCount(),
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
        // it should emit ProposalAdvanced event.
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
        proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: customCreationParam
        });
        uint16 initialStage;

        // execute proposals on first stage
        _executeStageProposals(initialStage);

        vm.warp(VOTE_DURATION + START_DATE);

        // check event emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalAdvanced(proposalId, initialStage + 1, users.manager);

        sppPlugin.advanceProposal(proposalId);

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        // check proposal advanced
        assertEq(proposal.currentStage, initialStage + 1, "currentStage");

        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());

        // check sub proposal created
        assertEq(
            PluginA(stages[initialStage + 1].bodies[0].addr).proposalCount(),
            1,
            "proposalsCount"
        );

        // should set the extra params on sub proposals
        assertEq(
            PluginA(stages[initialStage + 1].bodies[0].addr).extraParams(0),
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
        // it should emit ProposalAdvanced event.
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
        proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: customCreationParam
        });
        uint16 initialStage;

        // execute proposals on first stage
        _executeStageProposals(initialStage);

        vm.warp(VOTE_DURATION + START_DATE);

        // check event emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalAdvanced(proposalId, initialStage + 1, users.manager);

        sppPlugin.advanceProposal(proposalId);

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        // check proposal advanced
        assertEq(proposal.currentStage, initialStage + 1, "currentStage");

        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());

        // check sub proposal created
        assertEq(
            PluginA(stages[initialStage + 1].bodies[0].addr).proposalCount(),
            1,
            "proposalsCount"
        );

        // should set the extra params on sub proposals
        assertEq(
            PluginA(stages[initialStage + 1].bodies[0].addr).extraParams(0),
            customCreationParam[1][0],
            "extraParams"
        );
    }

    function test_RevertWhen_ExtraParamsAreProvidedButNotEnoughParams()
        external
        givenProposalExists
        whenProposalCanAdvance
        whenProposalIsNotInLastStage
        whenAllPluginsOnNextStageAreNonManual
        whenSomeSubProposalNeedExtraParams
    {
        // it should revert since the sub-body reverts when the extra param is not provided.
        // it should not advance the proposal.
        // it should not create sub proposals.

        // create custom params
        bytes[][] memory customCreationParam = new bytes[][](2);
        customCreationParam[0] = new bytes[](2);
        customCreationParam[0][0] = abi.encodePacked("data1");
        customCreationParam[0][1] = abi.encodePacked("data2");
        // second stage has a plugin but set no extra params
        customCreationParam[1] = new bytes[](0);

        // create proposal
        Action[] memory actions = _createDummyActions();
        proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: customCreationParam
        });
        uint16 initialStage;

        // execute proposals on first stage
        _executeStageProposals(initialStage);

        vm.warp(VOTE_DURATION + START_DATE);

        // the next stage's body reverts, which is rethrown naming that body.
        address failingBody = sppPlugin
        .getStages(sppPlugin.getCurrentConfigIndex())[initialStage + 1].bodies[0].addr;

        vm.expectRevert(_subProposalCreationFailed(failingBody, "needExtraParams"));

        sppPlugin.advanceProposal(proposalId);

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        // check proposal did not advance
        assertEq(proposal.currentStage, initialStage, "currentStage");

        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());

        // check sub proposal was not created
        assertEq(
            PluginA(stages[initialStage + 1].bodies[0].addr).proposalCount(),
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
        // it should emit ProposalAdvanced event.
        // it should advance proposal.
        // it should create sub proposals.

        // create proposal
        Action[] memory actions = _createDummyActions();
        proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });
        uint16 initialStage;

        // execute proposals on first stage
        _executeStageProposals(initialStage);

        vm.warp(VOTE_DURATION + START_DATE);

        // check event emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalAdvanced(proposalId, initialStage + 1, users.manager);

        sppPlugin.advanceProposal(proposalId);

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());

        // check proposal advanced
        assertEq(proposal.currentStage, initialStage + 1, "currentStage");

        // check sub proposal created
        assertEq(
            PluginA(stages[initialStage + 1].bodies[0].addr).proposalCount(),
            1,
            "proposalsCount"
        );
    }

    function test_WhenCallerHasNoExecutePermission()
        external
        givenProposalExists
        whenProposalCanAdvance
        whenProposalIsNotInLastStage
        whenAllPluginsOnNextStageAreNonManual
    {
        // it should emit ProposalAdvanced event.
        // it should advance proposal.
        // it should create sub proposals.

        // create proposal
        Action[] memory actions = _createDummyActions();
        proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });
        uint16 initialStage;

        // execute proposals on first stage
        _executeStageProposals(initialStage);

        vm.warp(VOTE_DURATION + START_DATE);

        address advanceProposalCaller = users.unauthorized;

        // grant advance permission but not execute permission
        DAO(payable(address(dao))).grant({
            _where: address(sppPlugin),
            _who: advanceProposalCaller,
            _permissionId: Permissions.ADVANCE_PERMISSION_ID
        });

        // check event emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalAdvanced(proposalId, initialStage + 1, advanceProposalCaller);

        resetPrank(advanceProposalCaller);
        sppPlugin.advanceProposal(proposalId);

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());

        // check proposal advanced
        assertEq(proposal.currentStage, initialStage + 1, "currentStage");

        // check sub proposal created
        assertEq(
            PluginA(stages[initialStage + 1].bodies[0].addr).proposalCount(),
            1,
            "proposalsCount"
        );
    }

    function test_RevertWhen_CallerHasNoAdvancePermission()
        external
        givenProposalExists
        whenProposalCanAdvance
        whenProposalIsNotInLastStage
        whenAllPluginsOnNextStageAreNonManual
    {
        // it should revert.

        Action[] memory actions = _createDummyActions();
        proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });
        uint16 initialStage;

        // execute proposals on first stage
        _executeStageProposals(initialStage);

        vm.warp(VOTE_DURATION + START_DATE);

        resetPrank(users.unauthorized);
        vm.warp(sppPlugin.getProposal(proposalId).lastStageTransition + VOTE_DURATION + START_DATE);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ProposalAdvanceForbidden.selector, proposalId)
        );
        sppPlugin.advanceProposal(proposalId);
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
        proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });

        uint16 initialStage;
        // execute proposals on first stage
        _executeStageProposals(initialStage);

        vm.warp(VOTE_DURATION + START_DATE);

        // check event emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalAdvanced(proposalId, initialStage + 1, users.manager);
        sppPlugin.advanceProposal(proposalId);

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        // check proposal advanced
        assertEq(proposal.currentStage, initialStage + 1, "currentStage");

        // check sub proposal not created
        assertEq(
            PluginA(stages[initialStage + 1].bodies[0].addr).proposalCount(),
            0,
            "proposalsCount"
        );
    }

    function test_WhenThereAreNoPluginsOnNextStage()
        external
        givenProposalExists
        whenProposalCanAdvance
        whenProposalIsNotInLastStage
    {
        // it should emit ProposalAdvanced event.
        // it should advance proposal.
        // it should not be able to advance until minAdvance.

        // configure stages (one of them non-manual)
        SPP.Stage[] memory stages = _createDummyStages(2, false, true, true);
        // remove bodies from stage 2
        stages[1].bodies = new SPP.Body[](0);
        stages[1].approvalThreshold = 0;
        stages[1].vetoThreshold = 0;
        sppPlugin.updateStages(stages);

        // create proposal
        Action[] memory actions = _createDummyActions();
        proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });

        uint16 initialStage;
        // execute proposals on first stage
        _executeStageProposals(initialStage);

        vm.warp(VOTE_DURATION + START_DATE);

        // check event emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalAdvanced(proposalId, initialStage + 1, users.manager);
        sppPlugin.advanceProposal(proposalId);

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        // check proposal advanced
        assertEq(proposal.currentStage, initialStage + 1, "currentStage");

        // check proposal can not advance
        assertFalse(sppPlugin.canProposalAdvance(proposalId), "canAdvanceProposal");

        // check can advance after minAdvance
        vm.warp(sppPlugin.getProposal(proposalId).lastStageTransition + minAdvance);
        assertTrue(sppPlugin.canProposalAdvance(proposalId), "canAdvance");
    }

    function test_RevertWhen_SubBodyOnNextStageRevertsOnCreateProposal()
        external
        givenProposalExists
        whenProposalCanAdvance
        whenProposalIsNotInLastStage
        whenAllPluginsOnNextStageAreNonManual
    {
        // it should revert.
        // it should leave the proposal on its current stage, blocking advancement.
        // it should advance once the body behaves again.

        // create proposal
        proposalId = sppPlugin.createProposal({
            _actions: _createDummyActions(),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });
        uint16 initialStage;

        // execute proposals on first stage
        _executeStageProposals(initialStage);

        // make the next stage's body revert when the sub proposal is created
        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());
        address nextStageBody = stages[initialStage + 1].bodies[0].addr;
        PluginA(nextStageBody).setRevertOnCreateProposal(true);

        vm.warp(VOTE_DURATION + START_DATE);

        // a single misbehaving body on the next stage blocks the whole advancement
        vm.expectRevert(_subProposalCreationFailed(nextStageBody, "revertOnCreateProposal"));
        sppPlugin.advanceProposal(proposalId);

        // the proposal is stuck on its current stage
        assertEq(sppPlugin.getProposal(proposalId).currentStage, initialStage, "currentStage");

        // once the body behaves again, the proposal can advance
        PluginA(nextStageBody).setRevertOnCreateProposal(false);
        sppPlugin.advanceProposal(proposalId);

        assertEq(
            sppPlugin.getProposal(proposalId).currentStage,
            initialStage + 1,
            "currentStage"
        );
        assertEq(PluginA(nextStageBody).proposalCount(), 1, "proposalsCount");
    }

    function test_RevertWhen_StageParamsStoredAtCreationCanNotSatisfyTheNextStage()
        external
        givenProposalExists
        whenProposalCanAdvance
        whenProposalIsNotInLastStage
        whenAllPluginsOnNextStageAreNonManual
        whenSomeSubProposalNeedExtraParams
    {
        // it should revert when advancing to the stage whose params are unusable.
        // it should leave the proposal permanently stuck, the stored params are not fixable.

        // The creator supplies usable params for stage zero but none for stage one. Only
        // the stage zero params are exercised during creation, so this proposal is created
        // successfully and the unusable stage one params are written to storage as-is.
        bytes[][] memory customCreationParam = new bytes[][](2);
        customCreationParam[0] = new bytes[](2);
        customCreationParam[0][0] = abi.encodePacked("data1");
        customCreationParam[0][1] = abi.encodePacked("data2");
        customCreationParam[1] = new bytes[](0);

        proposalId = sppPlugin.createProposal({
            _actions: _createDummyActions(),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: customCreationParam
        });
        uint16 initialStage;

        _executeStageProposals(initialStage);

        vm.warp(VOTE_DURATION + START_DATE);

        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());
        address nextStageBody = stages[initialStage + 1].bodies[0].addr;

        // the proposal is otherwise ready to advance
        assertTrue(sppPlugin.canProposalAdvance(proposalId), "canAdvance");

        bytes memory expectedRevert = _subProposalCreationFailed(
            nextStageBody,
            "needExtraParams"
        );

        vm.expectRevert(expectedRevert);
        sppPlugin.advanceProposal(proposalId);

        // Reconfiguring the stages does not repair it. `updateStages` writes a new config
        // index and this proposal keeps the one it was created with, so its stored stage
        // one params are still the unusable ones.
        SPP.Stage[] memory repairedStages = _createDummyStages(2, false, false, false);
        sppPlugin.updateStages(repairedStages);

        assertEq(
            sppPlugin.getCreateProposalParams(proposalId, initialStage + 1, 0),
            bytes(""),
            "storedParams"
        );

        vm.expectRevert(expectedRevert);
        sppPlugin.advanceProposal(proposalId);

        // the proposal never left the stage it was on
        assertEq(sppPlugin.getProposal(proposalId).currentStage, initialStage, "currentStage");
        assertFalse(sppPlugin.getProposal(proposalId).executed, "executed");

        // it is not stuck retryable forever, it simply expires unadvanced once the stage's
        // `maxAdvance` passes, so the proposal can never be executed
        vm.warp(sppPlugin.getProposal(proposalId).lastStageTransition + MAX_ADVANCE + 1);

        assertFalse(sppPlugin.canProposalAdvance(proposalId), "canAdvanceAfterExpiry");
        assertEq(
            uint8(sppPlugin.state(proposalId)),
            uint8(SPP.ProposalState.Expired),
            "state"
        );
    }

    function test_RevertWhen_ProposalCanNotAdvance() external givenProposalExists {
        // it should revert.

        // configure stages
        SPP.Stage[] memory stages = _createDummyStages(2, false, false, false);
        sppPlugin.updateStages(stages);

        // create proposal
        proposalId = sppPlugin.createProposal({
            _actions: _createDummyActions(),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });

        // check proposal can not advance
        assertFalse(sppPlugin.canProposalAdvance(proposalId), "canAdvanceProposal");

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.UnexpectedProposalState.selector,
                proposalId,
                uint8(SPP.ProposalState.Active),
                _encodeStateBitmap(SPP.ProposalState.Advanceable)
            )
        );
        sppPlugin.advanceProposal(proposalId);
    }

    function test_RevertGiven_ProposalDoesNotExist() external {
        // it should revert.

        vm.expectRevert(
            abi.encodeWithSelector(Errors.NonexistentProposal.selector, NON_EXISTENT_PROPOSAL_ID)
        );
        sppPlugin.advanceProposal(NON_EXISTENT_PROPOSAL_ID);
    }
}
