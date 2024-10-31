// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {BaseScript} from "./Base.sol";

import {PluginSettings} from "../src/utils/PluginSettings.sol";
import {StagedProposalProcessorSetup as SPPSetup} from "../src/StagedProposalProcessorSetup.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

contract UpgradeRepo is BaseScript {
    error UpgradingToSameVersion(uint8[3] currentProtocolVersion, uint8[3] latestProtocolVersion);
    error InvalidUpgradeVersion(uint8[3] currentProtocolVersion, uint8[3] latestProtocolVersion);
    error NotAllowed(address user);

    function run() external {
        // get deployed contracts
        PluginRepo latestBaseRepo = PluginRepo(getBasePluginRepoAddress());
        sppRepo = PluginRepo(getPluginRepoAddress());

        // check if update is possible
        uint8[3] memory currentProtocolVersion = sppRepo.protocolVersion();
        uint8[3] memory latestProtocolVersion = latestBaseRepo.protocolVersion();

        if (
            keccak256(abi.encode(currentProtocolVersion)) ==
            keccak256(abi.encode(latestProtocolVersion))
        ) {
            revert UpgradingToSameVersion(currentProtocolVersion, latestProtocolVersion);
        }

        if (
            currentProtocolVersion[0] > latestProtocolVersion[0] ||
            currentProtocolVersion[1] > latestProtocolVersion[1] ||
            currentProtocolVersion[2] > latestProtocolVersion[2]
        ) {
            revert InvalidUpgradeVersion(currentProtocolVersion, latestProtocolVersion);
        }

        bool isDeployerAllowed = sppRepo.isGranted(
            address(sppRepo),
            address(deployer),
            sppRepo.UPGRADE_REPO_PERMISSION_ID(),
            new bytes(0)
        );

        vm.startBroadcast(deployerPrivateKey);

        SPPSetup sppSetup;
        if (isDeployerAllowed) {
            // upgrade the repo
            sppRepo.upgradeTo(address(latestBaseRepo));
        } else {
            sppSetup = new SPPSetup();
            revert NotAllowed(deployer);
        }
        vm.stopBroadcast();
    }
}
