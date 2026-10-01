// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {NewVersion} from "../../../script/NewVersion.s.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

contract NewVersionHarness is NewVersion {
    // exposed function for internal `_requireNextBuild`
    function exposed_requireNextBuild(PluginRepo _repo) external view {
        _requireNextBuild(_repo);
    }
}
