// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../../BaseTest.t.sol";
import {Errors} from "../../../../../src/libraries/Errors.sol";
import {PluginB} from "../../../../utils/dummy-plugins/PluginB.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";

import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";

contract UpdateStages_SPP_UnitTest is BaseTest {
    function test_RevertWhen_CallerIsNotAllowedToUpdateStages() external {
        // it should revert.

        resetPrank(users.unauthorized);
        SPP.Stage[] memory stages = _createDummyStages({
            _stageCount: 2,
            _plugin1Manual: true,
            _plugin2Manual: true,
            _plugin3Manual: false
        });

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

        SPP.Stage[] memory stages = _createDummyStages({
            _stageCount: 0,
            _plugin1Manual: true,
            _plugin2Manual: true,
            _plugin3Manual: false
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.StageCountZero.selector));
        sppPlugin.updateStages(stages);
    }

    function test_WhenTheNewStagesListHasSingleStage() external {
        // it should emit an event.
        // it should update the stage.

        SPP.Stage[] memory stages = _createDummyStages({
            _stageCount: 1,
            _plugin1Manual: true,
            _plugin2Manual: true,
            _plugin3Manual: false
        });
        uint256 _newConfigIndex = sppPlugin.getCurrentConfigIndex() + 1;

        vm.expectEmit({emitter: address(sppPlugin)});
        emit StagesUpdated(stages);
        sppPlugin.updateStages(stages);

        SPP.Stage[] memory newStages = sppPlugin.getStages();
        assertEq(sppPlugin.getCurrentConfigIndex(), _newConfigIndex, "configIndex");
        assertEq(newStages.length, stages.length, "stages length");
        assertEq(newStages, stages);
    }

    modifier whenTheNewStagesListHasMultipleStages() {
        _;
    }

    modifier whenSomeStagesAreNonManual() {
        _;
    }

    function test_WhenTheStageSupportsIProposal()
        external
        whenTheNewStagesListHasMultipleStages
        whenSomeStagesAreNonManual
    {
        // it should emit event.
        // it should update the stages.
        SPP.Stage[] memory stages = _createDummyStages({
            _stageCount: 3,
            _plugin1Manual: true,
            _plugin2Manual: false,
            _plugin3Manual: false
        });
        uint256 _newConfigIndex = sppPlugin.getCurrentConfigIndex() + 1;

        vm.expectEmit({emitter: address(sppPlugin)});
        emit StagesUpdated(stages);
        sppPlugin.updateStages(stages);

        SPP.Stage[] memory newStages = sppPlugin.getStages();
        assertEq(sppPlugin.getCurrentConfigIndex(), _newConfigIndex, "configIndex");
        assertEq(newStages.length, stages.length, "stages length");
        assertEq(newStages, stages);
    }

    function test_RevertWhen_TheStageDoesNotSupportIProposal()
        external
        whenTheNewStagesListHasMultipleStages
        whenSomeStagesAreNonManual
    {
        // it should revert.

        SPP.Plugin[] memory _plugins = new SPP.Plugin[](1);
        _plugins[0] = _createPluginStruct(address(new PluginB(address(trustedForwarder))), false);

        SPP.Stage[] memory stages = new SPP.Stage[](1);
        stages[0] = _createStageStruct(_plugins);

        // check revert
        vm.expectRevert(abi.encodeWithSelector(Errors.InterfaceNotSupported.selector));
        sppPlugin.updateStages(stages);
    }

    function test_WhenAllStagesAreManual() external whenTheNewStagesListHasMultipleStages {
        // it should emit an event.
        // it should update the stage.

        SPP.Stage[] memory stages = _createDummyStages({
            _stageCount: 3,
            _plugin1Manual: true,
            _plugin2Manual: true,
            _plugin3Manual: true
        });
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
