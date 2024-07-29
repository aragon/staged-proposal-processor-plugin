// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

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

    // todo think how fuzz since it has an enum (enums are uint8 and ProposalType is 0 or 1 others values will revert)
    // function testFuzz_updateStages(Plugin[2] memory _plugins, bytes memory _metadata) external {}
}
