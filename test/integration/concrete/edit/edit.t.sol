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
import {console} from "forge-std/console.sol";

contract Edit_SPP_IntegrationTest is BaseTest {
    uint256 proposalId;
    bytes32 validStageBitmap = _encodeStateBitmap(SPP.ProposalState.Advanceable);
    bytes newMetadata = "dummy metadata 2";

    modifier whenProposalExists() {
        proposalId = _configureStagesAndCreateDummyProposal(DUMMY_METADATA);
        _;
    }

    modifier whenCallerIsAllowed() {
        resetPrank(users.manager);
        _;
    }

    modifier whenCurrentStageIsEditable() {
        // turn on editable flag and create a new proposal
        editable = true;
        cancellable = true; // added for the when proposal is canceled test
        proposalId = _configureStagesAndCreateDummyProposal("dummy metadata 1");
        _;
    }

    modifier whenProposalStateIsNotAdvanceable() {
        _;
    }

    function test_RevertWhen_ProposalIsActive()
        external
        whenProposalExists
        whenCallerIsAllowed
        whenCurrentStageIsEditable
        whenProposalStateIsNotAdvanceable
    {
        // it should revert.
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.UnexpectedProposalState.selector,
                proposalId,
                uint8(SPP.ProposalState.Active),
                validStageBitmap
            )
        );

        sppPlugin.edit(proposalId, newMetadata, _newFancyActions());
    }

    function test_RevertWhen_ProposalIsCancelled()
        external
        whenProposalExists
        whenCallerIsAllowed
        whenCurrentStageIsEditable
        whenProposalStateIsNotAdvanceable
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

        sppPlugin.edit(proposalId, newMetadata, _newFancyActions());
    }

    function test_RevertWhen_ProposalIsExecuted()
        external
        whenProposalExists
        whenCallerIsAllowed
        whenCurrentStageIsEditable
        whenProposalStateIsNotAdvanceable
    {
        // it should revert.

        _moveToLastStage(proposalId);
        sppPlugin.execute(proposalId);

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.UnexpectedProposalState.selector,
                proposalId,
                uint8(SPP.ProposalState.Executed),
                validStageBitmap
            )
        );
        sppPlugin.edit(proposalId, newMetadata, _newFancyActions());
    }

    function test_RevertWhen_ProposalIsExpired()
        external
        whenProposalExists
        whenCallerIsAllowed
        whenCurrentStageIsEditable
        whenProposalStateIsNotAdvanceable
    {
        // it should revert.

        _moveToLastStage(proposalId);

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
        sppPlugin.edit(proposalId, newMetadata, _newFancyActions());
    }

    function test_WhenProposalStateIsAdvanceable()
        external
        whenProposalExists
        whenCallerIsAllowed
        whenCurrentStageIsEditable
    {
        // it should update actions.
        // it should emit ProposalEdited event.

        // execute proposals on stage 0 and advance timestamp to make it advanceable
        _executeStageProposals(0);
        vm.warp(VOTE_DURATION + START_DATE);

        assertEq(
            uint8(sppPlugin.state(proposalId)),
            uint8(SPP.ProposalState.Advanceable),
            "advanceable"
        );

        // check event emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalEdited(
            proposalId,
            sppPlugin.getProposal(proposalId).currentStage,
            users.manager,
            newMetadata,
            _newFancyActions()
        );

        sppPlugin.edit(proposalId, newMetadata, _newFancyActions());
    }

    function test_RevertWhen_CurrentStageIsNotEditable()
        external
        whenProposalExists
        whenCallerIsAllowed
    {
        // it should revert.

        // execute proposals on stage 0 and advance timestamp to make it advanceable
        _executeStageProposals(0);
        vm.warp(VOTE_DURATION + START_DATE);

        assertEq(
            uint8(sppPlugin.state(proposalId)),
            uint8(SPP.ProposalState.Advanceable),
            "advanceable"
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ProposalCanNotBeEdited.selector,
                proposalId,
                sppPlugin.getProposal(proposalId).currentStage
            )
        );
        sppPlugin.edit(proposalId, newMetadata, _newFancyActions());
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
                Permissions.EDIT_PERMISSION_ID
            )
        );

        sppPlugin.edit(proposalId, newMetadata, _newFancyActions());
    }

    function test_RevertWhen_ProposalDoesNotExist() external {
        // it should revert.

        vm.expectRevert(
            abi.encodeWithSelector(Errors.NonexistentProposal.selector, NON_EXISTENT_PROPOSAL_ID)
        );
        sppPlugin.edit(proposalId, newMetadata, _newFancyActions());
    }

    function _newFancyActions() internal pure returns (Action[] memory actions) {
        actions = new Action[](2);
        actions[0] = Action({to: address(1), value: 1, data: abi.encode(0x1234)});
        actions[1] = Action({to: address(2), value: 2, data: abi.encode(0x5678)});
    }
}
