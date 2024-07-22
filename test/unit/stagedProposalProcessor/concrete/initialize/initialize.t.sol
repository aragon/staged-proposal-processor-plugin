// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../../BaseTest.t.sol";
import {Errors} from "../../../../../src/libraries/Errors.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";

contract Initialize_SPP_UnitTest is BaseTest {
    SPP internal newSppPlugin;

    function setUp() public override {
        super.setUp();
        // deploy new SPP plugin without initializing it.
        newSppPlugin = SPP(createProxyAndCall(address(new SPP()), EMPTY_DATA));
    }

    modifier whenInitialized() {
        newSppPlugin.initialize(dao, address(trustedForwarder), new SPP.Stage[](0), DUMMY_METADATA);
        _;
    }

    function test_RevertWhen_Reinitializing() external whenInitialized {
        // it should revert.
        vm.expectRevert("Initializable: contract is already initialized");
        newSppPlugin.initialize(dao, address(trustedForwarder), new SPP.Stage[](0), EMPTY_METADATA);
    }

    modifier whenNotInitialized() {
        _;
    }

    modifier whenInitializing() {
        _;
    }

    function test_WhenInitializing() external whenNotInitialized whenInitializing {
        // it should emit events.
        vm.expectEmit({emitter: address(newSppPlugin)});
        emit Initialized(1);

        newSppPlugin.initialize(dao, address(trustedForwarder), new SPP.Stage[](0), DUMMY_METADATA);

        // it should initialize the contract.
        assertEq(newSppPlugin.trustedForwarder(), address(trustedForwarder));
        assertEq(address(newSppPlugin.dao()), address(dao));
        assertEq(newSppPlugin.getMetadata(), DUMMY_METADATA);
    }

    function test_RevertWhen_MetadataIsNotCorrect() external whenNotInitialized whenInitializing {
        // it should revert.

        vm.expectRevert(abi.encodeWithSelector(Errors.EmptyMetadata.selector));

        newSppPlugin.initialize(dao, address(trustedForwarder), new SPP.Stage[](0), EMPTY_DATA);
    }
}
