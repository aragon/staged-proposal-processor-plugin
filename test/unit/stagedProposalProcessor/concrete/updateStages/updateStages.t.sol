// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../../BaseTest.t.sol";
import {Errors} from "../../../../../src/libraries/Errors.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";

import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";

contract UpdateStages_SPP_UnitTest is BaseTest {
    function test_RevertWhen_CallerIsNotAllowedToUpdateStages() external {
        // it should revert.

        resetPrank(users.unauthorized);
        SPP.Stage[] memory stages = _createDummyStages(2, true, true, false);

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
        // it should revert.

        SPP.Stage[] memory stages = _createDummyStages(0, true, true, false);

        vm.expectRevert(abi.encodeWithSelector(Errors.StageCountZero.selector));
        sppPlugin.updateStages(stages);
    }

    function test_WhenTheNewStagesListHasSingleStage() external {
        // it should emit an event.
        // it should update the stage.

        SPP.Stage[] memory stages = _createDummyStages(1, true, true, false);
        uint256 _newConfigIndex = sppPlugin.getCurrentConfigIndex() + 1;

        vm.expectEmit({emitter: address(sppPlugin)});
        emit StagesUpdated(stages);
        sppPlugin.updateStages(stages);

        SPP.Stage[] memory newStages = sppPlugin.getStages();
        assertEq(sppPlugin.getCurrentConfigIndex(), _newConfigIndex, "configIndex");
        assertEq(newStages.length, stages.length, "stages length");
        assertEq(newStages, stages);
    }

    function test_WhenTheNewStagesListHasMultipleStages() external {
        // it should emit an event.
        // it should update the stage.

        SPP.Stage[] memory stages = _createDummyStages(3, true, true, false);
        uint256 _newConfigIndex = sppPlugin.getCurrentConfigIndex() + 1;

        vm.expectEmit({emitter: address(sppPlugin)});
        emit StagesUpdated(stages);
        sppPlugin.updateStages(stages);

        SPP.Stage[] memory newStages = sppPlugin.getStages();
        assertEq(sppPlugin.getCurrentConfigIndex(), _newConfigIndex, "configIndex");
        assertEq(newStages.length, stages.length, "stages length");
        assertEq(newStages, stages);
    }
}
