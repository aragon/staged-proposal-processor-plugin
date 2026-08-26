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
import {
    AddressCheckConditionMock
} from "@aragon/osx-commons-contracts/src/mocks/permission/condition/AddressCheckConditionMock.sol";

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

    function test_WhenFromBuildIsOne_ItPreservesAsymmetricIfElseRulesAcrossMigration()
        external
    {
        // it should preserve an IF_ELSE rule that routes through an external
        // CONDITION_RULE_ID predicate across the migration:
        //   (a) the `_updateRules` staticcall probe on the CONDITION rule must
        //       not trip when the new helper is constructed with the seeded
        //       rules — the other prepareUpdate tests only exercise VALUE /
        //       BLOCK_NUMBER rules and would miss a regression there;
        //   (b) the resulting helper's `isGranted` must evaluate the asymmetric
        //       predicate with (_where, _who) in the correct order.
        //
        // NOTE: both endpoints here are v1.2 — there is no dual OSx/SPP import,
        // so this cannot witness the v1.1 → v1.2 swap-bug cure directly. That
        // property lives in the fork test, which installs a real v1.1 build via
        // the plugin repo. What this test pins is the post-migration invariant
        // on v1.2, cheaply and without an RPC.

        address fakePlugin = makeAddr("fakePlugin");
        address alice = makeAddr("alice");

        // Asymmetric predicate: true only for the exact pair (fakePlugin, alice).
        // Swapping the arguments would compare (alice, fakePlugin) and return
        // false, so the IF_ELSE branch taken is a direct readout of argument
        // order — a regression that swapped `(_where, _who)` post-migration
        // would flip both assertions below.
        AddressCheckConditionMock asymCondition = new AddressCheckConditionMock();
        asymCondition.setExpected(fakePlugin, alice);

        SPPRuleCondition oldCondition = _deployOldConditionWithIfElseCondRule(
            address(asymCondition)
        );

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
        SPPRuleCondition newCondition = SPPRuleCondition(setupData.helpers[0]);

        // Correct order — predicate matches, IF_ELSE routes to the success branch.
        assertTrue(
            newCondition.isGranted(
                fakePlugin,
                alice,
                Permissions.CREATE_PROPOSAL_PERMISSION_ID,
                bytes("")
            ),
            "migrated condition must evaluate (_where, _who) in the correct order"
        );

        // Swapped inputs — predicate must not match.
        assertFalse(
            newCondition.isGranted(
                alice,
                fakePlugin,
                Permissions.CREATE_PROPOSAL_PERMISSION_ID,
                bytes("")
            ),
            "migrated condition must not silently swap _where and _who"
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

    function _deployOldConditionWithIfElseCondRule(
        address _asymPredicate
    ) private returns (SPPRuleCondition oldCondition) {
        // encodeIfElse is pure — pull it off the setup's stored implementation
        // to avoid deploying a throwaway condition just for the encoding.
        uint240 ifElseValue = SPPRuleCondition(sppSetup.CONDITION_IMPLEMENTATION())
            .encodeIfElse(1, 2, 3);

        RuledCondition.Rule[] memory rules = new RuledCondition.Rule[](4);

        // rule 0: IF_ELSE(predicate=1, success=2, failure=3) — entry point.
        rules[0] = RuledCondition.Rule({
            id: 203, // LOGIC_OP_RULE_ID
            op: 12, // IF_ELSE
            value: ifElseValue,
            permissionId: Permissions.CREATE_PROPOSAL_PERMISSION_ID
        });

        // rule 1: predicate — asymmetric condition sensitive to (_where, _who) order.
        rules[1] = RuledCondition.Rule({
            id: 202, // CONDITION_RULE_ID
            op: 1, // EQ
            value: uint160(_asymPredicate),
            permissionId: Permissions.CREATE_PROPOSAL_PERMISSION_ID
        });

        // rule 2: success branch — RET 1.
        rules[2] = RuledCondition.Rule({
            id: 204, // VALUE_RULE_ID
            op: 7, // RET
            value: 1,
            permissionId: Permissions.CREATE_PROPOSAL_PERMISSION_ID
        });

        // rule 3: failure branch — RET 0.
        rules[3] = RuledCondition.Rule({
            id: 204, // VALUE_RULE_ID
            op: 7, // RET
            value: 0,
            permissionId: Permissions.CREATE_PROPOSAL_PERMISSION_ID
        });

        oldCondition = new SPPRuleCondition(address(dao), rules);
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
