// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {Errors} from "../libraries/Errors.sol";

import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

/// @notice DON'T USE IN PRODUCTION.
/// @dev This contract is used for testing purposes only.
contract TrustedForwarder {
    // We use array of actions even though we always revert with > 1
    // This is to allow compatibility as plugins call `execute` with multiple actions.
    function execute(
        bytes32 _callId,
        Action[] calldata _actions,
        uint256 _allowFailureMap
    ) external returns (bytes[] memory execResults, uint256 failureMap) {
        (_callId, _allowFailureMap, failureMap, execResults);
        if (_actions.length != 1) {
            revert Errors.IncorrectActionCount();
        }

        // append msg.sender in the end of the actual calldata
        bytes memory callData = abi.encodePacked(_actions[0].data, msg.sender);

        (bool success, ) = _actions[0].to.call{value: _actions[0].value}(callData);

        success;
    }
}
