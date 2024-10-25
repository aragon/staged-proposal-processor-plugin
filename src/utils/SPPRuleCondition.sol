// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {PowerfulCondition} from "@aragon/osx-commons-contracts/src/permission/condition/PowerfulCondition.sol";

import {
    DaoAuthorizable
} from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizable.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {
    IPermissionCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/IPermissionCondition.sol";

contract SPPCondition is DaoAuthorizable, PowerfulCondition {
    using Address for address;

    /// @notice The ID of the permission required to call the `updateRules` function.
    bytes32 public constant UPDATE_RULES_PERMISSION_ID = keccak256("UPDATE_RULES_PERMISSION");

    constructor(address dao, Rule[] memory rules) DaoAuthorizable(IDAO(dao)) {
        if (rules.length != 0) {
            _updateRules(rules);
        }
    }

    /// @inheritdoc IPermissionCondition
    function isGranted(
        address _where,
        address _who,
        bytes32 _permissionId,
        bytes calldata
    ) external view returns (bool isPermitted) {
        if (getRules().length == 0) {
            return true;
        }

        return _evalRule(0, _where, _who, _permissionId, new uint256[](0));
    }

    /// @notice Internal function that updates the rules. 
    /// @param _rules The rules that decide who can create a proposal on `StagedProposalProcessor`.
    function _updateRules(Rule[] memory _rules) internal override {
        for (uint256 i = 0; i < _rules.length; i++) {
            Rule memory rule = _rules[i];

            // Make sure that `isGranted` doesn't revert 
            // in case empty bytes data is provided.
            // Since SPP can not always predict what the `data` 
            // should be for each sub-plugin. We make sure that 
            // only those conditions that don't depend on `data` param are allowed.
            if (rule.id == CONDITION_RULE_ID) {
                bytes memory data = abi.encodeCall(
                    IPermissionCondition.isGranted,
                    (address(1), address(2), bytes32(uint256(1)), bytes(""))
                );

                address condition = address(uint160(rule.value));

                condition.functionStaticCall(data);
            }
        }

        super._updateRules(_rules);
    }

    /// @notice Updates the rules that will be used as a check upon proposal creation on `StagedProposalProcessor`.
    /// @param _rules The rules that decide who can create a proposal on `StagedProposalProcessor`.
    function updateRules(Rule[] calldata _rules) public auth(UPDATE_RULES_PERMISSION_ID) {
        _updateRules(_rules);
    }
}
