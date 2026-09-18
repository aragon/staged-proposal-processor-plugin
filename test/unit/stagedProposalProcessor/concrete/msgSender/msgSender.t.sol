// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {BaseTest} from "../../../../BaseTest.t.sol";
import {SppHarness} from "../../../../utils/harness/SppHarness.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";

contract MsgSender_SPP_UnitTest is BaseTest {
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
        // it should return the appended address as the sender.

        (address appendedAddress, ) = makeAddrAndKey("alice");
        bytes memory data = abi.encodePacked(
            SppHarness.exposed_msgSender.selector,
            appendedAddress
        );

        // check the data length is greater than 20 bytes
        assertGt(data.length, 20, "data-length");

        (bool success, bytes memory returnData) = address(sppHarness).call(data);

        assertTrue(success, "success");
        assertEq(abi.decode(returnData, (address)), appendedAddress, "sender");
    }

    function test_WhenCalldataLengthIsLessThan20Bytes() external whenCallerIsTrustedForwarder {
        // it should return the trusted forwarder as the sender.

        uint64 dataValue = type(uint64).max;
        bytes memory data = abi.encodePacked(SppHarness.exposed_msgSender.selector, dataValue);

        // check the data length is lower than 20 bytes
        assertLt(data.length, 20, "data-length");

        (bool success, bytes memory returnData) = address(sppHarness).call(data);

        assertTrue(success, "success");
        assertEq(abi.decode(returnData, (address)), address(trustedForwarder), "sender");
    }

    function test_WhenCallerIsNotTrustedForwarder() external {
        // it should return the trusted forwarder as the sender.

        resetPrank(users.manager);

        (address appendedAddress, ) = makeAddrAndKey("alice");
        bytes memory data = abi.encodePacked(
            SppHarness.exposed_msgSender.selector,
            appendedAddress
        );

        (bool success, bytes memory returnData) = address(sppHarness).call(data);

        assertTrue(success, "success");
        assertEq(abi.decode(returnData, (address)), users.manager, "sender");
    }
}
