// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {StagedProposalProcessor as SPP} from "../../src/StagedProposalProcessor.sol";

import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import {StdAssertions} from "forge-std/StdAssertions.sol";

abstract contract Assertions is StdAssertions {
    event log_named_array(string key, SPP.Stage[] stage);
    event log_named_array(string key, Action[] action);
    event log_named_array(string key, bytes[][] value);
    event log_named_array(string key, SPP.ResultType value);

    /// @dev Compares two {SPP.Stage} arrays.
    function assertEq(SPP.Stage[] memory a, SPP.Stage[] memory b) internal {
        if (keccak256(abi.encode(a)) != keccak256(abi.encode(b))) {
            emit log("Error: a == b not satisfied [SPP.Stage[]]");
            emit log_named_array("   Left", a);
            emit log_named_array("  Right", b);
            fail();
        }
    }

    /// @dev Compares two {SPP.Proposal} struct entities.
    function assertEq(SPP.Proposal memory a, SPP.Proposal memory b) internal {
        assertEq(a.allowFailureMap, b.allowFailureMap, "allowFailureMap");
        assertEq(a.lastStageTransition, b.lastStageTransition, "lastStageTransition");
        assertEq(a.currentStage, b.currentStage, "currentStage");
        assertEq(a.stageConfigIndex, b.stageConfigIndex, "stageConfigIndex");
        assertEq(a.executed, b.executed, "executed");
        assertEq(a.actions, b.actions);
    }

    /// @dev Compares two {Action} arrays.
    function assertEq(Action[] memory a, Action[] memory b) internal {
        if (keccak256(abi.encode(a)) != keccak256(abi.encode(b))) {
            emit log("Error: a == b not satisfied [Action[]]");
            emit log_named_array("   Left", a);
            emit log_named_array("  Right", b);
            fail();
        }
    }

    // @dev Compares two {bytes[][]} arrays.
    function assertEq(bytes[][] memory a, bytes[][] memory b) internal {
        if (keccak256(abi.encode(a)) != keccak256(abi.encode(b))) {
            emit log("Error: a == b not satisfied [bytes[][]]");
            emit log_named_array("   Left", a);
            emit log_named_array("  Right", b);
            fail();
        }
    }

    // @dev Compares two SPP.ResultType enums.
    function assertEq(SPP.ResultType a, SPP.ResultType b) internal {
        if (a != b) {
            emit log("Error: a == b not satisfied [SPP.ResultType]");
            emit log_named_array("   Left", a);
            emit log_named_array("  Right", b);
            fail();
        }
    }

    function assertValueInList(bytes32 value, bytes32[] memory list, string memory err) internal {
        for (uint256 i = 0; i < list.length; ++i) {
            if (list[i] == value) {
                return;
            }
        }
        emit log_named_string("Error, value not found in list", err);
        fail();
    }
}
