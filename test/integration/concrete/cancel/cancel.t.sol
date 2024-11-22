// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {BaseTest} from "../../../BaseTest.t.sol";
import {Errors} from "../../../../src/libraries/Errors.sol";
import {Permissions} from "../../../../src/libraries/Permissions.sol";
import {PluginA} from "../../../utils/dummy-plugins/PluginA/PluginA.sol";
import {StagedProposalProcessor as SPP} from "../../../../src/StagedProposalProcessor.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

contract Cancel_SPP_IntegrationTest is BaseTest {
    uint256 proposalId;
    bytes32 validStageBitmap =
        _encodeStateBitmap(SPP.ProposalState.Active) |
            _encodeStateBitmap(SPP.ProposalState.Advanceable);

    modifier whenProposalExists() {
        proposalId = _configureStagesAndCreateDummyProposal(DUMMY_METADATA);
        _;
    }

    modifier whenCallerIsAllowed() {
        resetPrank(users.manager);
        _;
    }

    modifier whenCurrentStageIsCancelable() {
        // turn on cancellable flag and create a new proposal
        cancellable = true;
        proposalId = _configureStagesAndCreateDummyProposal("dummy metadata 1");

        _;
    }

    modifier whenProposalStateIsNeitherActiveNorAdvanceable() {
        _;
    }

    function test_RevertWhen_ProposalIsCancelled()
        external
        whenProposalExists
        whenCallerIsAllowed
        whenCurrentStageIsCancelable
        whenProposalStateIsNeitherActiveNorAdvanceable
    {
        // it should revert.

        sppPlugin.cancel(proposalId);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.UnexpectedProposalState.selector,
                proposalId,
                uint8(SPP.ProposalState.Canceled),
                validStageBitmap
            )
        );
        sppPlugin.cancel(proposalId);
    }

    function test_RevertWhen_ProposalIsExecuted()
        external
        whenProposalExists
        whenCallerIsAllowed
        whenCurrentStageIsCancelable
        whenProposalStateIsNeitherActiveNorAdvanceable
    {
        // it should revert.

        _moveToLastStage();
        sppPlugin.execute(proposalId);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.UnexpectedProposalState.selector,
                proposalId,
                uint8(SPP.ProposalState.Executed),
                validStageBitmap
            )
        );
        sppPlugin.cancel(proposalId);
    }

    function test_RevertWhen_ProposalIsExpired()
        external
        whenProposalExists
        whenCallerIsAllowed
        whenCurrentStageIsCancelable
        whenProposalStateIsNeitherActiveNorAdvanceable
    {
        // it should revert.

        _moveToLastStage();

        // move timestamp to expire proposal
        vm.warp(sppPlugin.getProposal(proposalId).lastStageTransition + MAX_ADVANCE + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.UnexpectedProposalState.selector,
                proposalId,
                uint8(SPP.ProposalState.Expired),
                validStageBitmap
            )
        );
        sppPlugin.cancel(proposalId);
    }

    function test_WhenProposalStateIsActiveOrAdvanceable()
        external
        whenProposalExists
        whenCallerIsAllowed
        whenCurrentStageIsCancelable
    {
        // it should cancel proposal.
        // it should emit ProposalCanceled event.

        // check event emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalCanceled(
            proposalId,
            sppPlugin.getProposal(proposalId).currentStage,
            users.manager
        );

        sppPlugin.cancel(proposalId);

        // check proposal cancelled
        assertTrue(sppPlugin.getProposal(proposalId).canceled, "canceled ");
    }

    function test_RevertWhen_CurrentStageIsNotCancelable()
        external
        whenProposalExists
        whenCallerIsAllowed
    {
        // it should revert.

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ProposalCanNotBeCancelled.selector,
                sppPlugin.getProposal(proposalId).currentStage
            )
        );
        sppPlugin.cancel(proposalId);
    }

    function test_RevertWhen_CallerIsNotAllowed() external whenProposalExists {
        // it should revert.

        resetPrank(users.unauthorized);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(sppPlugin),
                users.unauthorized,
                Permissions.CANCEL_PERMISSION_ID
            )
        );

        sppPlugin.cancel(proposalId);
    }

    function test_RevertWhen_ProposalDoesNotExist() external {
        // it should revert.

        vm.expectRevert(
            abi.encodeWithSelector(Errors.NonexistentProposal.selector, NON_EXISTENT_PROPOSAL_ID)
        );
        sppPlugin.cancel(NON_EXISTENT_PROPOSAL_ID);
    }

    function _moveToLastStage() internal {
        uint256 initialStage;

        // move proposal to last stage to be executable
        // execute proposals on first stage
        _executeStageProposals(initialStage);

        // advance to last stage
        vm.warp(VOTE_DURATION + START_DATE);
        sppPlugin.advanceProposal(proposalId);

        // execute proposals on first stage
        _executeStageProposals(initialStage + 1);

        // advance last stage
        vm.warp(sppPlugin.getProposal(proposalId).lastStageTransition + VOTE_DURATION + START_DATE);
    }
}
