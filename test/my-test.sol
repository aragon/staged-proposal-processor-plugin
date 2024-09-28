// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "./BaseTest.t.sol";
import {StagedProposalProcessor as SPP} from "../src/StagedProposalProcessor.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import "forge-std/console.sol";

contract GIORGI_OE is BaseTest {

    function test_Giorgi() external {
        SPP.Stage[] memory stages = _createDummyStages(2, false, false, false);
        sppPlugin.updateStages(stages);

        // create proposal
        Action[] memory actions = _createDummyActions();

        uint256 g1 = gasleft();
        uint256 proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE,
            _data: defaultCreationParams
        });

        uint256 g2 = gasleft();

        console.log("blaxblux");
        console.log(g1 - g2);
    }

}