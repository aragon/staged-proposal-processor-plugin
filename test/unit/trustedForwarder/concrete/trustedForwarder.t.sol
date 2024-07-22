// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../BaseTest.t.sol";
import {Errors} from "../../../../src/libraries/Errors.sol";

import {IDAO} from "@aragon/osx-commons-contracts-new/src/dao/IDAO.sol";

contract TrustedForwarder_UnitTest is BaseTest {
    function test_RevertWhen_MoreThanOneActionIsExecuted() external {
        // it should revert.
        vm.expectRevert(abi.encodeWithSelector(Errors.NotPossible.selector));
        trustedForwarder.execute(DUMMY_CALL_ID, _createDummyActions(), 0);
    }

    function test_WhenTheActionIsCorrect() external {
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0] = IDAO.Action({
            to: address(target),
            value: 0,
            data: abi.encodeWithSelector(target.setValue.selector, TARGET_VALUE)
        });
        trustedForwarder.execute(DUMMY_CALL_ID, actions, 0);

        // it should execute correctly.
        assertEq(target.val(), TARGET_VALUE);
        // it return correct data.
        // todo currently the return values are not being set
    }

    function test_WhenTheActionIsIncorrect() external {
        // todo TBD
        // it should not execute.
        // it should return correct data.
        vm.skip(true);
    }
}
