// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {
    UPDATE_RULES_PERMISSION_ID,
    CREATE_PROPOSAL_PERMISSION_ID
} from "../../../utils/Permissions.sol";
import {PluginA} from "../../../utils/dummy-plugins/PluginA.sol";
import {PluginB} from "../../../utils/dummy-plugins/PluginB.sol";
import {PluginACondition} from "../../../utils/dummy-plugins/PluginACondition.sol";
import {PluginBCondition} from "../../../utils/dummy-plugins/PluginBCondition.sol";
import {BaseTest} from "../../../BaseTest.t.sol";
import {SPPRuleCondition} from "../../../../src/utils/SPPRuleCondition.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {
    PowerfulCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/PowerfulCondition.sol";

contract UpdateRules_SPPRuleCondition_UnitTest is BaseTest {
    SPPRuleCondition public ruleCondition;
    PluginACondition public pluginACondition;
    PluginBCondition public pluginBCondition;

    function setUp() public override {
        super.setUp();

        // set condition and grant permissions
        ruleCondition = new SPPRuleCondition();
        ruleCondition.initialize(address(dao), new SPPRuleCondition.Rule[](0));

        DAO(payable(address(dao))).grant({
            _where: address(ruleCondition),
            _who: users.manager,
            _permissionId: UPDATE_RULES_PERMISSION_ID
        });

        // deploy dummy plugins conditions
        pluginACondition = new PluginACondition(address(new PluginA(defaultTargetConfig)));
        pluginBCondition = new PluginBCondition(address(new PluginB(address(0))));
    }

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
        rules[0] = PowerfulCondition.Rule({
            id: 202, // condition rule id
            op: 0, // NONE
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
        rules[0] = PowerfulCondition.Rule({
            id: 202, // condition rule id
            op: 0, // NONE
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
                ruleCondition.UPDATE_RULES_PERMISSION_ID()
            )
        );
    }
}
