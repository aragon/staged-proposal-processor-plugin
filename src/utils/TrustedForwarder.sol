// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {Errors} from "../libraries/Errors.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

contract TrustedForwarder {
    // We use array of actions even though we always revert with > 1
    // This is to allow compatibility as plugins call `execute` with multiple actions.
    function execute(
        bytes32 _callId,
        Action[] calldata _actions,
        uint256 _allowFailureMap
    )
        external
        returns (
            // TODO: can we not restrict _actions.length != 1 ? in that case, tokenvoting's actions can be length of 2
            // which will call two different multibody's at the same time - i.e tokenvoting can belong to 2 different
            // multibodies at the same time. Though if so, Executor has to be global otherwise if M1 and M2 have
            // different executors(ex1 and ex2), TokenVoting will either have ex1 or ex2 set on it. If ex1,
            // it will call ex1.execute and in case we do snapshots, ex1 will only be able to get a timestamp
            // of M1 and this brings problems.
            // NOTE THAT we don't need auth permission here. We allow everyone
            // to be able to call this contract. If some contract that is not already in stages in Multibody,
            // Multibody will anyways reject it as `msg.sender` appended won't be the valid one.
            bytes[] memory execResults,
            uint256 failureMap
        )
    {
        (_callId, _allowFailureMap, failureMap, execResults);
        if (_actions.length != 1) {
            revert Errors.NotPossible();
        }

        // append msg.sender in the end of the actual calldata
        bytes memory callData = abi.encodePacked(_actions[0].data, msg.sender);

        // TODO: GIORGI might need to emit the results
        (bool success, ) = _actions[0].to.call{value: _actions[0].value}(callData);

        // todo do something if success is false
        success;
    }
}
