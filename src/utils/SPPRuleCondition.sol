// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.18;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {
    IPermissionCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/IPermissionCondition.sol";
import {
    DaoAuthorizableUpgradeable
} from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";
import {
    RuledCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/extensions/RuledCondition.sol";

/// @title SPPRuleCondition
/// @author Aragon X - 2024
/// @notice The SPP Condition that must be granted for `createProposal` function of `StagedProposalProcessor`.
/// @dev This contract must be deployed either with clonable or `new` keyword.
contract SPPRuleCondition is DaoAuthorizableUpgradeable, RuledCondition {
    using Address for address;

    /// @notice The ID of the permission required to call the `updateRules` function.
    bytes32 public constant UPDATE_RULES_PERMISSION_ID = keccak256("UPDATE_RULES_PERMISSION");

    /// @notice Disables the initializers on the implementation contract to prevent it from being left uninitialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _dao, Rule[] memory _rules) {
        initialize(_dao, _rules);
    }

    /// @notice Initializes the component.
    /// @param _dao The IDAO interface of the associated DAO.
    /// @param _rules The rules that decide who can create a proposal on `StagedProposalProcessor`.
    function initialize(address _dao, Rule[] memory _rules) public initializer {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));
        if (_rules.length != 0) {
            _updateRules(_rules);
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
        for (uint256 i = 0; i < _rules.length; ++i) {
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
