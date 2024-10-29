// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {
    UPDATE_RULES_PERMISSION_ID,
    CREATE_PROPOSAL_PERMISSION_ID
} from "../../../utils/Permissions.sol";
import {SPPRuleCondition} from "../../../../src/utils/SPPRuleCondition.sol";
import {RuleConditionConfiguredTest} from "../../../RuleConditionConfiguredTest.t.sol";
import {PluginACondition} from "../../../utils/dummy-plugins/PluginA/PluginACondition.sol";

import {
    PowerfulCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/PowerfulCondition.sol";

contract IsGranted_SPPRuleCondition_UnitTest is RuleConditionConfiguredTest {
    function test_WhenRulesAreEmpty() external {
        // it should return true.

        assertTrue(
            ruleCondition.isGranted(
                address(sppPlugin),
                users.unauthorized,
                CREATE_PROPOSAL_PERMISSION_ID,
                new bytes(0)
            )
        );
    }

    modifier whenRulesAreNotEmpty() {
        SPPRuleCondition.Rule[] memory rules = new SPPRuleCondition.Rule[](1);
        rules[0] = PowerfulCondition.Rule({
            id: CONDITION_RULE_ID,
            op: uint8(PowerfulCondition.Op.EQ),
            value: uint160(address(pluginACondition)), // condition address
            permissionId: CREATE_PROPOSAL_PERMISSION_ID
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
                CREATE_PROPOSAL_PERMISSION_ID,
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
                CREATE_PROPOSAL_PERMISSION_ID,
                new bytes(0)
            )
        );
    }
}
