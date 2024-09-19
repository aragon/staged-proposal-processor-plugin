// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "./BaseTest.t.sol";
import {StagedProposalProcessor as SPP} from "../src/StagedProposalProcessor.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import "forge-std/console.sol";

contract GIORGI_OE is BaseTest {


    function test_Giorgi() external {
        SPP.Stage[] memory stages = _createDummyStages(2, false, false, false);
        sppPlugin.updateStages(stages);

        // create proposal
        IDAO.Action[] memory actions = _createDummyActions();

        uint256 g1 = gasleft();
        bytes32 proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE
        });

        uint256 g2 = gasleft();

        console.log("blaxblux");
        console.log(g1 - g2);
    }

}