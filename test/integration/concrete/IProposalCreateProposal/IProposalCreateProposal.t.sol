// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Permissions} from "../../../../src/libraries/Permissions.sol";
import {StagedConfiguredSharedTest} from "../../../StagedConfiguredSharedTest.t.sol";

import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

contract IProposal_CreateProposal_SPP_IntegrationTest is StagedConfiguredSharedTest {
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

    modifier whenCallerIsAllowed() {
        _;
    }

    function test_WhenDataCanBeDecoded() external whenCallerIsAllowed {
        // it should call the createProposal function.
        // it should create the proposal.

        bytes memory data = abi.encode(new bytes[][](0));

        // todo this function is not working with internal functions, wait for foundry support response.
        // check function call was made
        // vm.expectCall({
        //     callee: address(sppPlugin),
        //     data: abi.encodeCall(
        //         sppPlugin.createProposal,
        //         (DUMMY_METADATA, new Action[](0), 0, START_DATE, abi.decode(data, (bytes[][])))
        //     ),
        //     count: 0
        // });

        uint256 proposalId = sppPlugin.createProposal(
            DUMMY_METADATA,
            new Action[](0),
            START_DATE,
            START_DATE + 1,
            data
        );

        // check proposal exists
        assertNotEq(sppPlugin.getProposal(proposalId).lastStageTransition, 0);
    }

    function test_RevertWhen_DataCanNotBeDecoded() external whenCallerIsAllowed {
        // it should revert.

        bytes memory data = "";
        vm.expectRevert();
        sppPlugin.createProposal(DUMMY_METADATA, new Action[](0), START_DATE, START_DATE + 1, data);
    }
}
