// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {
    PermissionCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/PermissionCondition.sol";

contract AlwaysTrueCondition is PermissionCondition {
    function isGranted(
        address _where,
        address _who,
        bytes32 _permissionId,
        bytes calldata _data
    ) public pure override returns (bool) {
        (_where, _who, _permissionId, _data);
        return true;
    }
}
