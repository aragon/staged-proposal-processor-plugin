// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Permissions} from "../../../../src/libraries/Permissions.sol";
import {SPPRuleCondition} from "../../../../src/utils/SPPRuleCondition.sol";
import {RuleConditionConfiguredTest} from "../../../RuleConditionConfiguredTest.t.sol";
import {PluginACondition} from "../../../utils/dummy-plugins/PluginA/PluginACondition.sol";

import {
    RuledCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/extensions/RuledCondition.sol";

contract IsGranted_SPPRuleCondition_UnitTest is RuleConditionConfiguredTest {
    function test_WhenRulesAreEmpty() external view {
        // it should return true.

        assertTrue(
            ruleCondition.isGranted(
                address(sppPlugin),
                users.unauthorized,
                Permissions.CREATE_PROPOSAL_PERMISSION_ID,
                new bytes(0)
            )
        );
    }

    modifier whenRulesAreNotEmpty() {
        SPPRuleCondition.Rule[] memory rules = new SPPRuleCondition.Rule[](1);
        rules[0] = RuledCondition.Rule({
            id: CONDITION_RULE_ID,
            op: uint8(RuledCondition.Op.EQ),
            value: uint160(address(pluginACondition)), // condition address
            permissionId: Permissions.CREATE_PROPOSAL_PERMISSION_ID
        });

        ruleCondition.updateRules(rules);
        _;
    }

    function test_WhenEvaluationIsTrue() external whenRulesAreNotEmpty {
        // it should return true.

        // set who as member on plugin A
        PluginACondition(pluginACondition).PLUGIN_A().setMember(users.alice);

        assertTrue(
            ruleCondition.isGranted(
                address(sppPlugin),
                users.alice,
                Permissions.CREATE_PROPOSAL_PERMISSION_ID,
                new bytes(0)
            )
        );
    }

    function test_WhenEvaluationIsFalse() external whenRulesAreNotEmpty {
        // it should return false.

        assertFalse(
            ruleCondition.isGranted(
                address(sppPlugin),
                users.unauthorized, // it is not set as member on plugin A
                Permissions.CREATE_PROPOSAL_PERMISSION_ID,
                new bytes(0)
            )
        );
    }
}
