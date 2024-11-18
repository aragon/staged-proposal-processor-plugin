// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.18;

import {PluginB} from "./PluginB.sol";

import {
    PermissionCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/PermissionCondition.sol";

contract PluginBCondition is PermissionCondition {
    PluginB private immutable PLUGIN_B;

    constructor(address _pluginB) {
        PLUGIN_B = PluginB(_pluginB);
    }

    function isGranted(
        address _where,
        address _who,
        bytes32 _permissionId,
        bytes calldata _data
    ) public view override returns (bool) {
        (_where, _data, _permissionId);

        return PLUGIN_B.hasPermission(_who, _data);
    }
}
