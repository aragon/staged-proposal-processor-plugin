// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {StdAssertions} from "forge-std/StdAssertions.sol";

import {StagedProposalProcessor as SPP} from "../../src/StagedProposalProcessor.sol";
import {SPPRuleCondition} from "../../src/utils/SPPRuleCondition.sol";

import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

abstract contract Assertions is StdAssertions {
    event log_named_array(string key, SPP.Stage[] stage);
    event log_named_array(string key, Action[] action);
    event log_named_array(string key, bytes[][] value);
    event log_named_array(string key, SPP.ResultType value);
    event log_named_array(string key, SPPRuleCondition.Rule[] value);
    event log_named_array(string key, SPP.Proposal value);

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
        if (keccak256(abi.encode(a)) != keccak256(abi.encode(b))) {
            emit log_named_string("Error, a == b not satisfied [SPP.Proposal]", err);
            emit log_named_array("   Left", a);
            emit log_named_array("  Right", b);
            fail();
        }
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

    // @dev Compares two SPPRuleCondition.Rules.
    function assertEq(
        SPPRuleCondition.Rule[] memory a,
        SPPRuleCondition.Rule[] memory b,
        string memory err
    ) internal {
        if (keccak256(abi.encode(a)) != keccak256(abi.encode(b))) {
            emit log_named_string("Error, a == b not satisfied [SPPRuleCondition.Rule[]]", err);
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
