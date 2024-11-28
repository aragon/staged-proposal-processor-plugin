// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {BaseTest} from "../../../../BaseTest.t.sol";
import {SppHarness} from "../../../../utils/harness/SppHarness.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";

import {
    RuledCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/extensions/RuledCondition.sol";

contract MsgData_SPP_UnitTest is BaseTest {
    SppHarness sppHarness;

    function setUp() public override {
        super.setUp();

        // create spp harness

        sppHarness = SppHarness(
            createProxyAndCall(
                address(new SppHarness()),
                abi.encodeCall(
                    SPP.initialize,
                    (
                        dao,
                        address(trustedForwarder),
                        new SPP.Stage[](0),
                        DUMMY_METADATA,
                        defaultTargetConfig
                    )
                )
            )
        );
    }

    modifier whenCallerIsTrustedForwarder() {
        resetPrank(address(trustedForwarder));
        _;
    }

    function test_WhenCalldataLengthIsGreaterThan20Bytes() external whenCallerIsTrustedForwarder {
        // it should return the calldata without the appended address.

        uint256 dataValue = type(uint256).max;
        bytes memory data = abi.encodePacked(
            SppHarness.exposed_msgData.selector,
            dataValue,
            trustedForwarder
        );

        // check the data length is greater than 20 bytes
        assertGt(data.length, 20, "data-length");

        (bool success, bytes memory returnData) = address(sppHarness).call(data);

        // fists 4 bytes is the signature, rest is the datavalue
        bytes memory msgData = abi.decode(returnData, (bytes));

        bytes32 msgDataFinalBytes;
        assembly {
            msgDataFinalBytes := mload(add(msgData, add(0x20, 0x04)))
        }

        assertTrue(success, "success");
        assertEq(msgData.length, data.length - 20, "msgData-length");
        assertEq(bytes4(msgData), SppHarness.exposed_msgData.selector, "selector");
        // check msgData final bytes are dataValue
        assertEq(uint256(msgDataFinalBytes), dataValue, "value");
    }

    function test_WhenCalldataLengthIsLessThan20Bytes() external whenCallerIsTrustedForwarder {
        // it should return the original calldata.

        uint16 dataValue = type(uint16).max;
        bytes memory data = abi.encodePacked(SppHarness.exposed_msgData.selector, dataValue);

        // check the data length is lower than 20 bytes
        assertLt(data.length, 20, "data-length");

        (bool success, bytes memory returnData) = address(sppHarness).call(data);

        // fists 4 bytes is the signature, rest is the datavalue
        bytes memory msgData = abi.decode(returnData, (bytes));

        bytes2 msgDataFinalBytes;
        assembly {
            msgDataFinalBytes := mload(add(msgData, add(0x20, 0x04)))
        }

        assertTrue(success, "success");
        assertEq(msgData.length, data.length, "msgData-length");
        assertEq(bytes4(msgData), SppHarness.exposed_msgData.selector, "selector");
        // check msgData final bytes are dataValue
        assertEq(uint16(bytes2(msgDataFinalBytes)), dataValue, "value");
    }

    function test_WhenCallerIsNotTrustedForwarder() external {
        // it should return the original calldata.

        uint256 dataValue = type(uint256).max;
        bytes memory data = abi.encodePacked(
            SppHarness.exposed_msgData.selector,
            dataValue,
            trustedForwarder
        );

        (bool success, bytes memory returnData) = address(sppHarness).call(data);

        // fists 4 bytes is the signature, rest is the datavalue
        bytes memory msgData = abi.decode(returnData, (bytes));

        bytes32 msgDataNext32Bytes;
        assembly {
            msgDataNext32Bytes := mload(add(msgData, add(0x20, 0x04)))
        }

        bytes20 msgDataLast20Bytes;
        uint256 offSet = 4 + 32;
        assembly {
            msgDataLast20Bytes := mload(add(msgData, add(0x20, offSet)))
        }

        assertTrue(success, "success");
        assertEq(msgData.length, data.length, "msgData-length");
        assertEq(bytes4(msgData), SppHarness.exposed_msgData.selector, "selector");
        // check msgData next 32 bytes are dataValue
        assertEq(uint256(msgDataNext32Bytes), dataValue, "value");
        // check msgData last 20 bytes are trustedForwarder
        assertEq(address(msgDataLast20Bytes), address(trustedForwarder), "trustedForwarder");
    }
}
