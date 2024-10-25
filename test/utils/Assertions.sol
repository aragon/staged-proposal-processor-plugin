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
    function assertEq(SPP.Stage[] memory a, SPP.Stage[] memory b, string memory err) internal {
        if (keccak256(abi.encode(a)) != keccak256(abi.encode(b))) {
            emit log_named_string("Error, a == b not satisfied [SPP.Stage[]]", err);
            emit log_named_array("   Left", a);
            emit log_named_array("  Right", b);
            fail();
        }
    }

    /// @dev Compares two {SPP.Proposal} struct entities.
    function assertEq(SPP.Proposal memory a, SPP.Proposal memory b, string memory err) internal {
        assertEq(
            a.allowFailureMap,
            b.allowFailureMap,
            string(abi.encodePacked(err, ".allowFailureMap"))
        );
        assertEq(
            a.lastStageTransition,
            b.lastStageTransition,
            string(abi.encodePacked(err, ".lastStageTransition"))
        );
        assertEq(a.currentStage, b.currentStage, string(abi.encodePacked(err, ".currentStage")));
        assertEq(
            a.stageConfigIndex,
            b.stageConfigIndex,
            string(abi.encodePacked(err, ".stageConfigIndex"))
        );
        assertEq(a.executed, b.executed, string(abi.encodePacked(err, ".executed")));
        assertEq(a.actions, b.actions, string(abi.encodePacked(err, ".actions")));
    }

    /// @dev Compares two {Action} arrays.
    function assertEq(Action[] memory a, Action[] memory b, string memory err) internal {
        if (keccak256(abi.encode(a)) != keccak256(abi.encode(b))) {
            emit log_named_string("Error, a == b not satisfied [Action[]]", err);
            emit log_named_array("   Left", a);
            emit log_named_array("  Right", b);
            fail();
        }
    }

    // @dev Compares two {bytes[][]} arrays.
    function assertEq(bytes[][] memory a, bytes[][] memory b, string memory err) internal {
        if (keccak256(abi.encode(a)) != keccak256(abi.encode(b))) {
            emit log_named_string("Error, a == b not satisfied [bytes[][]]", err);
            emit log_named_array("   Left", a);
            emit log_named_array("  Right", b);
            fail();
        }
    }

    // @dev Compares two SPP.ResultType enums.
    function assertEq(SPP.ResultType a, SPP.ResultType b, string memory err) internal {
        if (a != b) {
            emit log_named_string("Error, a == b not satisfied [SPP.ResultType]", err);
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
