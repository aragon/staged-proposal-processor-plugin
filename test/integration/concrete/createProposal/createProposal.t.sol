// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {BaseTest} from "../../../BaseTest.t.sol";
import {Errors} from "../../../../src/libraries/Errors.sol";
import {PluginA} from "../../../utils/dummy-plugins/PluginA/PluginA.sol";
import {PluginC} from "../../../utils/dummy-plugins/PluginC/PluginC.sol";
import {
    MalformedReturnPlugin
} from "../../../utils/dummy-plugins/MalformedReturnPlugin.sol";
import {StagedProposalProcessor as SPP} from "../../../../src/StagedProposalProcessor.sol";
import {Permissions} from "../../../../src/libraries/Permissions.sol";

import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

contract CreateProposal_SPP_IntegrationTest is BaseTest {
    function test_RevertWhen_CallerIsNotAllowed() external {
        // it should revert.

        resetPrank(users.unauthorized);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(sppPlugin),
                users.unauthorized,
                Permissions.CREATE_PROPOSAL_PERMISSION_ID
            )
        );
        sppPlugin.createProposal({
            _actions: new Action[](0),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });
    }

    modifier whenStagesAreConfigured() {
        _;
    }

    function test_RevertWhen_ProposalAlreadyExists() external whenStagesAreConfigured {
        // it should revert.

        // configure stages
        SPP.Stage[] memory stages = _createDummyStages({
            _stageCount: 2,
            _body1Manual: false,
            _body2Manual: false,
            _body3Manual: false
        });
        sppPlugin.updateStages(stages);

        // create proposal
        uint256 proposalId = sppPlugin.createProposal({
            _actions: _createDummyActions(),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.ProposalAlreadyExists.selector, proposalId));
        sppPlugin.createProposal({
            _actions: _createDummyActions(),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });
    }

    modifier whenProposalDoesNotExist() {
        _;
    }

    modifier givenAllPluginsOnStageZeroAreNonManual() {
        SPP.Stage[] memory stages = _createDummyStages({
            _stageCount: 2,
            _body1Manual: false,
            _body2Manual: false,
            _body3Manual: false
        });
        sppPlugin.updateStages(stages);
        _;
    }

    function test_RevertWhen_SubProposalCanNotBeCreated()
        external
        whenStagesAreConfigured
        whenProposalDoesNotExist
        givenAllPluginsOnStageZeroAreNonManual
    {
        // it should revert since the body's `createProposal` always reverts.

        // set up stages as non manual with a body whose `createProposal` always reverts
        SPP.Body[] memory _bodies = new SPP.Body[](1);
        _bodies[0] = _createBodyStruct(address(new PluginC(address(trustedForwarder))), false);
        SPP.Stage[] memory _stages = new SPP.Stage[](1);
        _stages[0] = _createStageStruct(_bodies);
        sppPlugin.updateStages(_stages);

        // the body's revert is rethrown naming the body that failed.
        vm.expectRevert(_subProposalCreationFailed(_bodies[0].addr, "Always reverts"));

        sppPlugin.createProposal({
            _actions: new Action[](0),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });
    }

    function test_RevertWhen_SubBodyRevertsOnCreateProposal()
        external
        whenStagesAreConfigured
        whenProposalDoesNotExist
        givenAllPluginsOnStageZeroAreNonManual
    {
        // it should revert and no proposal should exist.
        // it should roll back the sub proposals created before it.

        // make the second body on stage zero revert when creating the sub proposal
        address secondBody = sppPlugin
        .getStages(sppPlugin.getCurrentConfigIndex())[0].bodies[1].addr;
        PluginA(secondBody).setRevertOnCreateProposal(true);

        vm.expectRevert(_subProposalCreationFailed(secondBody, "revertOnCreateProposal"));

        sppPlugin.createProposal({
            _actions: _createDummyActions(),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });

        // the whole tx reverted, so even the first body's sub proposal was rolled back
        address firstBody = sppPlugin
        .getStages(sppPlugin.getCurrentConfigIndex())[0].bodies[0].addr;
        assertEq(PluginA(firstBody).proposalCount(), 0, "firstBodyProposalsCount");
        assertEq(PluginA(secondBody).proposalCount(), 0, "secondBodyProposalsCount");
    }

    function test_RevertWhen_ParamsWouldSkipTheVetoBody()
        external
        whenStagesAreConfigured
        whenProposalDoesNotExist
    {
        // it should revert rather than create a proposal the veto body can not veto.

        // A stage guarded by a single veto body, as a multisig veto would be configured.
        resultType = SPP.ResultType.Veto;
        vetoThreshold = 1;
        approvalThreshold = 0;

        address vetoBody = address(new PluginA(defaultTargetConfig));
        address otherBody = address(new PluginA(defaultTargetConfig));

        SPP.Body[] memory bodies = new SPP.Body[](2);
        bodies[0] = _createBodyStruct(otherBody, false);
        bodies[1] = _createBodyStruct(vetoBody, false);

        SPP.Stage[] memory stages = new SPP.Stage[](1);
        stages[0] = _createStageStruct(bodies);
        sppPlugin.updateStages(stages);

        // The creator controls the per-body params. Here the veto body is given params it
        // rejects, which would stop its sub-proposal from being created while the rest of
        // the stage is set up normally. If that were tolerated, the veto body would hold no
        // proposal to vote on and could never veto, so the stage would pass unopposed.
        PluginA(vetoBody).setNeedExtraParams(true);

        bytes[][] memory creationParams = new bytes[][](1);
        creationParams[0] = new bytes[](2);
        creationParams[0][0] = abi.encodePacked("data1");
        creationParams[0][1] = new bytes(0);

        vm.expectRevert(_subProposalCreationFailed(vetoBody, "needExtraParams"));

        sppPlugin.createProposal({
            _actions: _createDummyActions(),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: creationParams
        });

        // no sub proposal exists on either body, so the veto body was not bypassed
        assertEq(PluginA(vetoBody).proposalCount(), 0, "vetoBodyProposalsCount");
        assertEq(PluginA(otherBody).proposalCount(), 0, "otherBodyProposalsCount");
    }

    function test_RevertWhen_SubBodyReturnsMalformedData()
        external
        whenStagesAreConfigured
        whenProposalDoesNotExist
        givenAllPluginsOnStageZeroAreNonManual
    {
        // it should revert since the returndata can not be decoded as a uint256.

        // body advertises `IProposal` but returns fewer than the 32 bytes needed to decode
        // a `uint256`. The body itself returns successfully and the caller then reverts on
        // the `returndatasize()` check, which happens outside the `try/catch` around the
        // call. So this is NOT rethrown as `SubProposalCreationFailed` and the revert
        // carries no data naming the offending body.
        SPP.Body[] memory _bodies = new SPP.Body[](1);
        _bodies[0] = _createBodyStruct(address(new MalformedReturnPlugin(31)), false);
        SPP.Stage[] memory _stages = new SPP.Stage[](1);
        _stages[0] = _createStageStruct(_bodies);
        sppPlugin.updateStages(_stages);

        vm.expectRevert(bytes(""));

        sppPlugin.createProposal({
            _actions: new Action[](0),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });

        // control: the same body returning a well-formed 32-byte value succeeds, which
        // pins the revert above to the returndata size and not to anything around it.
        address okBody = address(new MalformedReturnPlugin(32));
        SPP.Body[] memory _okBodies = new SPP.Body[](1);
        _okBodies[0] = _createBodyStruct(okBody, false);
        SPP.Stage[] memory _okStages = new SPP.Stage[](1);
        _okStages[0] = _createStageStruct(_okBodies);
        sppPlugin.updateStages(_okStages);

        uint256 proposalId = sppPlugin.createProposal({
            _actions: new Action[](0),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });

        // the decoded sub-proposal id is the zero word the body returned
        assertEq(sppPlugin.getBodyProposalId(proposalId, 0, okBody), 0, "subProposalId");
    }

    function test_RevertWhen_SubBodyHasNoCode()
        external
        whenStagesAreConfigured
        whenProposalDoesNotExist
        givenAllPluginsOnStageZeroAreNonManual
    {
        // it should revert since a non-manual body must be a contract implementing `IProposal`.

        address eoaBody = makeAddr("eoaBody");

        SPP.Body[] memory _bodies = new SPP.Body[](1);
        _bodies[0] = _createBodyStruct(eoaBody, false);
        SPP.Stage[] memory _stages = new SPP.Stage[](1);
        _stages[0] = _createStageStruct(_bodies);

        // `updateStages` already rejects a non-manual body that does not advertise `IProposal`
        vm.expectRevert(abi.encodeWithSelector(Errors.InterfaceNotSupported.selector));
        sppPlugin.updateStages(_stages);
    }

    modifier whenSubProposalCanBeCreated() {
        _;
    }

    function test_WhenNoneSubProposalNeedExtraParams()
        external
        whenStagesAreConfigured
        whenProposalDoesNotExist
        givenAllPluginsOnStageZeroAreNonManual
        whenSubProposalCanBeCreated
    {
        // it should emit events.
        // it should create proposal.
        // it should create non-manual sub proposals on stage zero.
        // it should store non-manual sub proposal ids.
        // it should not create sub proposals on non zero stages.

        // create proposal
        Action[] memory actions = _createDummyActions();

        // check event
        vm.expectEmit({
            checkTopic1: false,
            checkTopic2: true,
            checkTopic3: true,
            checkData: true,
            emitter: address(sppPlugin)
        });
        emit ProposalCreated({
            proposalId: 0,
            creator: users.manager,
            startDate: START_DATE,
            endDate: 0,
            metadata: DUMMY_METADATA,
            actions: actions,
            allowFailureMap: 0
        });
        uint256 proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });

        // check proposal
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        assertEq(proposal.currentStage, 0, "current stage");
        assertEq(proposal.lastStageTransition, START_DATE, "startDate");
        assertFalse(proposal.executed, "executed");

        // check sub proposals on stage zero
        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());
        SPP.Body memory _currentPlugin;
        uint256 _currentPluginProposalsCount;
        for (uint256 i; i < stages[0].bodies.length; i++) {
            _currentPlugin = stages[0].bodies[i];
            _currentPluginProposalsCount = PluginA(_currentPlugin.addr).proposalCount();
            if (_currentPlugin.isManual) {
                // should not be created since it is manual
                assertEq(_currentPluginProposalsCount, 0, "proposalsCount");
            } else {
                // should be created since it is non-manual
                assertEq(_currentPluginProposalsCount, 1, "proposalsCount");

                // check sub proposal id was stored
                uint256 subProposalId = sppPlugin.getBodyProposalId(
                    proposalId,
                    0,
                    _currentPlugin.addr
                );

                assertEq(subProposalId, _currentPluginProposalsCount - 1, "subProposalId");
            }
        }

        // check sub proposals on non zero stage
        for (uint256 i; i < stages[1].bodies.length; i++) {
            _currentPlugin = stages[1].bodies[i];
            assertEq(PluginA(_currentPlugin.addr).proposalCount(), 0, "proposalsCount");
        }
    }

    modifier whenSomeSubProposalNeedExtraParams() {
        // configure in the body that extra params are needed.
        PluginA(sppPlugin.getStages(sppPlugin.getCurrentConfigIndex())[0].bodies[1].addr)
            .setNeedExtraParams(true);
        PluginA(sppPlugin.getStages(sppPlugin.getCurrentConfigIndex())[0].bodies[0].addr)
            .setNeedExtraParams(true);

        _;
    }

    function test_RevertWhen_ExtraParamsAreNotProvided()
        external
        whenStagesAreConfigured
        whenProposalDoesNotExist
        givenAllPluginsOnStageZeroAreNonManual
        whenSubProposalCanBeCreated
        whenSomeSubProposalNeedExtraParams
    {
        // it should revert since the sub-body reverts when the extra param is not provided.
        // it should not create the proposal.
        // it should not create sub proposals.

        Action[] memory actions = _createDummyActions();

        // the first body on stage zero is the first one to be asked for params, so it is
        // the one that fails and gets named in the rethrown error.
        address failingBody = sppPlugin
        .getStages(sppPlugin.getCurrentConfigIndex())[0].bodies[0].addr;

        vm.expectRevert(_subProposalCreationFailed(failingBody, "needExtraParams"));

        sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });

        // check no sub proposals were created on any stage
        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());
        for (uint256 i; i < stages.length; i++) {
            for (uint256 j; j < stages[i].bodies.length; j++) {
                assertEq(PluginA(stages[i].bodies[j].addr).proposalCount(), 0, "proposalsCount");
            }
        }
    }

    function test_WhenExtraParamsAreProvided()
        external
        whenStagesAreConfigured
        whenProposalDoesNotExist
        givenAllPluginsOnStageZeroAreNonManual
        whenSubProposalCanBeCreated
        whenSomeSubProposalNeedExtraParams
    {
        // it should emit events.
        // it should create proposal.
        // it should create non-manual sub proposals on stage zero with all needed params.
        // it should store non-manual sub proposal ids.
        // it should not create sub proposals on non zero stages.

        Action[] memory actions = _createDummyActions();

        // create custom params
        bytes[][] memory customCreationParam = new bytes[][](2);
        customCreationParam[0] = new bytes[](2);
        customCreationParam[0][0] = abi.encodePacked("data1");
        customCreationParam[0][1] = abi.encodePacked("data2");
        customCreationParam[1] = new bytes[](1);
        customCreationParam[1][0] = abi.encodePacked("data3");

        // check event
        vm.expectEmit({
            checkTopic1: false,
            checkTopic2: true,
            checkTopic3: true,
            checkData: true,
            emitter: address(sppPlugin)
        });
        emit ProposalCreated({
            proposalId: 0,
            creator: users.manager,
            startDate: START_DATE,
            endDate: 0,
            metadata: DUMMY_METADATA,
            actions: actions,
            allowFailureMap: 0
        });

        uint256 proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: customCreationParam
        });

        // check proposal
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        assertEq(
            proposal,
            SPP.Proposal({
                allowFailureMap: 0,
                lastStageTransition: START_DATE,
                actions: actions,
                stageConfigIndex: 1,
                currentStage: 0,
                executed: false,
                canceled: false,
                targetConfig: IPlugin.TargetConfig({
                    target: address(dao),
                    operation: IPlugin.Operation.Call
                }),
                creator: users.manager
            }),
            "proposal"
        );

        // check sub proposals on stage zero
        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());
        SPP.Body memory _currentPlugin;
        uint256 _currentPluginProposalsCount;
        for (uint256 i; i < stages[0].bodies.length; i++) {
            _currentPlugin = stages[0].bodies[i];
            _currentPluginProposalsCount = PluginA(_currentPlugin.addr).proposalCount();
            if (_currentPlugin.isManual) {
                // should not be created since it is manual
                assertEq(_currentPluginProposalsCount, 0, "proposalsCount");
            } else {
                // should be created since it is non-manual
                assertEq(_currentPluginProposalsCount, 1, "proposalsCount");

                // check sub proposal id was stored
                uint256 subProposalId = sppPlugin.getBodyProposalId(
                    proposalId,
                    0,
                    _currentPlugin.addr
                );

                assertEq(subProposalId, _currentPluginProposalsCount - 1, "subProposalId");

                // should set the extra params on sub proposals
                assertEq(
                    PluginA(_currentPlugin.addr).extraParams(subProposalId),
                    customCreationParam[0][i],
                    "extraParams"
                );
            }
        }

        // check sub proposals on non zero stage
        for (uint256 i; i < stages[1].bodies.length; i++) {
            _currentPlugin = stages[1].bodies[i];
            assertEq(PluginA(_currentPlugin.addr).proposalCount(), 0, "proposalsCount");
        }

        // check extra params was not stored since was not provided.
        for (uint256 i = 1; i < stages.length; i++) {
            for (uint256 j; j < stages[i].bodies.length; j++) {
                assertEq(
                    sppPlugin.getCreateProposalParams(proposalId, uint16(i), j),
                    customCreationParam[i][j]
                );
            }
        }
    }

    function test_WhenExtraParamsAreProvidedAndAreBig()
        external
        whenStagesAreConfigured
        whenProposalDoesNotExist
        givenAllPluginsOnStageZeroAreNonManual
        whenSubProposalCanBeCreated
        whenSomeSubProposalNeedExtraParams
    {
        // it should emit events.
        // it should create proposal.
        // it should create non-manual sub proposals on stage zero with all needed params.
        // it should store non-manual sub proposal ids.
        // it should not create sub proposals on non zero stages.

        Action[] memory actions = _createDummyActions();

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

        // check event
        vm.expectEmit({
            checkTopic1: false,
            checkTopic2: true,
            checkTopic3: true,
            checkData: true,
            emitter: address(sppPlugin)
        });
        emit ProposalCreated({
            proposalId: 0,
            creator: users.manager,
            startDate: START_DATE,
            endDate: 0,
            metadata: DUMMY_METADATA,
            actions: actions,
            allowFailureMap: 0
        });

        uint256 proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: customCreationParam
        });

        // check proposal
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        assertEq(
            proposal,
            SPP.Proposal({
                allowFailureMap: 0,
                lastStageTransition: START_DATE,
                actions: actions,
                stageConfigIndex: 1,
                currentStage: 0,
                executed: false,
                canceled: false,
                targetConfig: IPlugin.TargetConfig({
                    target: address(dao),
                    operation: IPlugin.Operation.Call
                }),
                creator: users.manager
            }),
            "proposal"
        );

        // check sub proposals on stage zero
        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());
        SPP.Body memory _currentPlugin;
        uint256 _currentPluginProposalsCount;
        for (uint256 i; i < stages[0].bodies.length; i++) {
            _currentPlugin = stages[0].bodies[i];
            _currentPluginProposalsCount = PluginA(_currentPlugin.addr).proposalCount();
            if (_currentPlugin.isManual) {
                // should not be created since it is manual
                assertEq(_currentPluginProposalsCount, 0, "proposalsCount");
            } else {
                // should be created since it is non-manual
                assertEq(_currentPluginProposalsCount, 1, "proposalsCount");

                // check sub proposal id was stored
                uint256 subProposalId = sppPlugin.getBodyProposalId(
                    proposalId,
                    0,
                    _currentPlugin.addr
                );

                assertEq(subProposalId, _currentPluginProposalsCount - 1, "subProposalId");

                // should set the extra params on sub proposals
                assertEq(
                    PluginA(_currentPlugin.addr).extraParams(subProposalId),
                    customCreationParam[0][i],
                    "extraParams"
                );
            }
        }

        // check sub proposals on non zero stage
        for (uint256 i; i < stages[1].bodies.length; i++) {
            _currentPlugin = stages[1].bodies[i];
            assertEq(PluginA(_currentPlugin.addr).proposalCount(), 0, "proposalsCount");
        }

        // check extra params was not stored since was not provided.
        for (uint256 i = 1; i < stages.length; i++) {
            for (uint256 j; j < stages[i].bodies.length; j++) {
                assertEq(
                    sppPlugin.getCreateProposalParams(proposalId, uint16(i), j),
                    customCreationParam[i][j],
                    "extraParams"
                );
            }
        }
    }

    function test_RevertWhen_ExtraParamsAreProvidedButNotEnoughParams()
        external
        whenStagesAreConfigured
        whenProposalDoesNotExist
        givenAllPluginsOnStageZeroAreNonManual
        whenSubProposalCanBeCreated
        whenSomeSubProposalNeedExtraParams
    {
        // it should revert since the second sub-body gets no extra param and reverts.
        // it should not create the parent proposal.
        // it should not create sub proposals.

        Action[] memory actions = _createDummyActions();

        // create custom params
        bytes[][] memory customCreationParam = new bytes[][](2);
        // the stage has two plugins but set extra params only for first one
        customCreationParam[0] = new bytes[](1);
        customCreationParam[0][0] = abi.encodePacked("data1");
        customCreationParam[1] = new bytes[](1);
        customCreationParam[1][0] = abi.encodePacked("data3");

        // the first body gets `data1`, the second one gets nothing and is the one that fails.
        address failingBody = sppPlugin
        .getStages(sppPlugin.getCurrentConfigIndex())[0].bodies[1].addr;

        vm.expectRevert(_subProposalCreationFailed(failingBody, "needExtraParams"));

        sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: customCreationParam
        });

        // check no sub proposals were created on any stage, the whole tx was reverted
        SPP.Stage[] memory stages = sppPlugin.getStages(sppPlugin.getCurrentConfigIndex());
        for (uint256 i; i < stages.length; i++) {
            for (uint256 j; j < stages[i].bodies.length; j++) {
                assertEq(PluginA(stages[i].bodies[j].addr).proposalCount(), 0, "proposalsCount");
            }
        }
    }

    function test_GivenSomePluginsOnStageZeroAreManual()
        external
        whenStagesAreConfigured
        whenProposalDoesNotExist
    {
        // it should emit events.
        // it should create proposal.
        // it should not create sub proposals on stage zero.
        // it should not create sub proposals on non zero stages.

        // configure stages
        SPP.Stage[] memory stages = _createDummyStages(2, true, true, false);
        sppPlugin.updateStages(stages);

        // create proposal
        Action[] memory actions = _createDummyActions();

        // check event
        vm.expectEmit({
            checkTopic1: false,
            checkTopic2: true,
            checkTopic3: true,
            checkData: true,
            emitter: address(sppPlugin)
        });
        emit ProposalCreated({
            proposalId: 0,
            creator: users.manager,
            startDate: START_DATE,
            endDate: 0,
            metadata: DUMMY_METADATA,
            actions: actions,
            allowFailureMap: 0
        });

        uint256 proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });

        // check proposal
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        assertEq(proposal.currentStage, 0, "current stage");
        assertEq(proposal.lastStageTransition, START_DATE, "startDate");
        assertFalse(proposal.executed, "executed");

        // check no sub proposals created
        SPP.Body memory _currentPlugin;
        for (uint256 i; i < stages[0].bodies.length; i++) {
            _currentPlugin = stages[0].bodies[i];

            assertTrue(_currentPlugin.isManual, "isManual");
            assertEq(PluginA(_currentPlugin.addr).proposalCount(), 0, "proposalCount");
        }

        // check no sub proposals created
        for (uint256 i; i < stages[1].bodies.length; i++) {
            assertEq(PluginA(stages[1].bodies[i].addr).proposalCount(), 0, "proposalCount");
        }
    }

    function test_GivenOnStageZeroThereAreZeroPlugins()
        external
        whenStagesAreConfigured
        whenProposalDoesNotExist
    {
        // it should emit events.
        // it should create proposal.
        // it should not be able to advance until minAdvance.

        // configure stages
        SPP.Stage[] memory stages = _createDummyStages(2, true, true, false);

        // remove bodies from stage 0
        stages[0].bodies = new SPP.Body[](0);
        stages[0].approvalThreshold = 0;
        stages[0].vetoThreshold = 0;

        sppPlugin.updateStages(stages);

        // create proposal
        Action[] memory actions = _createDummyActions();

        // check event
        vm.expectEmit({
            checkTopic1: false,
            checkTopic2: true,
            checkTopic3: true,
            checkData: true,
            emitter: address(sppPlugin)
        });
        emit ProposalCreated({
            proposalId: 0,
            creator: users.manager,
            startDate: START_DATE,
            endDate: 0,
            metadata: DUMMY_METADATA,
            actions: actions,
            allowFailureMap: 0
        });

        uint256 proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });

        // check proposal
        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);
        assertEq(proposal.currentStage, 0, "current stage");
        assertEq(proposal.lastStageTransition, START_DATE, "startDate");
        assertFalse(proposal.executed, "executed");

        // check can not advance
        assertFalse(sppPlugin.canProposalAdvance(proposalId), "canAdvance");

        // check can advance after minAdvance
        vm.warp(START_DATE + minAdvance);
        assertTrue(sppPlugin.canProposalAdvance(proposalId), "canAdvance");
    }

    function test_RevertGiven_StartDateIsInThePast()
        external
        whenStagesAreConfigured
        whenProposalDoesNotExist
    {
        // it should revert.

        // block.timestamp is 3 and startDate is 1  1 < 3
        vm.warp(3);

        // configure stages
        SPP.Stage[] memory stages = _createDummyStages(2, false, false, false);
        sppPlugin.updateStages(stages);

        vm.expectRevert(abi.encodeWithSelector(Errors.StartDateInvalid.selector, 1));
        sppPlugin.createProposal({
            _actions: new Action[](0),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: 1,
            _proposalParams: defaultCreationParams
        });
    }

    function test_GivenStartDateIsInTheFuture()
        external
        whenStagesAreConfigured
        whenProposalDoesNotExist
    {
        // it should use startDate for last stage transition.
        // it should use startDate for first stage sub proposal startDate.

        uint64 _expectedStartDate = START_DATE;

        // configure stages
        SPP.Stage[] memory stages = _createDummyStages(2, false, false, false);
        sppPlugin.updateStages(stages);

        // create proposal
        Action[] memory actions = _createDummyActions();

        // check proposal start date
        SPP.Body memory _currentPlugin;
        for (uint256 i; i < stages[0].bodies.length; i++) {
            _currentPlugin = stages[0].bodies[i];

            vm.expectEmit({emitter: _currentPlugin.addr});
            emit ProposalCreated({
                proposalId: 0,
                startDate: _expectedStartDate,
                endDate: _expectedStartDate + stages[0].voteDuration
            });
        }

        uint256 proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        // check proposal last stage transition
        assertEq(proposal.lastStageTransition, _expectedStartDate, "lastStageTransition");
    }

    function test_GivenStartDateIsZero() external whenStagesAreConfigured whenProposalDoesNotExist {
        // it should use block.timestamp for last stage transition.
        // it should use block.timestamp for first stage sub proposal startDate.
        uint64 _expectedStartDate = uint64(block.timestamp);
        uint64 _startDate = 0;

        // configure stages
        SPP.Stage[] memory stages = _createDummyStages(2, false, false, false);
        sppPlugin.updateStages(stages);

        // create proposal
        Action[] memory actions = _createDummyActions();

        // check proposal start date
        SPP.Body memory _currentPlugin;
        for (uint256 i; i < stages[0].bodies.length; i++) {
            _currentPlugin = stages[0].bodies[i];

            vm.expectEmit({emitter: _currentPlugin.addr});
            emit ProposalCreated({
                proposalId: 0,
                startDate: _expectedStartDate,
                endDate: _expectedStartDate + stages[0].voteDuration
            });
        }

        uint256 proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: _startDate,
            _proposalParams: defaultCreationParams
        });

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        // check proposal last stage transition
        assertEq(proposal.lastStageTransition, _expectedStartDate, "lastStageTransition");
    }

    function test_RevertWhen_StagesAreNotConfigured() external {
        // it should revert.

        vm.expectRevert(abi.encodeWithSelector(Errors.StageCountZero.selector));
        sppPlugin.createProposal({
            _actions: new Action[](0),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });
    }
}
