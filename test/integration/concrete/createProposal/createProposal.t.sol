// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../BaseTest.t.sol";
import {Errors} from "../../../../src/libraries/Errors.sol";
import {PluginA} from "../../../utils/dummy-plugins/PluginA.sol";
import {PluginC} from "../../../utils/dummy-plugins/PluginC.sol";
import {StagedProposalProcessor as SPP} from "../../../../src/StagedProposalProcessor.sol";

import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

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
                sppPlugin.CREATE_PROPOSAL_PERMISSION_ID()
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

    function test_WhenSubProposalCanNotBeCreated()
        external
        whenStagesAreConfigured
        whenProposalDoesNotExist
        givenAllPluginsOnStageZeroAreNonManual
    {
        // todo TBD that event is not being emitted currently.
        // it should emit an event.
        // it should store uint max value as proposal id.

        // set up stages as non manual but not supporting IProposal interface
        SPP.Body[] memory _bodies = new SPP.Body[](1);
        _bodies[0] = _createBodyStruct(address(new PluginC(address(trustedForwarder))), false);
        SPP.Stage[] memory _stages = new SPP.Stage[](1);
        _stages[0] = _createStageStruct(_bodies);
        sppPlugin.updateStages(_stages);

        uint256 proposalId = sppPlugin.createProposal({
            _actions: new Action[](0),
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });

        // check sub proposal was not created and the id is max uint256
        uint256 subProposalId = sppPlugin.bodyProposalIds(proposalId, 0, _bodies[0].addr);

        assertEq(subProposalId, type(uint256).max, "subProposalId");
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
        SPP.Stage[] memory stages = sppPlugin.getStages();
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
                uint256 subProposalId = sppPlugin.bodyProposalIds(
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
        PluginA(sppPlugin.getStages()[0].bodies[1].addr).setNeedExtraParams(true);
        PluginA(sppPlugin.getStages()[0].bodies[0].addr).setNeedExtraParams(true);

        _;
    }

    function test_WhenExtraParamsAreNotProvided()
        external
        whenStagesAreConfigured
        whenProposalDoesNotExist
        givenAllPluginsOnStageZeroAreNonManual
        whenSubProposalCanBeCreated
        whenSomeSubProposalNeedExtraParams
    {
        // it should create proposal.
        // it should not create sub proposals since extra param was not provided.
        // it should not store extra params.

        Action[] memory actions = _createDummyActions();

        uint256 proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
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
                targetConfig: IPlugin.TargetConfig({
                    target: address(trustedForwarder),
                    operation: IPlugin.Operation.Call
                })
            }),
            "proposal"
        );

        // check sub proposals on stage zero, they should not be created
        SPP.Stage[] memory stages = sppPlugin.getStages();
        SPP.Body memory _currentPlugin;
        uint256 _currentPluginProposalsCount;
        for (uint256 i; i < stages[0].bodies.length; i++) {
            _currentPlugin = stages[0].bodies[i];
            _currentPluginProposalsCount = PluginA(_currentPlugin.addr).proposalCount();

            // should not be created since the extra params are not provided
            assertEq(_currentPluginProposalsCount, 0, "proposalsCount");

            // check sub proposal invalid id was stored
            uint256 subProposalId = sppPlugin.bodyProposalIds(proposalId, 0, _currentPlugin.addr);

            assertEq(subProposalId, type(uint256).max, "subProposalId");
        }

        // check sub proposals on non zero stage
        for (uint256 i; i < stages[1].bodies.length; i++) {
            _currentPlugin = stages[1].bodies[i];
            assertEq(PluginA(_currentPlugin.addr).proposalCount(), 0, "proposalsCount");
        }

        // check extra params was not stored since was not provided.
        for (uint256 i; i < stages.length; i++) {
            for (uint256 j; j < stages[i].bodies.length; j++) {
                assertEq(sppPlugin.getCreateProposalParams(proposalId, uint16(i), j), bytes(""));
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
                targetConfig: IPlugin.TargetConfig({
                    target: address(trustedForwarder),
                    operation: IPlugin.Operation.Call
                })
            }),
            "proposal"
        );

        // check sub proposals on stage zero
        SPP.Stage[] memory stages = sppPlugin.getStages();
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
                uint256 subProposalId = sppPlugin.bodyProposalIds(
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
                targetConfig: IPlugin.TargetConfig({
                    target: address(trustedForwarder),
                    operation: IPlugin.Operation.Call
                })
            }),
            "proposal"
        );

        // check sub proposals on stage zero
        SPP.Stage[] memory stages = sppPlugin.getStages();
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
                uint256 subProposalId = sppPlugin.bodyProposalIds(
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

    function test_WhenExtraParamsAreProvidedButNotEnoughParams1()
        external
        whenStagesAreConfigured
        whenProposalDoesNotExist
        givenAllPluginsOnStageZeroAreNonManual
        whenSubProposalCanBeCreated
        whenSomeSubProposalNeedExtraParams
    {
        // it should emit events.
        // it should create parent proposal.
        // it should not create sub proposals since extra param was not provided.
        // it should not create sub proposals on non zero stages.

        Action[] memory actions = _createDummyActions();

        // create custom params
        bytes[][] memory customCreationParam = new bytes[][](2);
        // the stage has two plugins but set extra params only for first one
        customCreationParam[0] = new bytes[](1);
        customCreationParam[0][0] = abi.encodePacked("data1");
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
                targetConfig: IPlugin.TargetConfig({
                    target: address(trustedForwarder),
                    operation: IPlugin.Operation.Call
                })
            }),
            "proposal"
        );

        // check sub proposals on stage zero, first one should be created second one not
        SPP.Stage[] memory stages = sppPlugin.getStages();

        // stage zero first sub proposal should be created, the extra params were provided
        address _stageZeroFirstPlugin = stages[0].bodies[0].addr;
        uint256 _currentPluginProposalsCount = PluginA(_stageZeroFirstPlugin).proposalCount();

        // should not be created since the extra params are not provided
        assertEq(_currentPluginProposalsCount, 1, "proposalsCount");

        // check sub proposal invalid id was stored
        assertEq(
            sppPlugin.bodyProposalIds(proposalId, 0, _stageZeroFirstPlugin),
            _currentPluginProposalsCount - 1,
            "subProposalId"
        );

        // stage zero second sub proposal should not be created, the extra params were not provided
        address _stageZeroSecondPlugin = stages[0].bodies[1].addr;

        // should not be created since the extra params are not provided
        assertEq(PluginA(_stageZeroSecondPlugin).proposalCount(), 0, "proposalsCount");

        // check sub proposal invalid id was stored
        assertEq(
            sppPlugin.bodyProposalIds(proposalId, 0, _stageZeroSecondPlugin),
            type(uint256).max,
            "subProposalId"
        );

        // check sub proposals on non zero stage
        for (uint256 i; i < stages[1].bodies.length; i++) {
            assertEq(PluginA(stages[1].bodies[i].addr).proposalCount(), 0, "proposalsCount");
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

    function test_GivenStartDateIsInThePast()
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

    function test_GivenStartDateInInTheFuture()
        external
        whenStagesAreConfigured
        whenProposalDoesNotExist
    {
        // it should use block.timestamp for first stage sub proposal startDate.
        // it should use block.timestamp for last stage transition.

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
