// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {BaseTest} from "../../../../BaseTest.t.sol";
import {Errors} from "../../../../../src/libraries/Errors.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";

contract GetStages_SPP_UnitTest is BaseTest {
    modifier givenInvalidIndex() {
        _;
    }

    function test_RevertGiven_IndexIsZero() external givenInvalidIndex {
        // it should revert.

        uint256 index;

        vm.expectRevert(Errors.StageCountZero.selector);
        sppPlugin.getStages(index);
    }

    function test_RevertGiven_IndexGreaterThanCurrentConfigIndex() external givenInvalidIndex {
        // it should revert.
        uint256 index = sppPlugin.getCurrentConfigIndex() + 1;

        vm.expectRevert(Errors.StageCountZero.selector);
        sppPlugin.getStages(index);
    }

    function test_GivenValidIndex() external {
        // it should return correct stages array.

        // update stages configuration
        SPP.Stage[] memory stages = _createDummyStages({
            _stageCount: 1,
            _body1Manual: true,
            _body2Manual: true,
            _body3Manual: false
        });

        sppPlugin.updateStages(stages);

        // check stages
        assertEq(sppPlugin.getStages(sppPlugin.getCurrentConfigIndex()), stages, "stages");
    }
}
