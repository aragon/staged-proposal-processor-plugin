// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {BaseTest} from "../../../BaseTest.t.sol";
import {Stage, Body} from "../../../utils/Types.sol";
import {Permissions} from "../../../../src/libraries/Permissions.sol";
import {StagedProposalProcessor as SPP} from "../../../../src/StagedProposalProcessor.sol";

import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

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
                Permissions.SET_METADATA_PERMISSION_ID
            )
        );
        sppPlugin.setMetadata(DUMMY_METADATA);
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
                Permissions.UPDATE_STAGES_PERMISSION_ID
            )
        );
        sppPlugin.updateStages(stages);
    }

    function testFuzz_updateMetadata(bytes calldata _metadata) external {
        // it should update metadata.

        vm.assume(_metadata.length != 0);

        sppPlugin.setMetadata(_metadata);

        assertEq(sppPlugin.getMetadata(), _metadata, "metadata");
    }
}
