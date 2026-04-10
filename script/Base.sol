// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";

import {StagedProposalProcessorSetup as SPPSetup} from "../src/StagedProposalProcessorSetup.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

contract BaseScript is Script {
    SPPSetup public sppSetup;
    PluginRepo public sppRepo;

    uint256 internal deployerPrivateKey = vm.envUint("DEPLOYER_KEY");

    // solhint-disable immutable-vars-naming
    address internal immutable deployer = vm.addr(deployerPrivateKey);

    function _versionString(uint8 _release, uint8 _build) internal pure returns (string memory) {
        return string(abi.encodePacked("v", vm.toString(_release), ".", vm.toString(_build)));
    }
}
