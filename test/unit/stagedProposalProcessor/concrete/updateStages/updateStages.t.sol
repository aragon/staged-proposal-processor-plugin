// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../../BaseTest.t.sol";
import {Errors} from "../../../../../src/libraries/Errors.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";

import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";

contract UpdateStages_SPP_UnitTest is BaseTest {
    function test_RevertWhen_CallerIsNotAllowedToUpdateStages() external {
        resetPrank(users.unauthorized);
        SPP.Stage[] memory stages = _createDummyStages(2, true, true, false);

        // it should revert.
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(sppPlugin),
                users.unauthorized,
                sppPlugin.UPDATE_STAGES_PERMISSION_ID()
            )
        );
        sppPlugin.updateStages(stages);
    }

    function test_RevertWhen_TheNewStagesListIsEmpty() external {
        SPP.Stage[] memory stages = _createDummyStages(0, true, true, false);

        // it should revert.
        vm.expectRevert(abi.encodeWithSelector(Errors.StageCountZero.selector));
        sppPlugin.updateStages(stages);
    }

    function test_WhenTheNewStagesListHasSingleStage() external {
        SPP.Stage[] memory stages = _createDummyStages(1, true, true, false);
        uint256 _newConfigIndex = sppPlugin.getCurrentConfigIndex() + 1;

        // it should emit an event.
        vm.expectEmit({emitter: address(sppPlugin)});
        emit StagesUpdated(stages);
        sppPlugin.updateStages(stages);

        SPP.Stage[] memory newStages = sppPlugin.getStages();
        // it should update the stage.
        assertEq(sppPlugin.getCurrentConfigIndex(), _newConfigIndex, "configIndex");
        assertEq(newStages.length, stages.length, "stages length");
        assertEq(newStages, stages);
    }

    function test_WhenTheNewStagesListHasMultipleStages() external {
        SPP.Stage[] memory stages = _createDummyStages(3, true, true, false);
        uint256 _newConfigIndex = sppPlugin.getCurrentConfigIndex() + 1;

        // it should emit an event.
        vm.expectEmit({emitter: address(sppPlugin)});
        emit StagesUpdated(stages);
        sppPlugin.updateStages(stages);

        SPP.Stage[] memory newStages = sppPlugin.getStages();
        // it should update the stage.
        assertEq(sppPlugin.getCurrentConfigIndex(), _newConfigIndex, "configIndex");
        assertEq(newStages.length, stages.length, "stages length");
        assertEq(newStages, stages);
    }
}
