// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../BaseTest.t.sol";
import {Errors} from "../../../../src/libraries/Errors.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

contract TrustedForwarder_FuzzyTest is BaseTest {
    function test_AnyoneCanExecute(address _randomAddress) external {
        // it should no revert.

        assumeNotPrecompile(_randomAddress);
        resetPrank(_randomAddress);

        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0] = IDAO.Action({
            to: address(target),
            value: 0,
            data: abi.encodeWithSelector(target.setValue.selector, TARGET_VALUE)
        });
        trustedForwarder.execute(DUMMY_CALL_ID, actions, 0);
    }
}
