// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {SPPRuleCondition} from "../../../../src/utils/SPPRuleCondition.sol";
import {RuleConditionConfiguredTest} from "../../../RuleConditionConfiguredTest.t.sol";

import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

contract Initialize_SPPRuleCondition_UnitTest is RuleConditionConfiguredTest {
    using ProxyLib for address;

    address internal sppRuleCondition;

    modifier whenDeployingAClone() {
        sppRuleCondition = ruleConditionImplementation.deployMinimalProxy(bytes(""));

        _;
    }

    modifier whenInitializing() {
        SPPRuleCondition.Rule[] memory rules = new SPPRuleCondition.Rule[](1);
        rules[0] = getDummyRule();

        vm.expectEmit({emitter: address(sppRuleCondition)});
        emit Initialized(1);
        SPPRuleCondition(sppRuleCondition).initialize(address(dao), rules);

        _;
    }

    function test_WhenNotInitialized() external whenDeployingAClone whenInitializing {
        // it should emit events.
        // it should initialize the contract.

        SPPRuleCondition.Rule[] memory rules = new SPPRuleCondition.Rule[](1);
        rules[0] = getDummyRule();

        // check initialization values are correct
        assertEq(SPPRuleCondition(sppRuleCondition).getRules(), rules, "rules");
    }

    function test_RevertWhen_Initialized() external whenDeployingAClone whenInitializing {
        // it should revert.

        vm.expectRevert("Initializable: contract is already initialized");
        SPPRuleCondition(sppRuleCondition).initialize(address(dao), new SPPRuleCondition.Rule[](0));
    }

    function test_WhenDeployingAContract() external {
        // it should initialize the contract on construction.

        SPPRuleCondition.Rule[] memory rules = new SPPRuleCondition.Rule[](1);
        rules[0] = getDummyRule();

        vm.expectEmit();
        emit Initialized(1);
        SPPRuleCondition deployedRuleCondition = new SPPRuleCondition(address(dao), rules);

        // check contract was initialized when deployed
        assertEq(SPPRuleCondition(deployedRuleCondition).getRules(), rules, "rules");
    }
}
