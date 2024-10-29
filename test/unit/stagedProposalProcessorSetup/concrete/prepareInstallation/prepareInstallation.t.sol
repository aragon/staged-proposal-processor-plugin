// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {
    RuledCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/extensions/RuledCondition.sol";
import {
    AlwaysTrueCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/extensions/AlwaysTrueCondition.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

import {BaseTest} from "../../../../BaseTest.t.sol";
import {
    StagedProposalProcessorSetup as SPPSetup
} from "../../../../../src/StagedProposalProcessorSetup.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";

contract PrepareInstallation_SPPSetup_UnitTest is BaseTest {
    SPPSetup sppSetup;

    function setUp() public override {
        super.setUp();


        // deploy SPPSetup contract.
        sppSetup = new SPPSetup(address(new AlwaysTrueCondition()));
    }

    function test_WhenPreparingInstallation() external {
        // it should deploy plugin.
        // it should define trusted forwarder on the plugin.
        // it should return correct helpers.
        // it should return correct permissions list.

        SPP.Stage[] memory stages = _createDummyStages(3, false, false, false);
        bytes memory data = abi.encode(
            stages,
            bytes("metadata"),
            defaultTargetConfig,
            new RuledCondition.Rule[](0)
        );
        (address deployedPlugin, IPluginSetup.PreparedSetupData memory setupData) = sppSetup
            .prepareInstallation(address(dao), data);

        // check deployed plugin.
        assertNotEq(address(0), deployedPlugin, "deployedPlugin");

        // check plugin trusted forwarder.
        assertEq(address(0), SPP(deployedPlugin).getTrustedForwarder(), "trustedForwarder");

        // check plugin stages.
        assertEq(stages, SPP(deployedPlugin).getStages(), "stages");

        // todo check returned helpers

        // check returned permissions list.
        assertEq(setupData.permissions.length, 7, "permissionsLength");
        for (uint256 i = 0; i < 7; i++) {
            bytes32 permissionId = setupData.permissions[i].permissionId;
            assertEq(
                uint256(setupData.permissions[i].operation),
                permissionId == sppSetup.CREATE_PROPOSAL_PERMISSION_ID()
                    ? uint256(PermissionLib.Operation.GrantWithCondition)
                    : uint256(PermissionLib.Operation.Grant),
                "operation"
            );

            assertValueInList(permissionId, _getSetupPermissions(), "permissionId");
        }
    }
}
