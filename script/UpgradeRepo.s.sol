// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {console} from "forge-std/console.sol";

import {BaseScript} from "./Base.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

contract UpgradeRepo is BaseScript {
    error UpgradingToSameVersion(uint8[3] currentProtocolVersion, uint8[3] latestProtocolVersion);
    error InvalidUpgradeVersion(uint8[3] currentProtocolVersion, uint8[3] latestProtocolVersion);
    error NotAllowed(address user);

    function run() external {
        _printAragonArt();

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

        if (isDeployerAllowed) {
            // upgrade the repo
            sppRepo.upgradeTo(address(latestBaseRepo));
            console.log("Repo upgraded to version", _protocolVersionString(latestProtocolVersion));
        } else {
            revert NotAllowed(deployer);
        }
        vm.stopBroadcast();
    }
}
