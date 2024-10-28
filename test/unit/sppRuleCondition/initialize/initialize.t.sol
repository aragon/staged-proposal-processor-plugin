// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../BaseTest.t.sol";
import {SPPRuleCondition} from "../../../../src/utils/SPPRuleCondition.sol";
import {CREATE_PROPOSAL_PERMISSION_ID} from "../../../utils/Permissions.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {
    PowerfulCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/PowerfulCondition.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

contract Initialize_SPPRuleCondition_UnitTest is BaseTest {
    using ProxyLib for address;

    PowerfulCondition.Rule dummyRule =
        PowerfulCondition.Rule({
            id: 1,
            op: 1,
            value: 55,
            permissionId: CREATE_PROPOSAL_PERMISSION_ID
        });

    address internal ruleConditionImplementation;
    address internal sppRuleCondition;

    modifier whenDeployingAClone() {
        ruleConditionImplementation = address(
            new SPPRuleCondition(address(0), new PowerfulCondition.Rule[](0))
        );
        sppRuleCondition = ruleConditionImplementation.deployMinimalProxy(bytes(""));

        _;
    }

    modifier whenInitializing() {
        SPPRuleCondition.Rule[] memory rules = new SPPRuleCondition.Rule[](1);
        rules[0] = dummyRule;

        vm.expectEmit({emitter: address(sppRuleCondition)});
        emit Initialized(1);
        SPPRuleCondition(sppRuleCondition).initialize(address(dao), rules);

        _;
    }

    function test_WhenNotInitialized() external whenDeployingAClone whenInitializing {
        // it should emit events.
        // it should initialize the contract.

        // // check event
        // vm.expectEmit({emitter: address(sppRuleCondition)});
        // emit Initialized(1);

        // SPPRuleCondition(sppRuleCondition).initialize(address(dao), rules);

        SPPRuleCondition.Rule[] memory rules = new SPPRuleCondition.Rule[](1);
        rules[0] = dummyRule;

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
        rules[0] = dummyRule;

        vm.expectEmit();
        emit Initialized(1);
        SPPRuleCondition deployedRuleCondition = new SPPRuleCondition(address(dao), rules);

        // check contract was initialized when deployed
        assertEq(SPPRuleCondition(deployedRuleCondition).getRules(), rules, "rules");
    }
}
