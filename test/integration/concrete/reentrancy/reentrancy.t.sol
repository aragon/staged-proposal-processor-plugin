// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Vm} from "forge-std/Vm.sol";

import {BaseTest} from "../../../BaseTest.t.sol";
import {Errors} from "../../../../src/libraries/Errors.sol";
import {Permissions} from "../../../../src/libraries/Permissions.sol";
import {PluginA} from "../../../utils/dummy-plugins/PluginA/PluginA.sol";
import {IdAwarePlugin} from "../../../utils/dummy-plugins/IdAwarePlugin.sol";
import {ReentrantPlugin} from "../../../utils/dummy-plugins/ReentrantPlugin.sol";
import {StagedProposalProcessor as SPP} from "../../../../src/StagedProposalProcessor.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {
    IProposal
} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";

/// @dev `_createBodyProposals` only learns a body's sub-proposal id once the external
///      `createProposal` call on that body returns. While that call runs, SPP stores
///      `PROPOSAL_IN_PROGRESS` for the body, and the entries of every body after it in the
///      stage are still unwritten. These tests exercise what a body can do by calling back
///      into SPP from inside that window.
contract Reentrancy_SPP_IntegrationTest is BaseTest {
    /// @dev Mirrors the private constant in SPP.
    uint256 internal constant PROPOSAL_IN_PROGRESS = type(uint256).max - 1;

    bytes32 internal constant PROPOSAL_CREATED_TOPIC =
        keccak256(
            "ProposalCreated(uint256,address,uint64,uint64,bytes,(address,uint256,bytes)[],uint256)"
        );

    /// @dev `StagedProposalProcessorSetup` grants `ADVANCE_PERMISSION_ID` and
    ///      `EXECUTE_PROPOSAL_PERMISSION_ID` to `ANY_ADDR` without a condition, so in a real
    ///      deployment any sub-body may advance or execute. The test DAO only grants them to
    ///      the manager, which would make a reentrant advance fail on permission alone and
    ///      hide whether anything else stops it.
    function _grantProductionPermissions() internal {
        DAO(payable(address(dao))).grant(
            address(sppPlugin),
            ANY_ADDR,
            Permissions.ADVANCE_PERMISSION_ID
        );
        DAO(payable(address(dao))).grant(
            address(sppPlugin),
            ANY_ADDR,
            Permissions.EXECUTE_PROPOSAL_PERMISSION_ID
        );
    }

    /// @dev Two stage config where stage one holds only `_body`. Stage zero keeps the
    ///      `PluginA` bodies from `_createDummyStages` so that it can be reported normally.
    function _configureStageOneWith(address _body) internal returns (SPP.Stage[] memory stages) {
        stages = _createDummyStages(2, false, false, false);
        SPP.Body[] memory stageOneBodies = new SPP.Body[](1);
        stageOneBodies[0] = _createBodyStruct(_body, false);
        stages[1].bodies = stageOneBodies;
    }

    /// @dev Removes every time bound from `_stage` so that `state()` is decided by the
    ///      tally alone. Both values are accepted by `_updateStages`.
    function _removeTimeBounds(SPP.Stage memory _stage) internal pure {
        _stage.minAdvance = 0;
        _stage.vetoThreshold = 0;
    }

    function _createProposalAndPassStageZero() internal returns (uint256 proposalId) {
        proposalId = sppPlugin.createProposal({
            _actions: _createDummyActions(),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });

        // stage zero's bodies report their approval, which is what makes the proposal
        // advanceable once the vote duration has passed
        _executeStageProposals(0);
        vm.warp(VOTE_DURATION + START_DATE);
    }

    function _logIndex(
        Vm.Log[] memory _logs,
        address _emitter,
        bytes32 _topic
    ) internal pure returns (uint256) {
        for (uint256 i; i < _logs.length; i++) {
            if (_logs[i].emitter == _emitter && _logs[i].topics[0] == _topic) {
                return i;
            }
        }
        revert("log not found");
    }

    function _unexpectedStateActive(uint256 _proposalId) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                Errors.UnexpectedProposalState.selector,
                _proposalId,
                uint8(SPP.ProposalState.Active),
                _encodeStateBitmap(SPP.ProposalState.Advanceable)
            );
    }

    /// @dev The revert the outer call ends with when `_body` reenters, gets `Active` back
    ///      from SPP, and bubbles that out of its own `createProposal`.
    function _rejectedReentrantAdvance(
        address _body,
        uint256 _proposalId
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                Errors.SubProposalCreationFailed.selector,
                _body,
                _unexpectedStateActive(_proposalId)
            );
    }

    modifier whenSubBodyReentersDuringCreateProposal() {
        _;
    }

    function test_WhenReportingForAStageThatHasNotBecomeActive()
        external
        whenSubBodyReentersDuringCreateProposal
    {
        // it should reject the reentrant report.
        // it should revert the whole createProposal when the body propagates that failure.

        ReentrantPlugin reentrant = new ReentrantPlugin();

        // Two stages, the reentrant body sits on stage zero. While SPP is creating that
        // body's sub-proposal the proposal is still on stage zero, so reporting a result
        // for stage one is reporting for a stage that has not become active yet.
        SPP.Stage[] memory stages = _createDummyStages(2, false, false, false);
        SPP.Body[] memory stageZeroBodies = new SPP.Body[](1);
        stageZeroBodies[0] = _createBodyStruct(address(reentrant), false);
        stages[0].bodies = stageZeroBodies;
        sppPlugin.updateStages(stages);

        uint16 reportedStageId = 1;

        // the id is derived deterministically, so the reentrant call can target the
        // proposal that is about to be created
        Action[] memory actions = _createDummyActions();
        uint256 expectedProposalId = _predictProposalId(actions, DUMMY_METADATA);

        reentrant.setUpReentrancy({
            _spp: sppPlugin,
            _returnedProposalId: 777,
            _reentrantCalldata: abi.encodeCall(
                SPP.reportProposalResult,
                (expectedProposalId, reportedStageId, SPP.ResultType.Approval, false)
            )
        });

        // SPP rejects the reentrant report, the body bubbles that up out of its own
        // `createProposal`, and SPP rethrows it naming the body.
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.SubProposalCreationFailed.selector,
                address(reentrant),
                abi.encodeWithSelector(
                    Errors.StageIdInvalid.selector,
                    uint64(0),
                    uint64(reportedStageId)
                )
            )
        );

        sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });

        // no proposal was created, `lastStageTransition` is what marks one as existing
        assertEq(
            sppPlugin.getProposal(expectedProposalId).lastStageTransition,
            0,
            "lastStageTransition"
        );
    }

    function test_WhenSubBodyCreatesAnotherProposalOnSPP()
        external
        whenSubBodyReentersDuringCreateProposal
    {
        // it should create the inner proposal with its own sub-proposal ids.
        // it should store the outer proposal's sub-proposal ids untouched by the inner one.

        ReentrantPlugin reentrant = new ReentrantPlugin();

        // Stage zero is [reentrant, pluginA]. The reentrant body creates a second SPP
        // proposal from inside its own `createProposal`, while the outer loop has not yet
        // reached `pluginA`. `pluginA` hands out increasing ids, so which proposal got
        // which of its sub-proposals is visible afterwards.
        SPP.Stage[] memory stages = _createDummyStages(2, false, false, false);
        address pluginA = stages[0].bodies[1].addr;
        stages[0].bodies[0] = _createBodyStruct(address(reentrant), false);
        sppPlugin.updateStages(stages);

        DAO(payable(address(dao))).grant(
            address(sppPlugin),
            address(reentrant),
            Permissions.CREATE_PROPOSAL_PERMISSION_ID
        );

        Action[] memory actions = _createDummyActions();
        bytes memory innerMetadata = "inner";

        reentrant.setUpReentrancy({
            _spp: sppPlugin,
            _returnedProposalId: 777,
            _reentrantCalldata: abi.encodeWithSignature(
                "createProposal(bytes,(address,uint256,bytes)[],uint128,uint64,bytes[][])",
                innerMetadata,
                actions,
                uint128(0),
                uint64(0),
                defaultCreationParams
            )
        });

        vm.recordLogs();

        uint256 outerProposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });

        uint256 innerProposalId = _predictProposalIdFor(actions, innerMetadata, address(reentrant));

        assertTrue(reentrant.reentrantCallSucceeded(), "reentrantCallSucceeded");
        assertEq(sppPlugin.getProposal(innerProposalId).creator, address(reentrant), "innerCreator");

        // The inner proposal finished first, so it took `pluginA`'s first sub-proposal and
        // the outer one took the second. Neither overwrote the other's entry.
        assertEq(sppPlugin.getBodyProposalId(innerProposalId, 0, pluginA), 0, "innerPluginAId");
        assertEq(sppPlugin.getBodyProposalId(outerProposalId, 0, pluginA), 1, "outerPluginAId");
        assertEq(PluginA(pluginA).proposalCount(), 2, "pluginAProposalCount");

        assertEq(
            sppPlugin.getBodyProposalId(innerProposalId, 0, address(reentrant)),
            777,
            "innerReentrantId"
        );
        assertEq(
            sppPlugin.getBodyProposalId(outerProposalId, 0, address(reentrant)),
            777,
            "outerReentrantId"
        );

        // and the inner proposal was announced before the outer one that spawned it
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 innerCreated = _logIndex(logs, address(sppPlugin), PROPOSAL_CREATED_TOPIC);
        assertEq(uint256(logs[innerCreated].topics[1]), innerProposalId, "firstProposalCreated");
    }

    function test_WhenStageZeroHasNoTimeBoundsSubBodyCanNotExecuteTheProposalDuringItsCreation()
        external
        whenSubBodyReentersDuringCreateProposal
    {
        // it should reject the reentrant advance although the tally alone would pass.
        // it should not create the proposal when the body propagates that failure.

        _grantProductionPermissions();

        ReentrantPlugin reentrant = new ReentrantPlugin();

        // Single stage, no time bounds, so `state()` is decided by the tally alone. The
        // reentrant body answers `true` to any `hasSucceeded`, and it is the only body, so
        // the stage would pass if the tally consulted it. It is on its last stage, so a
        // successful advance would execute the proposal from inside its own creation.
        SPP.Stage[] memory stages = new SPP.Stage[](1);
        SPP.Body[] memory bodies = new SPP.Body[](1);
        bodies[0] = _createBodyStruct(address(reentrant), false);
        stages[0] = _createStageStruct(bodies);
        _removeTimeBounds(stages[0]);
        sppPlugin.updateStages(stages);

        Action[] memory actions = _createDummyActions();
        uint256 expectedProposalId = _predictProposalId(actions, DUMMY_METADATA);

        reentrant.setUpReentrancy({
            _spp: sppPlugin,
            _returnedProposalId: 777,
            _reentrantCalldata: abi.encodeCall(SPP.advanceProposal, (expectedProposalId))
        });

        // The body's own entry holds `PROPOSAL_IN_PROGRESS`, so the tally refuses to score
        // the stage, `state()` is `Active` and the advance is rejected.
        vm.expectRevert(_rejectedReentrantAdvance(address(reentrant), expectedProposalId));

        // `_startDate` of zero is `block.timestamp`, a future start date would keep the
        // proposal `Active` until it is reached even without the marker
        sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: 0,
            _proposalParams: defaultCreationParams
        });

        // nothing happened, no proposal and no executed actions
        assertEq(
            sppPlugin.getProposal(expectedProposalId).lastStageTransition,
            0,
            "lastStageTransition"
        );
        assertEq(target.val(), 0, "targetValue");
    }

    modifier whenSubBodyReentersDuringAdvance() {
        _;
    }

    function test_WhenReportingForTheStageBeingAdvancedTo()
        external
        whenSubBodyReentersDuringAdvance
    {
        // it should accept the reentrant report.
        // `_advanceProposal` increments `currentStage` before it creates the new stage's
        // sub-proposals, so a body on that stage already sees its own stage as current and
        // passes the `_stageId > currentStage` check. Reporting never consults the tally,
        // so the in progress marker does not get in its way.

        ReentrantPlugin reentrant = new ReentrantPlugin();
        sppPlugin.updateStages(_configureStageOneWith(address(reentrant)));

        uint256 proposalId = _createProposalAndPassStageZero();
        uint16 advancedStageId = 1;

        // report for the stage being advanced to, which is already `currentStage` by the
        // time this body's `createProposal` runs
        reentrant.setUpReentrancy({
            _spp: sppPlugin,
            _returnedProposalId: 777,
            _reentrantCalldata: abi.encodeCall(
                SPP.reportProposalResult,
                (proposalId, advancedStageId, SPP.ResultType.Approval, false)
            )
        });

        // the reentrant report is accepted, so `createProposal` does not revert and the
        // advance completes
        sppPlugin.advanceProposal(proposalId);

        // the body recorded an approval for the stage it was still being created on
        assertEq(
            uint8(sppPlugin.getBodyResult(proposalId, advancedStageId, address(reentrant))),
            uint8(SPP.ResultType.Approval),
            "bodyResult"
        );

        // the id was stored once `createProposal` returned
        assertEq(
            sppPlugin.getBodyProposalId(proposalId, advancedStageId, address(reentrant)),
            777,
            "bodyProposalId"
        );

        assertEq(sppPlugin.getProposal(proposalId).currentStage, advancedStageId, "currentStage");
    }

    function test_WhenSubBodyReadsItsOwnIdDuringAdvance()
        external
        whenSubBodyReentersDuringAdvance
    {
        // it should read the in progress marker for its own sub-proposal id.
        // it should not be asked hasSucceeded at all while its id is not stored.
        // it should not look advanceable from inside the window.
        // it should read its real id once createProposal has returned.

        ReentrantPlugin reentrant = new ReentrantPlugin();
        SPP.Stage[] memory stages = _configureStageOneWith(address(reentrant));
        // With the default bounds `state()` returns `Active` on `minAdvance` before it
        // ever tallies, so the mapping is not even read. Without them the tally runs and
        // it is the marker alone that keeps the stage from being scored.
        _removeTimeBounds(stages[1]);
        sppPlugin.updateStages(stages);

        uint256 proposalId = _createProposalAndPassStageZero();

        // observe only, no call back into SPP that changes state
        reentrant.setUpReentrancy({
            _spp: sppPlugin,
            _returnedProposalId: 777,
            _reentrantCalldata: ""
        });

        // The body calls `canProposalAdvance` from inside the window. The tally must stop at
        // the marker and never ask this body about any id, neither the unwritten zero nor
        // the 777 it is about to return.
        vm.expectCall(address(reentrant), abi.encodeCall(IProposal.hasSucceeded, (0)), 0);
        vm.expectCall(address(reentrant), abi.encodeCall(IProposal.hasSucceeded, (777)), 0);

        sppPlugin.advanceProposal(proposalId);

        assertTrue(reentrant.reentered(), "reentered");
        assertEq(reentrant.observedBodyProposalId(), PROPOSAL_IN_PROGRESS, "observedBodyProposalId");
        assertFalse(reentrant.observedCanAdvance(), "observedCanAdvance");
        assertEq(reentrant.observedState(), uint8(SPP.ProposalState.Active), "observedState");

        assertEq(sppPlugin.getBodyProposalId(proposalId, 1, address(reentrant)), 777, "storedBodyProposalId");
    }

    function test_WhenStageHasDefaultTimeBoundsSubBodyCanNotAdvanceDuringItsCreation()
        external
        whenSubBodyReentersDuringAdvance
    {
        // it should reject the reentrant advance because the stage just started.
        // it should advance normally once the body no longer reenters.

        _grantProductionPermissions();

        ReentrantPlugin reentrant = new ReentrantPlugin();
        sppPlugin.updateStages(_configureStageOneWith(address(reentrant)));

        uint256 proposalId = _createProposalAndPassStageZero();

        reentrant.setUpReentrancy({
            _spp: sppPlugin,
            _returnedProposalId: 777,
            _reentrantCalldata: abi.encodeCall(SPP.advanceProposal, (proposalId))
        });

        // The body has permission to advance. Stage one's `lastStageTransition` was just
        // set to now, so `minAdvance` has not elapsed and `state()` is `Active` before the
        // tally, and with it the marker, is even reached.
        vm.expectRevert(_rejectedReentrantAdvance(address(reentrant), proposalId));
        sppPlugin.advanceProposal(proposalId);

        // control: the same advance goes through when the body does not reenter
        reentrant.setUpReentrancy({
            _spp: sppPlugin,
            _returnedProposalId: 777,
            _reentrantCalldata: ""
        });
        sppPlugin.advanceProposal(proposalId);

        assertEq(sppPlugin.getProposal(proposalId).currentStage, 1, "currentStage");
        assertEq(sppPlugin.getBodyProposalId(proposalId, 1, address(reentrant)), 777, "bodyProposalId");
    }

    function test_WhenStageHasNoTimeBoundsSubBodyCanNotExecuteTheProposalDuringItsCreation()
        external
        whenSubBodyReentersDuringAdvance
    {
        // it should reject the reentrant advance although the tally alone would pass.
        // it should leave the proposal on its current stage when the body propagates that failure.
        // it should advance normally once the body no longer reenters.

        _grantProductionPermissions();

        ReentrantPlugin reentrant = new ReentrantPlugin();
        SPP.Stage[] memory stages = _configureStageOneWith(address(reentrant));
        _removeTimeBounds(stages[1]);
        sppPlugin.updateStages(stages);

        uint256 proposalId = _createProposalAndPassStageZero();

        reentrant.setUpReentrancy({
            _spp: sppPlugin,
            _returnedProposalId: 777,
            _reentrantCalldata: abi.encodeCall(SPP.advanceProposal, (proposalId))
        });

        // No time bound holds the stage back here. It is the marker in the body's own
        // entry that makes the tally refuse to score the stage.
        vm.expectRevert(_rejectedReentrantAdvance(address(reentrant), proposalId));
        sppPlugin.advanceProposal(proposalId);

        assertEq(sppPlugin.getProposal(proposalId).currentStage, 0, "currentStage");
        assertFalse(sppPlugin.getProposal(proposalId).executed, "executed");
        assertEq(target.val(), 0, "targetValue");

        // control: without reentering, stage one is created and, since the body approves
        // and nothing else gates the stage, the proposal is then advanceable the normal way
        reentrant.setUpReentrancy({
            _spp: sppPlugin,
            _returnedProposalId: 777,
            _reentrantCalldata: ""
        });
        sppPlugin.advanceProposal(proposalId);

        assertEq(sppPlugin.getProposal(proposalId).currentStage, 1, "currentStage");
        assertEq(sppPlugin.getBodyProposalId(proposalId, 1, address(reentrant)), 777, "bodyProposalId");
        assertTrue(sppPlugin.canProposalAdvance(proposalId), "canProposalAdvance");
    }

    function test_WhenSubBodySwallowsTheRejectedReentrantAdvance()
        external
        whenSubBodyReentersDuringAdvance
    {
        // it should reject the reentrant advance.
        // it should complete the outer advance as if the body had not reentered.

        _grantProductionPermissions();

        ReentrantPlugin reentrant = new ReentrantPlugin();
        SPP.Stage[] memory stages = _configureStageOneWith(address(reentrant));
        _removeTimeBounds(stages[1]);
        sppPlugin.updateStages(stages);

        uint256 proposalId = _createProposalAndPassStageZero();

        // A realistic attacker ignores the failed call and returns normally, so that the
        // outer advance does not revert and give the attempt away.
        reentrant.setPropagateFailure(false);
        reentrant.setUpReentrancy({
            _spp: sppPlugin,
            _returnedProposalId: 777,
            _reentrantCalldata: abi.encodeCall(SPP.advanceProposal, (proposalId))
        });

        sppPlugin.advanceProposal(proposalId);

        // the reentrant advance was rejected with the same error as when it is propagated
        assertTrue(reentrant.reentrantCallMade(), "reentrantCallMade");
        assertFalse(reentrant.reentrantCallSucceeded(), "reentrantCallSucceeded");
        assertEq(
            reentrant.reentrantCallReturnData(),
            _unexpectedStateActive(proposalId),
            "reentrantCallReturnData"
        );

        // and the outer advance did exactly what it does for an honest body
        assertEq(sppPlugin.getProposal(proposalId).currentStage, 1, "currentStage");
        assertFalse(sppPlugin.getProposal(proposalId).executed, "executed");
        assertEq(target.val(), 0, "targetValue");
        assertEq(sppPlugin.getBodyProposalId(proposalId, 1, address(reentrant)), 777, "bodyProposalId");
    }

    modifier whenALaterBodyOnTheStageHasAnOldProposalWithIdZero() {
        _;
    }

    function test_WhenSubBodyReentersTheTallyDoesNotCountTheLaterBodyByItsStaleId()
        external
        whenSubBodyReentersDuringAdvance
        whenALaterBodyOnTheStageHasAnOldProposalWithIdZero
    {
        // it should reject the reentrant advance.
        // it should not ask the later body about id zero.

        _grantProductionPermissions();

        ReentrantPlugin reentrant = new ReentrantPlugin();
        IdAwarePlugin honest = new IdAwarePlugin();

        // The honest body has an old proposal with id 0 that passed. Its sub-proposal for
        // this SPP proposal will get id 1 and nobody will vote on it.
        honest.setSucceeded(0, true);

        // Stage one is [reentrant, honest] and needs both to approve. While the reentrant
        // body's `createProposal` runs, the honest body's entry is still zero because the
        // loop has not reached it. Before the marker, the tally would have asked the honest
        // body `hasSucceeded(0)`, counted the old proposal as this one's approval, and let
        // the reentrant body execute the proposal.
        SPP.Stage[] memory stages = _createDummyStages(2, false, false, false);
        SPP.Body[] memory stageOneBodies = new SPP.Body[](2);
        stageOneBodies[0] = _createBodyStruct(address(reentrant), false);
        stageOneBodies[1] = _createBodyStruct(address(honest), false);
        stages[1].bodies = stageOneBodies;
        stages[1].approvalThreshold = 2;
        _removeTimeBounds(stages[1]);
        sppPlugin.updateStages(stages);

        uint256 proposalId = _createProposalAndPassStageZero();

        // Swallow the failure so that the outer call completes and the calls made inside the
        // window can be checked afterwards.
        reentrant.setPropagateFailure(false);
        reentrant.setUpReentrancy({
            _spp: sppPlugin,
            _returnedProposalId: 777,
            _reentrantCalldata: abi.encodeCall(SPP.advanceProposal, (proposalId))
        });

        // The tally stops at the reentrant body's marker, which comes first, so the honest
        // body is never asked about the unwritten zero.
        vm.expectCall(address(honest), abi.encodeCall(IProposal.hasSucceeded, (0)), 0);

        sppPlugin.advanceProposal(proposalId);

        assertFalse(reentrant.reentrantCallSucceeded(), "reentrantCallSucceeded");
        assertEq(
            reentrant.reentrantCallReturnData(),
            _unexpectedStateActive(proposalId),
            "reentrantCallReturnData"
        );

        assertEq(sppPlugin.getProposal(proposalId).currentStage, 1, "currentStage");
        assertFalse(sppPlugin.getProposal(proposalId).executed, "executed");

        // the honest body's real sub-proposal exists now, has id 1 and never succeeded
        assertEq(sppPlugin.getBodyProposalId(proposalId, 1, address(honest)), 1, "honestBodyProposalId");
        assertFalse(honest.hasSucceeded(1), "honestRealSubProposalSucceeded");

        // so the stage does not pass, with or without the window
        assertFalse(sppPlugin.canProposalAdvance(proposalId), "canProposalAdvance");
    }

    function test_WhenSubBodyDoesNotReenterTheLaterBodyIsCountedByItsRealId()
        external
        whenSubBodyReentersDuringAdvance
        whenALaterBodyOnTheStageHasAnOldProposalWithIdZero
    {
        // it should not be advanceable, the same setup gives no approval outside the window.

        _grantProductionPermissions();

        ReentrantPlugin reentrant = new ReentrantPlugin();
        IdAwarePlugin honest = new IdAwarePlugin();
        honest.setSucceeded(0, true);

        SPP.Stage[] memory stages = _createDummyStages(2, false, false, false);
        SPP.Body[] memory stageOneBodies = new SPP.Body[](2);
        stageOneBodies[0] = _createBodyStruct(address(reentrant), false);
        stageOneBodies[1] = _createBodyStruct(address(honest), false);
        stages[1].bodies = stageOneBodies;
        stages[1].approvalThreshold = 2;
        _removeTimeBounds(stages[1]);
        sppPlugin.updateStages(stages);

        uint256 proposalId = _createProposalAndPassStageZero();

        // no call back into SPP, stage one is created normally
        reentrant.setUpReentrancy({
            _spp: sppPlugin,
            _returnedProposalId: 777,
            _reentrantCalldata: ""
        });
        sppPlugin.advanceProposal(proposalId);

        assertEq(sppPlugin.getProposal(proposalId).currentStage, 1, "currentStage");
        assertEq(sppPlugin.getBodyProposalId(proposalId, 1, address(honest)), 1, "honestBodyProposalId");

        // Once the ids are stored the tally asks the honest body about its real
        // sub-proposal, which did not succeed, so the threshold of two is not met.
        vm.expectCall(address(honest), abi.encodeCall(IProposal.hasSucceeded, (1)));
        assertFalse(sppPlugin.canProposalAdvance(proposalId), "canProposalAdvance");

        vm.expectRevert(_unexpectedStateActive(proposalId));
        sppPlugin.advanceProposal(proposalId);

        // and this is not a matter of waiting, there are no time bounds on this stage
        vm.warp(block.timestamp + MIN_ADVANCE + VOTE_DURATION);
        assertFalse(sppPlugin.canProposalAdvance(proposalId), "canProposalAdvanceLater");
        assertFalse(sppPlugin.getProposal(proposalId).executed, "executed");
    }

    modifier givenTheInProgressMarker() {
        _;
    }

    function test_RevertWhen_SubBodyReturnsTheInProgressMarkerAsItsId()
        external
        givenTheInProgressMarker
    {
        // it should reject the sub-proposal, the marker must never be stored as a real id.

        ReentrantPlugin body = new ReentrantPlugin();
        sppPlugin.updateStages(_configureStageOneWith(address(body)));

        uint256 proposalId = _createProposalAndPassStageZero();

        // no reentrancy, the body simply hands out the marker as its id
        body.setUpReentrancy({
            _spp: sppPlugin,
            _returnedProposalId: PROPOSAL_IN_PROGRESS,
            _reentrantCalldata: ""
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.SubProposalCreationFailed.selector,
                address(body),
                bytes("")
            )
        );
        sppPlugin.advanceProposal(proposalId);

        assertEq(sppPlugin.getProposal(proposalId).currentStage, 0, "currentStage");
    }

    function test_WhenSubBodyReturnsTheLegacyFailedMarkerAsItsId()
        external
        givenTheInProgressMarker
    {
        // it should store it as an ordinary id.
        // it should consult the body about that id like any other.
        //
        // Earlier versions stored `type(uint256).max` for sub-proposals that failed to be
        // created, and proposals created before this upgrade may still hold it. It must
        // not read as "in progress", or those proposals could never advance again.

        ReentrantPlugin body = new ReentrantPlugin();
        SPP.Stage[] memory stages = _configureStageOneWith(address(body));
        _removeTimeBounds(stages[1]);
        sppPlugin.updateStages(stages);

        uint256 proposalId = _createProposalAndPassStageZero();

        body.setUpReentrancy({
            _spp: sppPlugin,
            _returnedProposalId: type(uint256).max,
            _reentrantCalldata: ""
        });

        sppPlugin.advanceProposal(proposalId);

        assertEq(
            sppPlugin.getBodyProposalId(proposalId, 1, address(body)),
            type(uint256).max,
            "bodyProposalId"
        );

        // the tally asks about it instead of stopping at it
        vm.expectCall(address(body), abi.encodeCall(IProposal.hasSucceeded, (type(uint256).max)));
        assertTrue(sppPlugin.canProposalAdvance(proposalId), "canProposalAdvance");
    }

    modifier whenStageHasNoThresholdsAtAll() {
        _;
    }

    function test_WhenSubBodyReentersOnAStageWithoutThresholdsItStillAdvancesDuringItsCreation()
        external
        whenSubBodyReentersDuringAdvance
        whenStageHasNoThresholdsAtAll
    {
        // it should execute the proposal from inside the advance that creates its last stage.
        //
        // Documents the one case the marker does not cover. With both thresholds at zero
        // `_thresholdsMet` returns true for any tally, including the failing one the marker
        // produces, so such a stage is advanceable the moment its time bounds allow. Without
        // time bounds that is during its own creation. A stage like this has no vote to
        // protect, so this is accepted rather than fixed.

        _grantProductionPermissions();

        ReentrantPlugin reentrant = new ReentrantPlugin();
        SPP.Stage[] memory stages = _configureStageOneWith(address(reentrant));
        stages[1].approvalThreshold = 0;
        _removeTimeBounds(stages[1]);
        sppPlugin.updateStages(stages);

        uint256 proposalId = _createProposalAndPassStageZero();

        reentrant.setUpReentrancy({
            _spp: sppPlugin,
            _returnedProposalId: 777,
            _reentrantCalldata: abi.encodeCall(SPP.advanceProposal, (proposalId))
        });

        sppPlugin.advanceProposal(proposalId);

        assertTrue(reentrant.reentrantCallSucceeded(), "reentrantCallSucceeded");
        assertTrue(sppPlugin.getProposal(proposalId).executed, "executed");
        assertEq(target.val(), TARGET_VALUE, "targetValue");
        assertEq(sppPlugin.getBodyProposalId(proposalId, 1, address(reentrant)), 777, "bodyProposalId");
    }
}
