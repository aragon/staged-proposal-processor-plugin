// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {BaseTest} from "../../../../BaseTest.t.sol";
import {Permissions} from "../../../../../src/libraries/Permissions.sol";
import {SPPRuleCondition} from "../../../../../src/utils/SPPRuleCondition.sol";
import {StagedProposalProcessor as SPP} from "../../../../../src/StagedProposalProcessor.sol";
import {
    StagedProposalProcessorSetup as SPPSetup
} from "../../../../../src/StagedProposalProcessorSetup.sol";

import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {
    PluginUpgradeableSetup
} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginUpgradeableSetup.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {
    RuledCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/extensions/RuledCondition.sol";

contract PrepareUpdate_SPPSetup_UnitTest is BaseTest {
    SPPSetup sppSetup;

    function setUp() public override {
        super.setUp();

        sppSetup = new SPPSetup(new SPP());
    }

    function test_RevertWhen_FromBuildIsNotOne() external {
        // it should revert for any build other than 1 — there is only one supported update path.

        IPluginSetup.SetupPayload memory payload = IPluginSetup.SetupPayload({
            plugin: address(0),
            currentHelpers: new address[](0),
            data: ""
        });

        uint16[3] memory invalidFromBuilds = [uint16(0), uint16(2), uint16(3)];
        for (uint256 i = 0; i < invalidFromBuilds.length; i++) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    PluginUpgradeableSetup.InvalidUpdatePath.selector,
                    invalidFromBuilds[i],
                    2
                )
            );
            sppSetup.prepareUpdate(address(dao), invalidFromBuilds[i], payload);
        }
    }

    function test_WhenFromBuildIsOne() external {
        // it should deploy a new condition seeded with the existing rules,
        // return it as the single helper, and emit empty initData.

        SPPRuleCondition oldCondition = _deployOldConditionWithRules();
        address fakePlugin = makeAddr("fakePlugin");

        address[] memory currentHelpers = new address[](1);
        currentHelpers[0] = address(oldCondition);
        IPluginSetup.SetupPayload memory payload = IPluginSetup.SetupPayload({
            plugin: fakePlugin,
            currentHelpers: currentHelpers,
            data: ""
        });

        (bytes memory initData, IPluginSetup.PreparedSetupData memory setupData) = sppSetup
            .prepareUpdate(address(dao), 1, payload);

        // initData stays empty: no reinitializer needed.
        assertEq(initData.length, 0, "initData should be empty");

        // a brand new helper is returned (not the old one).
        assertEq(setupData.helpers.length, 1, "helpers length");
        assertNotEq(setupData.helpers[0], address(0), "helper non-zero");
        assertNotEq(setupData.helpers[0], address(oldCondition), "helper differs from old");

        // the new helper carries the same rules as the old one.
        RuledCondition.Rule[] memory oldRules = oldCondition.getRules();
        RuledCondition.Rule[] memory newRules = SPPRuleCondition(setupData.helpers[0]).getRules();
        assertEq(oldRules, newRules, "rules copied to new condition");
    }

    function test_WhenFromBuildIsOne_ItMigratesPermissions() external {
        // it should revoke CREATE_PROPOSAL/UPDATE_RULES from the old condition
        // and grant them on the new one, in that order.

        SPPRuleCondition oldCondition = _deployOldConditionWithRules();
        address fakePlugin = makeAddr("fakePlugin");

        address[] memory currentHelpers = new address[](1);
        currentHelpers[0] = address(oldCondition);
        IPluginSetup.SetupPayload memory payload = IPluginSetup.SetupPayload({
            plugin: fakePlugin,
            currentHelpers: currentHelpers,
            data: ""
        });

        (, IPluginSetup.PreparedSetupData memory setupData) = sppSetup.prepareUpdate(
            address(dao),
            1,
            payload
        );
        address newCondition = setupData.helpers[0];

        assertEq(setupData.permissions.length, 4, "four permission migrations expected");

        PermissionLib.MultiTargetPermission memory revokeCreate = setupData.permissions[0];
        assertEq(
            uint256(revokeCreate.operation),
            uint256(PermissionLib.Operation.Revoke),
            "[0] operation"
        );
        assertEq(revokeCreate.where, fakePlugin, "[0] where");
        assertEq(revokeCreate.who, ANY_ADDR, "[0] who");
        assertEq(revokeCreate.condition, address(oldCondition), "[0] condition");
        assertEq(
            revokeCreate.permissionId,
            Permissions.CREATE_PROPOSAL_PERMISSION_ID,
            "[0] permissionId"
        );

        PermissionLib.MultiTargetPermission memory grantCreate = setupData.permissions[1];
        assertEq(
            uint256(grantCreate.operation),
            uint256(PermissionLib.Operation.GrantWithCondition),
            "[1] operation"
        );
        assertEq(grantCreate.where, fakePlugin, "[1] where");
        assertEq(grantCreate.who, ANY_ADDR, "[1] who");
        assertEq(grantCreate.condition, newCondition, "[1] condition");
        assertEq(
            grantCreate.permissionId,
            Permissions.CREATE_PROPOSAL_PERMISSION_ID,
            "[1] permissionId"
        );

        PermissionLib.MultiTargetPermission memory revokeUpdateRules = setupData.permissions[2];
        assertEq(
            uint256(revokeUpdateRules.operation),
            uint256(PermissionLib.Operation.Revoke),
            "[2] operation"
        );
        assertEq(revokeUpdateRules.where, address(oldCondition), "[2] where");
        assertEq(revokeUpdateRules.who, address(dao), "[2] who");
        assertEq(
            revokeUpdateRules.permissionId,
            Permissions.UPDATE_RULES_PERMISSION_ID,
            "[2] permissionId"
        );

        PermissionLib.MultiTargetPermission memory grantUpdateRules = setupData.permissions[3];
        assertEq(
            uint256(grantUpdateRules.operation),
            uint256(PermissionLib.Operation.Grant),
            "[3] operation"
        );
        assertEq(grantUpdateRules.where, newCondition, "[3] where");
        assertEq(grantUpdateRules.who, address(dao), "[3] who");
        assertEq(
            grantUpdateRules.permissionId,
            Permissions.UPDATE_RULES_PERMISSION_ID,
            "[3] permissionId"
        );
    }

    function test_WhenFromBuildIsOneAndRulesAreEmpty() external {
        // it should still produce a valid update with an empty rules set on the new helper.

        SPPRuleCondition oldCondition = new SPPRuleCondition(
            address(dao),
            new RuledCondition.Rule[](0)
        );

        address[] memory currentHelpers = new address[](1);
        currentHelpers[0] = address(oldCondition);
        IPluginSetup.SetupPayload memory payload = IPluginSetup.SetupPayload({
            plugin: makeAddr("fakePlugin"),
            currentHelpers: currentHelpers,
            data: ""
        });

        (, IPluginSetup.PreparedSetupData memory setupData) = sppSetup.prepareUpdate(
            address(dao),
            1,
            payload
        );

        assertEq(SPPRuleCondition(setupData.helpers[0]).getRules().length, 0, "rules empty");
    }

    function _deployOldConditionWithRules() private returns (SPPRuleCondition oldCondition) {
        RuledCondition.Rule[] memory rules = new RuledCondition.Rule[](2);
        rules[0] = RuledCondition.Rule({
            id: 204, // VALUE_RULE_ID
            op: 7, // RET
            value: 1,
            permissionId: Permissions.CREATE_PROPOSAL_PERMISSION_ID
        });
        rules[1] = RuledCondition.Rule({
            id: 200, // BLOCK_NUMBER_RULE_ID
            op: 5, // GTE
            value: 100,
            permissionId: Permissions.CREATE_PROPOSAL_PERMISSION_ID
        });

        oldCondition = new SPPRuleCondition(address(dao), rules);
    }
}
