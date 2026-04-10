// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.18;

import {console} from "forge-std/console.sol";

import {BaseScript} from "./Base.sol";
import {PluginSettings} from "../src/utils/PluginSettings.sol";
import {StagedProposalProcessor as SPP} from "../src/StagedProposalProcessor.sol";
import {StagedProposalProcessorSetup as SPPSetup} from "../src/StagedProposalProcessorSetup.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

/// @notice Deploys a new SPPSetup implementation and prints the DAO proposal calldata.
/// Submit the printed calldata as a management DAO proposal to publish the new version.
contract NewVersion is BaseScript {
    function run() external {
        sppRepo = PluginRepo(vm.envAddress("SPP_PLUGIN_REPO_ADDRESS"));

        vm.startBroadcast(deployerPrivateKey);
        sppSetup = new SPPSetup(new SPP());
        vm.stopBroadcast();

        console.log("- SPP PluginSetup:  ", address(sppSetup));
        console.log(
            "- Version:          ",
            _versionString(PluginSettings.VERSION_RELEASE, PluginSettings.VERSION_BUILD)
        );
        console.log("\nDAO proposal to publish this version:");
        console.log("  to:    ", address(sppRepo));
        console.log("  value: ", uint256(0));
        console.logBytes(
            abi.encodeWithSelector(
                sppRepo.createVersion.selector,
                PluginSettings.VERSION_RELEASE,
                address(sppSetup),
                PluginSettings.BUILD_METADATA,
                PluginSettings.RELEASE_METADATA
            )
        );
    }
}
