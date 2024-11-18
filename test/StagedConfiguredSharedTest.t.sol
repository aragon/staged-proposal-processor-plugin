// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

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
            _body1Manual: false,
            _body2Manual: false,
            _body3Manual: false,
            _executor: address(trustedForwarder),
            _operation: IPlugin.Operation.Call,
            _tryAdvance: true
        });
        sppPlugin.updateStages(stages);
    }
}
