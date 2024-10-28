// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../../BaseTest.t.sol";
import {Errors} from "../../../../../src/libraries/Errors.sol";
import {PluginB} from "../../../../utils/dummy-plugins/PluginB/PluginB.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";

import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";

contract UpdateStages_SPP_UnitTest is BaseTest {
    function test_RevertWhen_CallerIsNotAllowedToUpdateStages() external {
        // it should revert.

        resetPrank(users.unauthorized);
        SPP.Stage[] memory stages = _createDummyStages({
            _stageCount: 2,
            _body1Manual: true,
            _body2Manual: true,
            _body3Manual: false
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
            _body1Manual: true,
            _body2Manual: true,
            _body3Manual: false
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.StageCountZero.selector));
        sppPlugin.updateStages(stages);
    }

    function test_WhenTheNewStagesListHasSingleStage() external {
        // it should emit an event.
        // it should update the stage.

        SPP.Stage[] memory stages = _createDummyStages({
            _stageCount: 1,
            _body1Manual: true,
            _body2Manual: true,
            _body3Manual: false
        });
        uint256 _newConfigIndex = sppPlugin.getCurrentConfigIndex() + 1;

        vm.expectEmit({emitter: address(sppPlugin)});
        emit StagesUpdated(stages);
        sppPlugin.updateStages(stages);

        SPP.Stage[] memory newStages = sppPlugin.getStages();
        assertEq(sppPlugin.getCurrentConfigIndex(), _newConfigIndex, "configIndex");
        assertEq(newStages.length, stages.length, "stages length");
        assertEq(newStages, stages, "stages");
    }

    modifier whenTheNewStagesListHasMultipleStages() {
        _;
    }

    function test_RevertWhen_MinAdvanceIsBiggerOrEqualThanMaxAdvance()
        external
        whenTheNewStagesListHasMultipleStages
    {
        // it should revert.

        // set minAdvance bigger than maxAdvance
        minAdvance = maxAdvance + 1;
        SPP.Stage[] memory stages = _createDummyStages({
            _stageCount: 2,
            _body1Manual: true,
            _body2Manual: true,
            _body3Manual: false
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.StageDurationsInvalid.selector));
        sppPlugin.updateStages(stages);

        // set minAdvance equal to maxAdvance
        minAdvance = maxAdvance;
        stages = _createDummyStages({
            _stageCount: 2,
            _body1Manual: true,
            _body2Manual: true,
            _body3Manual: false
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.StageDurationsInvalid.selector));
        sppPlugin.updateStages(stages);
    }

    function test_RevertWhen_VoteDurationIsBiggerOrEqualThanMaxAdvance()
        external
        whenTheNewStagesListHasMultipleStages
    {
        // it should revert.

        // set voteDuration bigger than maxAdvance
        voteDuration = maxAdvance + 1;
        SPP.Stage[] memory stages = _createDummyStages({
            _stageCount: 2,
            _body1Manual: true,
            _body2Manual: true,
            _body3Manual: false
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.StageDurationsInvalid.selector));
        sppPlugin.updateStages(stages);

        // set voteDuration equal to maxAdvance
        voteDuration = maxAdvance;
        stages = _createDummyStages({
            _stageCount: 2,
            _body1Manual: true,
            _body2Manual: true,
            _body3Manual: false
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.StageDurationsInvalid.selector));
        sppPlugin.updateStages(stages);
    }

    function test_RevertWhen_ApprovalThresholdIsBiggerThanBodiesLength()
        external
        whenTheNewStagesListHasMultipleStages
    {
        // it should revert.

        // set approvalThreshold bigger than bodies length
        approvalThreshold = 3;
        SPP.Stage[] memory stages = _createDummyStages({
            _stageCount: 2,
            _body1Manual: true,
            _body2Manual: true,
            _body3Manual: false
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.StageThresholdsInvalid.selector));
        sppPlugin.updateStages(stages);
    }

    function test_RevertWhen_VetoThresholdIsBiggerThanBodiesLength()
        external
        whenTheNewStagesListHasMultipleStages
    {
        // it should revert.

        // set vetoThreshold bigger than bodies length
        vetoThreshold = 3;
        SPP.Stage[] memory stages = _createDummyStages({
            _stageCount: 2,
            _body1Manual: true,
            _body2Manual: true,
            _body3Manual: false
        });

        vm.expectRevert(abi.encodeWithSelector(Errors.StageThresholdsInvalid.selector));
        sppPlugin.updateStages(stages);
    }

    function test_RevertWhen_ThereAreDuplicatedBodiesOnSameStage()
        external
        whenTheNewStagesListHasMultipleStages
    {
        // it should revert.

        // create stages structure with duplicated body address
        address duplicatedAddr = address(new PluginB(address(trustedForwarder)));

        SPP.Body[] memory stageBodies = new SPP.Body[](2);
        stageBodies[0] = _createBodyStruct(duplicatedAddr, false);
        stageBodies[1] = _createBodyStruct(duplicatedAddr, false);
        SPP.Stage[] memory stages = new SPP.Stage[](1);
        stages[0] = _createStageStruct(stageBodies);

        vm.expectRevert(
            abi.encodeWithSelector(Errors.DuplicateBodyAddress.selector, 0, duplicatedAddr)
        );
        sppPlugin.updateStages(stages);
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
            _body1Manual: true,
            _body2Manual: false,
            _body3Manual: false
        });
        uint256 _newConfigIndex = sppPlugin.getCurrentConfigIndex() + 1;

        vm.expectEmit({emitter: address(sppPlugin)});
        emit StagesUpdated(stages);
        sppPlugin.updateStages(stages);

        SPP.Stage[] memory newStages = sppPlugin.getStages();
        assertEq(sppPlugin.getCurrentConfigIndex(), _newConfigIndex, "configIndex");
        assertEq(newStages.length, stages.length, "stages length");
        assertEq(newStages, stages, "stages");
    }

    function test_RevertWhen_TheStageDoesNotSupportIProposal()
        external
        whenTheNewStagesListHasMultipleStages
        whenSomeStagesAreNonManual
    {
        // it should revert.

        SPP.Body[] memory _bodies = new SPP.Body[](1);
        _bodies[0] = _createBodyStruct(address(new PluginB(address(trustedForwarder))), false);

        SPP.Stage[] memory stages = new SPP.Stage[](1);
        stages[0] = _createStageStruct(_bodies);

        // check revert
        vm.expectRevert(abi.encodeWithSelector(Errors.InterfaceNotSupported.selector));
        sppPlugin.updateStages(stages);
    }

    function test_WhenAllStagesAreManual() external whenTheNewStagesListHasMultipleStages {
        // it should emit an event.
        // it should update the stage.

        SPP.Stage[] memory stages = _createDummyStages({
            _stageCount: 3,
            _body1Manual: true,
            _body2Manual: true,
            _body3Manual: true
        });
        uint256 _newConfigIndex = sppPlugin.getCurrentConfigIndex() + 1;

        vm.expectEmit({emitter: address(sppPlugin)});
        emit StagesUpdated(stages);
        sppPlugin.updateStages(stages);

        SPP.Stage[] memory newStages = sppPlugin.getStages();
        assertEq(sppPlugin.getCurrentConfigIndex(), _newConfigIndex, "configIndex");
        assertEq(newStages.length, stages.length, "stages length");
        assertEq(newStages, stages, "stages");
    }
}
