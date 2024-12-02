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

contract Execute_SPP_IntegrationTest is BaseTest {
    uint256 proposalId;

    modifier whenProposalExists() {
        proposalId = _configureStagesAndCreateDummyProposal(DUMMY_METADATA);

        _;
    }

    modifier whenCallerIsAllowed() {
        resetPrank(users.manager);
        _;
    }

    function test_WhenProposalCanExecute() external whenProposalExists whenCallerIsAllowed {
        // it should emit event.
        // it should execute proposal.

        _moveToLastStage(proposalId);

        // check event emitted
        vm.expectEmit({emitter: address(sppPlugin)});
        emit ProposalExecuted(proposalId);

        sppPlugin.execute(proposalId);

        // check proposal executed
        assertTrue(sppPlugin.getProposal(proposalId).executed, "executed");

        // check actions executed
        assertEq(target.val(), TARGET_VALUE, "targetValue");
        assertEq(target.ctrAddress(), TARGET_ADDRESS, "ctrAddress");
    }

    function test_RevertWhen_ProposalCanNotExecute()
        external
        whenProposalExists
        whenCallerIsAllowed
    {
        // it should revert.

        vm.expectRevert(
            abi.encodeWithSelector(Errors.ProposalExecutionForbidden.selector, proposalId)
        );
        sppPlugin.execute(proposalId);
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
                Permissions.EXECUTE_PROPOSAL_PERMISSION_ID
            )
        );

        sppPlugin.execute(proposalId);
    }

    function test_RevertWhen_ProposalDoesNotExist() external {
        // it should revert.

        vm.expectRevert(
            abi.encodeWithSelector(Errors.NonexistentProposal.selector, NON_EXISTENT_PROPOSAL_ID)
        );
        sppPlugin.execute(NON_EXISTENT_PROPOSAL_ID);
    }
}
