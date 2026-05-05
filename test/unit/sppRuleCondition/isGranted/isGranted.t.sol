// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Permissions} from "../../../../src/libraries/Permissions.sol";
import {SPPRuleCondition} from "../../../../src/utils/SPPRuleCondition.sol";
import {RuleConditionConfiguredTest} from "../../../RuleConditionConfiguredTest.t.sol";
import {PluginACondition} from "../../../utils/dummy-plugins/PluginA/PluginACondition.sol";

import {
    RuledCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/extensions/RuledCondition.sol";
import {
    AddressCheckConditionMock
} from "@aragon/osx-commons-contracts/src/mocks/permission/condition/AddressCheckConditionMock.sol";

contract IsGranted_SPPRuleCondition_UnitTest is RuleConditionConfiguredTest {
    // Rule IDs not exposed via the SPP test Constants
    uint8 internal constant LOGIC_OP_RULE_ID = 203;
    uint8 internal constant VALUE_RULE_ID = 204;

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

    AddressCheckConditionMock internal addressCheckCondition;

    modifier whenRuleIsIfElseWithAsymmetricPredicate() {
        addressCheckCondition = new AddressCheckConditionMock();
        // The predicate is true only when (_where == sppPlugin, _who == alice).
        // Swapping the two would compare (alice, sppPlugin) against the same
        // expected pair and return false.
        addressCheckCondition.setExpected(address(sppPlugin), users.alice);

        SPPRuleCondition.Rule[] memory rules = new SPPRuleCondition.Rule[](4);

        // rule 0: IF_ELSE(predicate=1, success=2, failure=3) — entry point.
        rules[0] = RuledCondition.Rule({
            id: LOGIC_OP_RULE_ID,
            op: uint8(RuledCondition.Op.IF_ELSE),
            value: ruleCondition.encodeIfElse(1, 2, 3),
            permissionId: Permissions.CREATE_PROPOSAL_PERMISSION_ID
        });

        // rule 1: predicate — asymmetric condition that cares about both addresses.
        rules[1] = RuledCondition.Rule({
            id: CONDITION_RULE_ID,
            op: uint8(RuledCondition.Op.EQ),
            value: uint160(address(addressCheckCondition)),
            permissionId: Permissions.CREATE_PROPOSAL_PERMISSION_ID
        });

        // rule 2: success branch — VALUE_RULE_ID + RET with value=1 → always true.
        rules[2] = RuledCondition.Rule({
            id: VALUE_RULE_ID,
            op: uint8(RuledCondition.Op.RET),
            value: 1,
            permissionId: Permissions.CREATE_PROPOSAL_PERMISSION_ID
        });

        // rule 3: failure branch — VALUE_RULE_ID + RET with value=0 → always false.
        rules[3] = RuledCondition.Rule({
            id: VALUE_RULE_ID,
            op: uint8(RuledCondition.Op.RET),
            value: 0,
            permissionId: Permissions.CREATE_PROPOSAL_PERMISSION_ID
        });

        ruleCondition.updateRules(rules);
        _;
    }

    function test_WhenIfElsePredicateMatches_ItRoutesToSuccessBranch()
        external
        whenRuleIsIfElseWithAsymmetricPredicate
    {
        // it should evaluate the predicate with (_where, _who) in the correct
        // order, take the success branch, and return true.

        assertTrue(
            ruleCondition.isGranted(
                address(sppPlugin), // _where — matches expectedWhere
                users.alice, // _who — matches expectedWho
                Permissions.CREATE_PROPOSAL_PERMISSION_ID,
                new bytes(0)
            ),
            "IF_ELSE predicate should match and route to success branch"
        );
    }

    function test_WhenIfElsePredicateDoesNotMatch_ItRoutesToFailureBranch()
        external
        whenRuleIsIfElseWithAsymmetricPredicate
    {
        // it should take the failure branch when the predicate is false.

        assertFalse(
            ruleCondition.isGranted(
                address(sppPlugin),
                users.bob, // _who differs from expectedWho
                Permissions.CREATE_PROPOSAL_PERMISSION_ID,
                new bytes(0)
            ),
            "IF_ELSE predicate should not match and route to failure branch"
        );
    }

    function test_WhenIfElseCallerSwapsWhereAndWho_PredicateMustNotMatch()
        external
        whenRuleIsIfElseWithAsymmetricPredicate
    {
        // If the caller passes the addresses in the opposite order, the predicate 
        // sees (_where=alice, _who=sppPlugin), which must not match the expected
        // (sppPlugin, alice) pair. With the bug present, _evalLogic would
        // swap them back internally and the predicate would incorrectly
        // evaluate to true, taking the success branch.

        assertFalse(
            ruleCondition.isGranted(
                users.alice, // _where (intentionally swapped)
                address(sppPlugin), // _who (intentionally swapped)
                Permissions.CREATE_PROPOSAL_PERMISSION_ID,
                new bytes(0)
            ),
            "Swapped where/who must not satisfy the asymmetric IF_ELSE predicate"
        );
    }
}
