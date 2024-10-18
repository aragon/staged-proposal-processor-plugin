// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import {BaseTest} from "../../../BaseTest.t.sol";
import {Errors} from "../../../../src/libraries/Errors.sol";

contract TrustedForwarder_UnitTest is BaseTest {
    function test_RevertWhen_MoreThanOneActionIsExecuted() external {
        // it should revert.

        vm.expectRevert(abi.encodeWithSelector(Errors.IncorrectActionCount.selector));
        trustedForwarder.execute(DUMMY_CALL_ID, _createDummyActions(), 0);
    }

    function test_WhenTheActionIsCorrect() external {
        // it should execute correctly.
        // it return correct data.

        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            to: address(target),
            value: 0,
            data: abi.encodeWithSelector(target.setValue.selector, TARGET_VALUE)
        });
        trustedForwarder.execute(DUMMY_CALL_ID, actions, 0);

        assertEq(target.val(), TARGET_VALUE);
        // todo currently the return values are not being set
    }

    function test_WhenTheActionIsIncorrect() external {
        // todo TBD
        // it should not execute.
        // it should return correct data.
        vm.skip(true);
    }
}
