// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {BaseTest} from "../../../../BaseTest.t.sol";
import {
    StagedProposalProcessorSetup as SPPSetup
} from "../../../../../src/StagedProposalProcessorSetup.sol";
import {SPPRuleCondition} from "../../../../../src/utils/SPPRuleCondition.sol";
import {CREATE_PROPOSAL_PERMISSION_ID} from "../../../../utils/Permissions.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";

import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {
    RuledCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/extensions/RuledCondition.sol";

contract PrepareInstallation_SPPSetup_UnitTest is BaseTest {
    SPPSetup sppSetup;

    function setUp() public override {
        super.setUp();

        // deploy SPPSetup contract.
        sppSetup = new SPPSetup();
    }

    modifier whenPreparingInstallation() {
        _;
    }

    function test_WhenPreparingInstallation() external whenPreparingInstallation {
        // it should deploy plugin.
        // it should store stages on the plugin.
        // it should store metadata on the plugin.
        // it should store trusted forwarder on the plugin.
        // it should return correct helpers.
        // it should return correct permissions list.

        SPP.Stage[] memory stages = _createDummyStages(3, false, false, false);
        bytes memory data = abi.encode(
            DUMMY_METADATA,
            stages,
            new RuledCondition.Rule[](0),
            defaultTargetConfig
        );
        (address deployedPlugin, IPluginSetup.PreparedSetupData memory setupData) = sppSetup
            .prepareInstallation(address(dao), data);

        // check deployed plugin.
        assertNotEq(address(0), deployedPlugin, "deployedPlugin");

        // check plugin stages.
        assertEq(
            stages,
            SPP(deployedPlugin).getStages(SPP(deployedPlugin).getCurrentConfigIndex()),
            "stages"
        );

        // check plugin metadata
        assertEq(DUMMY_METADATA, SPP(deployedPlugin).getMetadata(), "metadata");

        // check plugin trusted forwarder.
        assertEq(address(0), SPP(deployedPlugin).getTrustedForwarder(), "trustedForwarder");

        // check plugin stages.
        assertEq(
            stages,
            SPP(deployedPlugin).getStages(SPP(deployedPlugin).getCurrentConfigIndex()),
            "stages"
        );

        // check returned helpers
        assertEq(1, setupData.helpers.length, "helpersLength");
        assertNotEq(address(0), setupData.helpers[0], "helpersLength");

        // check returned permissions list.
        assertEq(setupData.permissions.length, _getSetupPermissions().length, "permissionsLength");
        for (uint256 i = 0; i < 7; i++) {
            bytes32 permissionId = setupData.permissions[i].permissionId;
            assertEq(
                uint256(setupData.permissions[i].operation),
                permissionId == CREATE_PROPOSAL_PERMISSION_ID
                    ? uint256(PermissionLib.Operation.GrantWithCondition)
                    : uint256(PermissionLib.Operation.Grant),
                "operation"
            );

            assertValueInList(permissionId, _getSetupPermissions(), "permissionId");
        }
    }

    function test_WhenRulesAreEmpty() external whenPreparingInstallation {
        // it should return spp condition as only helper.
        // it should set correct permission with spp condition.
        // it should not store rules on the spp condition.

        bytes memory data = abi.encode(
            DUMMY_METADATA,
            new SPP.Stage[](0),
            new RuledCondition.Rule[](0), // empty rules
            defaultTargetConfig
        );
        (, IPluginSetup.PreparedSetupData memory setupData) = sppSetup.prepareInstallation(
            address(dao),
            data
        );

        // check returned helpers
        assertEq(1, setupData.helpers.length, "helpersLength");
        assertNotEq(address(0), setupData.helpers[0], "helpersLength");

        // check permission granted
        assertEq(
            uint256(PermissionLib.Operation.GrantWithCondition),
            uint256(_findCreateProposalPermission(setupData.permissions).operation),
            "operation"
        );

        // check permissions on condition are empty
        assertEq(0, SPPRuleCondition(setupData.helpers[0]).getRules().length, "rules");
    }

    function test_WhenRulesAreNotEmpty() external whenPreparingInstallation {
        // it should return spp condition as only helper.
        // it should set correct permission with spp condition.
        // it should store the rules on the spp condition.

        RuledCondition.Rule[] memory rules = new RuledCondition.Rule[](1);
        rules[0] = RuledCondition.Rule({
            id: 1,
            op: 1,
            value: 1,
            permissionId: CREATE_PROPOSAL_PERMISSION_ID
        });
        bytes memory data = abi.encode(
            DUMMY_METADATA,
            new SPP.Stage[](0),
            rules, //not empty rules
            defaultTargetConfig
        );
        (, IPluginSetup.PreparedSetupData memory setupData) = sppSetup.prepareInstallation(
            address(dao),
            data
        );

        // check returned helpers
        assertEq(1, setupData.helpers.length, "helpersLength");
        assertNotEq(address(0), setupData.helpers[0], "helpersLength");

        // check permission granted
        assertEq(
            uint256(PermissionLib.Operation.GrantWithCondition),
            uint256(_findCreateProposalPermission(setupData.permissions).operation),
            "operation"
        );

        // check permissions on condition are not empty
        assertEq(rules, SPPRuleCondition(setupData.helpers[0]).getRules(), "rules");
    }

    function _findCreateProposalPermission(
        PermissionLib.MultiTargetPermission[] memory permissions
    ) private returns (PermissionLib.MultiTargetPermission memory permission) {
        for (uint256 i = 0; i < permissions.length; i++) {
            if (permissions[i].permissionId == CREATE_PROPOSAL_PERMISSION_ID) {
                permission = permissions[i];
            }
        }
        if (permission.permissionId == 0) {
            fail();
        }
    }
}
