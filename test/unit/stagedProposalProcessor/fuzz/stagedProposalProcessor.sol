// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {Stage, Plugin} from "../../../utils/Types.sol";
import {BaseTest} from "../../../BaseTest.t.sol";
import {StagedProposalProcessor as SPP} from "../../../../src/StagedProposalProcessor.sol";

import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";

contract SPP_Unit_FuzzTest is BaseTest {
    function testFuzz_updateMetadata_RevertWhen_IsNotAllowed(address _randomAddress) external {
        // it should revert.

        assumeNotPrecompile(_randomAddress);
        vm.assume(_randomAddress != users.manager);

        resetPrank(_randomAddress);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(sppPlugin),
                _randomAddress,
                sppPlugin.UPDATE_METADATA_PERMISSION_ID()
            )
        );
        sppPlugin.updateMetadata(DUMMY_METADATA);
    }

    function testFuzz_updateStage_RevertWhen_IsNotAllowed(address _randomAddress) external {
        // it should revert.

        assumeNotPrecompile(_randomAddress);
        vm.assume(_randomAddress != users.manager);

        resetPrank(_randomAddress);
        SPP.Stage[] memory stages = _createDummyStages(2, true, true, false);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(sppPlugin),
                _randomAddress,
                sppPlugin.UPDATE_STAGES_PERMISSION_ID()
            )
        );
        sppPlugin.updateStages(stages);
    }

    function testFuzz_updateMetadata(bytes calldata _metadata) external {
        // it should update metadata.

        sppPlugin.updateMetadata(_metadata);

        assertEq(sppPlugin.getMetadata(), _metadata, "metadata");
    }

    function testFuzz_updateStages(Stage[] memory stages, Plugin[] memory plugins) external {
        // it should update stages.

        vm.assume(stages.length > 0);
        vm.assume(stages.length < 5);
        vm.assume(plugins.length > 0);
        vm.assume(plugins.length < 5);

        SPP.Stage[] memory fuzzStages = fuzzSppStages(stages, plugins);

        sppPlugin.updateStages(fuzzStages);

        assertEq(sppPlugin.getStages(), fuzzStages);
    }
}
