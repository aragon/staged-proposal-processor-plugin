// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {
    UPDATE_RULES_PERMISSION_ID,
    CREATE_PROPOSAL_PERMISSION_ID
} from "../../../utils/Permissions.sol";
import {SPPRuleCondition} from "../../../../src/utils/SPPRuleCondition.sol";
import {RuleConditionConfiguredTest} from "../../../RuleConditionConfiguredTest.t.sol";

import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {
    RuledCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/extensions/RuledCondition.sol";

contract UpdateRules_SPPRuleCondition_UnitTest is RuleConditionConfiguredTest {
    modifier whenUpdatingRules() {
        _;
    }

    modifier whenCallerIsAllowed() {
        _;
    }

    function test_RevertWhen_SomeConditionsCheckMsgData()
        external
        whenUpdatingRules
        whenCallerIsAllowed
    {
        // it should revert.

        SPPRuleCondition.Rule[] memory rules = new SPPRuleCondition.Rule[](1);
        // condition that checks msg.data
        rules[0] = RuledCondition.Rule({
            id: CONDITION_RULE_ID,
            op: uint8(RuledCondition.Op.EQ),
            value: uint160(address(pluginBCondition)), // condition address
            permissionId: CREATE_PROPOSAL_PERMISSION_ID
        });

        // low lever call should revert
        vm.expectRevert();
        ruleCondition.updateRules(rules);

        // check if the rules was not updated
        assertEq(ruleCondition.getRules(), new SPPRuleCondition.Rule[](0), "rules");
    }

    function test_WhenNoneConditionCheckMsgData() external whenUpdatingRules whenCallerIsAllowed {
        // it should update the conditions

        SPPRuleCondition.Rule[] memory rules = new SPPRuleCondition.Rule[](1);
        rules[0] = RuledCondition.Rule({
            id: CONDITION_RULE_ID,
            op: uint8(RuledCondition.Op.EQ),
            value: uint160(address(pluginACondition)), // condition address
            permissionId: CREATE_PROPOSAL_PERMISSION_ID
        });

        ruleCondition.updateRules(rules);

        assertEq(rules, ruleCondition.getRules(), "rules");
    }

    function test_RevertWhen_CallerIsNotAllowed() external whenUpdatingRules {
        // it should revert.

        resetPrank(users.unauthorized);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(ruleCondition),
                users.unauthorized,
                UPDATE_RULES_PERMISSION_ID
            )
        );
        ruleCondition.updateRules(new SPPRuleCondition.Rule[](0));
    }
}
