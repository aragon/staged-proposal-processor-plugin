// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../../BaseTest.t.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";

contract GetMetadata_SPP_UnitTest is BaseTest {
    SPP internal notInitializedSppPlugin;

    function setUp() public override {
        super.setUp();
        // deploy new SPP plugin without initializing it, to have empty metadata.
        notInitializedSppPlugin = SPP(createProxyAndCall(address(new SPP()), EMPTY_DATA));
    }

    function test_WhenNonConfiguredMetadata() external view {
        // it should return empty metadata.

        bytes memory _metadata = notInitializedSppPlugin.getMetadata();
        assertEq(_metadata, EMPTY_METADATA);
    }

    function test_WhenConfiguredMetadata() external {
        // it should return correct metadata.

        // configure metadata
        sppPlugin.setMetadata(DUMMY_METADATA);

        bytes memory _metadata = sppPlugin.getMetadata();
        assertEq(_metadata, DUMMY_METADATA);
    }
}
