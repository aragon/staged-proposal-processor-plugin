// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../../BaseTest.t.sol";
import {
    StagedProposalProcessorSetup as SPPSetup
} from "../../../../../src/StagedProposalProcessorSetup.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";

contract PrepareUninstallation_SPPSetup_UnitTest is BaseTest {
    SPPSetup sppSetup;

    function setUp() public override {
        super.setUp();

        // deploy SPPSetup contract.
        sppSetup = new SPPSetup();
    }

    function test_WhenPreparingUninstallation() external {
        // it should return the correct permissions list to revoke.

        address[] memory helpers = new address[](1);
        helpers[0] = address(this);

        IPluginSetup.SetupPayload memory payload = IPluginSetup.SetupPayload({
            plugin: address(0),
            currentHelpers: helpers,
            data: ""
        });

        PermissionLib.MultiTargetPermission[] memory permissions = sppSetup.prepareUninstallation(
            address(dao),
            payload
        );

        // check returned permissions list.
        assertEq(permissions.length, 7, "permissionsLength");
        for (uint256 i = 0; i < 7; i++) {
            bytes32 permissionId = permissions[i].permissionId;
            assertEq(
                uint256(permissions[i].operation),
                uint256(PermissionLib.Operation.Revoke),
                "operation"
            );

            assertValueInList(permissionId, _getSetupPermissions(), "permissionId");
        }
    }
}
