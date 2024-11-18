// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.28;

import {PluginA} from "./PluginA.sol";

import {
    PermissionCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/PermissionCondition.sol";

contract PluginACondition is PermissionCondition {
    PluginA public immutable PLUGIN_A;

    constructor(address _pluginA) {
        PLUGIN_A = PluginA(_pluginA);
    }

    function isGranted(
        address _where,
        address _who,
        bytes32 _permissionId,
        bytes calldata _data
    ) public view override returns (bool) {
        (_where, _data, _permissionId);

        return PLUGIN_A.isMember(_who);
    }
}
