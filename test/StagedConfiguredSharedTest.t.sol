// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "./BaseTest.t.sol";
import {StagedProposalProcessor as SPP} from "../src/StagedProposalProcessor.sol";

abstract contract StagedConfiguredSharedTest is BaseTest {
    function setUp() public override {
        super.setUp();

        // setup stages
        SPP.Stage[] memory stages = _createDummyStages(2, false, false, false);
        multiBodyPlugin.updateStages(stages);
    }
}
