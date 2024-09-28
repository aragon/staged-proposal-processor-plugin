// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../../BaseTest.t.sol";
import {
    StagedProposalProcessorSetup as SPPSetup
} from "../../../../../src/StagedProposalProcessorSetup.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";

contract PrepareInstallation_SPPSetup_UnitTest is BaseTest {
    SPPSetup sppSetup;

    function setUp() public override {
        super.setUp();

        // deploy SPPSetup contract.
        sppSetup = new SPPSetup();
    }

    function test_WhenPreparingInstallation() external {
        // it should deploy plugin.
        // it should define trusted forwarder on the plugin.
        // it should return correct helpers.
        // it should return correct permissions list.

        SPP.Stage[] memory stages = _createDummyStages(3, false, false, false);
        bytes memory data = abi.encode(stages, bytes("metadata"), defaultTargetConfig);
        (address deployedPlugin, IPluginSetup.PreparedSetupData memory setupData) = sppSetup
            .prepareInstallation(address(dao), data);

        // check deployed plugin.
        assertNotEq(address(0), deployedPlugin, "deployedPlugin");

        // check plugin trusted forwarder.
        assertEq(address(0), SPP(deployedPlugin).getTrustedForwarder(), "trustedForwarder");

        // check plugin stages.
        assertEq(stages, SPP(deployedPlugin).getStages());

        // todo check returned helpers

        // check returned permissions list.
        assertEq(setupData.permissions.length, 3, "permissionsLength");
        for (uint256 i = 0; i < 3; i++) {
            assertEq(
                uint256(setupData.permissions[i].operation),
                uint256(PermissionLib.Operation.Grant),
                "operation"
            );
            if (
                setupData.permissions[i].permissionId != sppSetup.UPDATE_STAGES_PERMISSION_ID() &&
                setupData.permissions[i].permissionId !=
                DAO(payable(address(dao))).EXECUTE_PERMISSION_ID() &&
                setupData.permissions[i].permissionId !=
                sppSetup.SET_TRUSTED_FORWARDER_PERMISSION_ID()
            ) {
                fail();
            }
        }
    }
}
