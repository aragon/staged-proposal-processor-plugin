// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../../BaseTest.t.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";

contract Initialize_SPP_UnitTest is BaseTest {
    SPP internal newSppPlugin;

    function setUp() public override {
        super.setUp();
        // deploy new SPP plugin without initializing it.
        newSppPlugin = SPP(createProxyAndCall(address(new SPP()), EMPTY_DATA));
    }

    modifier whenInitialized() {
        newSppPlugin.initialize(
            dao,
            address(trustedForwarder),
            new SPP.Stage[](0),
            DUMMY_METADATA,
            defaultTargetConfig
        );
        _;
    }

    function test_RevertWhen_Reinitializing() external whenInitialized {
        // it should revert.

        vm.expectRevert("Initializable: contract is already initialized");
        newSppPlugin.initialize(
            dao,
            address(trustedForwarder),
            new SPP.Stage[](0),
            EMPTY_METADATA,
            defaultTargetConfig
        );
    }

    modifier whenNotInitialized() {
        _;
    }

    modifier whenInitializing() {
        _;
    }

    function test_WhenInitializing() external whenNotInitialized whenInitializing {
        // it should emit events.
        // it should initialize the contract.

        // check event
        vm.expectEmit({emitter: address(newSppPlugin)});
        emit Initialized(1);

        newSppPlugin.initialize(
            dao,
            address(trustedForwarder),
            new SPP.Stage[](0),
            DUMMY_METADATA,
            defaultTargetConfig
        );

        // check initialization values are correct
        assertEq(newSppPlugin.getTrustedForwarder(), address(trustedForwarder));
        assertEq(address(newSppPlugin.dao()), address(dao));
        assertEq(newSppPlugin.getMetadata(), DUMMY_METADATA);
    }
}
