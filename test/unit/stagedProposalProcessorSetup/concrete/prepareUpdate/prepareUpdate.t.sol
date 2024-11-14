// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../../BaseTest.t.sol";
import {
    StagedProposalProcessorSetup as SPPSetup
} from "../../../../../src/StagedProposalProcessorSetup.sol";

import {
    PluginUpgradeableSetup
} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginUpgradeableSetup.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";

contract PrepareUpdate_SPPSetup_UnitTest is BaseTest {
    SPPSetup sppSetup;

    function setUp() public override {
        super.setUp();

        // deploy SPPSetup contract.
        sppSetup = new SPPSetup();
    }

    function test_RevertWhen_PreparingUpdate() external {
        // it should revert.

        // reverts due to there is no build before current one.
        vm.expectRevert(
            abi.encodeWithSelector(PluginUpgradeableSetup.InvalidUpdatePath.selector, 0, 1)
        );
        sppSetup.prepareUpdate(
            address(dao),
            0,
            IPluginSetup.SetupPayload({
                plugin: address(0),
                currentHelpers: new address[](0),
                data: ""
            })
        );
    }
}
