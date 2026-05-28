// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {PermissionCondition} from "@aragon/osx-commons-contracts/src/permission/condition/PermissionCondition.sol";

/// @notice A mock that returns true only when both `_where` and `_who` match the configured addresses.
/// @dev DO NOT USE IN PRODUCTION!
contract AddressCheckConditionMock is PermissionCondition {
    address public expectedWhere;
    address public expectedWho;

    function setExpected(address _expectedWhere, address _expectedWho) external {
        expectedWhere = _expectedWhere;
        expectedWho = _expectedWho;
    }

    function isGranted(
        address _where,
        address _who,
        bytes32 _permissionId,
        bytes memory _data
    ) external view returns (bool) {
        (_permissionId, _data);
        return _where == expectedWhere && _who == expectedWho;
    }
}
