// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {NewVersion} from "../../../script/NewVersion.s.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

contract NewVersionHarness is NewVersion {
    // exposed function for internal `_buildsToPublish`
    function exposed_buildsToPublish(PluginRepo _repo) external view returns (uint256) {
        return _buildsToPublish(_repo);
    }

    // exposed function for internal `_createVersionActions`
    function exposed_createVersionActions(
        PluginRepo _repo,
        address _setup,
        uint256 _count
    ) external pure returns (Action[] memory) {
        return _createVersionActions(_repo, _setup, _count);
    }
}
