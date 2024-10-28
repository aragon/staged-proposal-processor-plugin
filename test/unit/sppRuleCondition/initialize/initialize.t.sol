// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../BaseTest.t.sol";
import {SPPRuleCondition} from "../../../../src/utils/SPPRuleCondition.sol";
import {CREATE_PROPOSAL_PERMISSION_ID} from "../../../utils/Permissions.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {
    PowerfulCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/PowerfulCondition.sol";

contract Initialize_SPPRuleCondition_UnitTest is BaseTest {
    SPPRuleCondition internal newRuleCondition;

    function setUp() public override {
        super.setUp();

        // deploy new SPP plugin without initializing it.
        newRuleCondition = new SPPRuleCondition();
    }

    modifier whenInitialized() {
        newRuleCondition.initialize(address(dao), new SPPRuleCondition.Rule[](0));
        _;
    }

    function test_RevertWhen_Reinitializing() external whenInitialized {
        // it should revert.

        vm.expectRevert("Initializable: contract is already initialized");
        newRuleCondition.initialize(address(dao), new SPPRuleCondition.Rule[](0));
    }

    modifier whenNotInitialized() {
        _;
    }

    modifier whenInitializing() {
        _;
    }

    function test_WhenInitializing() external whenNotInitialized whenInitializing {
        // it should emit events.
        // it should initialize the contract.

        // check event
        vm.expectEmit({emitter: address(newRuleCondition)});
        emit Initialized(1);

        SPPRuleCondition.Rule[] memory rules = new SPPRuleCondition.Rule[](1);
        rules[0] = PowerfulCondition.Rule({
            id: 1,
            op: 1,
            value: 55,
            permissionId: CREATE_PROPOSAL_PERMISSION_ID
        });

        newRuleCondition.initialize(address(dao), rules);

        // check initialization values are correct
        assertEq(newRuleCondition.getRules(), rules, "rules");
    }
}
