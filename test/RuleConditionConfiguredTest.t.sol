// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {BaseTest} from "./BaseTest.t.sol";
import {PluginA} from "./utils/dummy-plugins/PluginA/PluginA.sol";
import {PluginB} from "./utils/dummy-plugins/PluginB/PluginB.sol";
import {SPPRuleCondition} from "../src/utils/SPPRuleCondition.sol";
import {PluginACondition} from "./utils/dummy-plugins/PluginA/PluginACondition.sol";
import {PluginBCondition} from "./utils/dummy-plugins/PluginB/PluginBCondition.sol";
import {Permissions} from "../src/libraries/Permissions.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {
    RuledCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/extensions/RuledCondition.sol";

abstract contract RuleConditionConfiguredTest is BaseTest {
    address internal ruleConditionImplementation;

    SPPRuleCondition public ruleCondition;
    PluginACondition public pluginACondition;
    PluginBCondition public pluginBCondition;

    function setUp() public virtual override {
        super.setUp();

        ruleConditionImplementation = address(
            new SPPRuleCondition(address(0), new RuledCondition.Rule[](0))
        );

        // deploy rule condition
        ruleCondition = new SPPRuleCondition(address(dao), new RuledCondition.Rule[](0));

        // grant permission to update rules
        DAO(payable(address(dao))).grant({
            _where: address(ruleCondition),
            _who: users.manager,
            _permissionId: Permissions.UPDATE_RULES_PERMISSION_ID
        });

        // deploy dummy plugins conditions
        pluginACondition = new PluginACondition(address(new PluginA(defaultTargetConfig)));
        pluginBCondition = new PluginBCondition(address(new PluginB(address(0))));
    }

    function getDummyRule() internal pure returns (RuledCondition.Rule memory) {
        return
            RuledCondition.Rule({
                id: 1,
                op: 1,
                value: 55,
                permissionId: Permissions.CREATE_PROPOSAL_PERMISSION_ID
            });
    }
}
