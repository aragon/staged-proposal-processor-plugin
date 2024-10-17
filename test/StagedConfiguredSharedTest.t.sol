// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "./BaseTest.t.sol";
import {StagedProposalProcessor as SPP} from "../src/StagedProposalProcessor.sol";

import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";

abstract contract StagedConfiguredSharedTest is BaseTest {
    function setUp() public override {
        super.setUp();

        // setup stages
        vetoThreshold = 0;
        SPP.Stage[] memory stages = _createCustomStages({
            _stageCount: 2,
            _plugin1Manual: false,
            _plugin2Manual: false,
            _plugin3Manual: false,
            _allowedBody: allowedBody,
            executor: address(trustedForwarder),
            operation: IPlugin.Operation.Call
        });
        sppPlugin.updateStages(stages);
    }
}
