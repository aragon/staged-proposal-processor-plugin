// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../BaseTest.t.sol";

import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

contract TrustedForwarder_FuzzyTest is BaseTest {
    function test_AnyoneCanExecute(address _randomAddress) external {
        // it should no revert.

        assumeNotPrecompile(_randomAddress);
        resetPrank(_randomAddress);

        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            to: address(target),
            value: 0,
            data: abi.encodeWithSelector(target.setValue.selector, TARGET_VALUE)
        });
        trustedForwarder.execute(DUMMY_CALL_ID, actions, 0);
    }
}
