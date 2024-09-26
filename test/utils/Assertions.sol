// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {StagedProposalProcessor as SPP} from "../../src/StagedProposalProcessor.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

import {StdAssertions} from "forge-std/StdAssertions.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";

abstract contract Assertions is StdAssertions {
    event log_named_array(string key, SPP.Stage[] stage);
    event log_named_array(string key, IDAO.Action[] action);
    event log_named_array(string key, bytes[][] value);

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
        assertEq(a.creator, b.creator, "creator");
        assertEq(a.lastStageTransition, b.lastStageTransition, "lastStageTransition");
        assertEq(a.metadata, b.metadata, "metadata");
        assertEq(a.currentStage, b.currentStage, "currentStage");
        assertEq(a.stageConfigIndex, b.stageConfigIndex, "stageConfigIndex");
        assertEq(a.executed, b.executed, "executed");
        assertEq(a.actions, b.actions);
    }

    /// @dev Compares two {IDAO.Action} arrays.
    function assertEq(IDAO.Action[] memory a, IDAO.Action[] memory b) internal {
        if (keccak256(abi.encode(a)) != keccak256(abi.encode(b))) {
            emit log("Error: a == b not satisfied [IDAO.Action[]]");
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
}
