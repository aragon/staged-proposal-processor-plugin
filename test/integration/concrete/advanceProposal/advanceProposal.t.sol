// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../BaseTest.t.sol";
import {Errors} from "../../../../src/libraries/Errors.sol";
import {PluginA} from "../../../utils/dummy-plugins/PluginA.sol";
import {StagedProposalProcessor as SPP} from "../../../../src/StagedProposalProcessor.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

contract AdvanceProposal_SPP_IntegrationTest is BaseTest {
    function test_RevertWhen_CallerIsNotAllowed() external {
        // it should revert.

        // revoke permission
        DAO(payable(address(dao))).revoke({
            _where: address(sppPlugin),
            _who: ANY_ADDR,
            _permissionId: sppPlugin.ADVANCE_PROPOSAL_PERMISSION_ID()
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(sppPlugin),
                users.manager,
                sppPlugin.ADVANCE_PROPOSAL_PERMISSION_ID()
            )
        );
        sppPlugin.advanceProposal(NON_EXISTENT_PROPOSAL_ID);
    }

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

    function test_WhenSomeProposalsOnNextStageAreNonManual()
        external
        givenProposalExists
        whenProposalCanAdvance
        whenProposalIsNotInLastStage
    {
        // it should emit events.
        // it should advance proposal.
        // it should create sub proposals.

        // configure stages (one of them non-manual)
        SPP.Stage[] memory stages = _createDummyStages(2, false, true, false);
        sppPlugin.updateStages(stages);

        // create proposal
        IDAO.Action[] memory actions = _createDummyActions();
        uint256 proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _data: defaultCreationParams
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

        // check sub proposal created
        assertEq(
            PluginA(stages[initialStage + 1].plugins[0].pluginAddress).proposalCount(),
            1,
            "proposalsCount"
        );
    }

    function test_WhenAllProposalOnNextStageAreManual()
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
        IDAO.Action[] memory actions = _createDummyActions();
        uint256 proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _data: defaultCreationParams
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
        // todo TBD
        // it should revert
        vm.skip(true);
    }

    function test_RevertGiven_ProposalDoesNotExist() external {
        // it should revert

        vm.expectRevert(
            abi.encodeWithSelector(Errors.ProposalNotExists.selector, NON_EXISTENT_PROPOSAL_ID)
        );
        sppPlugin.advanceProposal(NON_EXISTENT_PROPOSAL_ID);
    }
}
