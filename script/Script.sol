// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";

import {BaseScript} from "./Base.sol";

import {PluginSettings} from "../src/utils/PluginSettings.sol";
import {StagedProposalProcessorSetup as SPPSetup} from "../src/StagedProposalProcessorSetup.sol";

import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";

import "forge-std/console.sol";

import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

contract Scriptt is Script {
    uint256 internal deployerPrivateKey = vm.envUint("DEPLOYER_KEY");

    address managingDao = 0x61fc858Cf5a40c5b77909Fe22d05A5Af5539b6e0;

    address multisigPlugin = 0x7e7e8D9CAd2Ad08A713A28Fee11B2307180204D8;
    address adminRepo = 0xEdA3074437375DC71007AFC9D421644656d72287;
    address multisigRepo = 0xA0901B5BC6e04F14a9D0d094653E047644586DdE;
    address tokenVotingRepo = 0x6241ad0D3f162028d2e0000f1A878DBc4F5c4aD0;
    address sppRepo = 0xE67b8E026d190876704292442A38163Ce6945d6b;

    function run1() external {
        // get deployed contracts

        vm.startBroadcast(deployerPrivateKey);

        // deploy spp setup

        // SPPSetup sppSetup = new SPPSetup();

        // console.log("SPP setup", address(sppSetup));
        // 0xc325750d32dc0bBfc890D10B8D49BA55648eEF72
        // 4
        Action[] memory actions = new Action[](1);

        actions[0] = Action({
            to: sppRepo,
            data: hex"fc0544270000000000000000000000000000000000000000000000000000000000000001000000000000000000000000b0bc62562b3ad65592424b42f831c71d0cc4e8f5000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000564756d6d79000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000564756d6d79000000000000000000000000000000000000000000000000000000",
            // data: abi.encodeWithSelector(
            //     PluginRepo.createVersion.selector,
            //     1,
            //     sppSetup,
            //     abi.encode("dummy"),
            //     abi.encode("dummy")
            // ),
            value: 0
        });

        uint256 proposalId = IMultisig(multisigPlugin).createProposal(
            abi.encodePacked("Publish 'SPP' plugin v1.6"),
            actions,
            0,
            false,
            false,
            uint64(block.timestamp) + 1 minutes,
            uint64(block.timestamp) + 1 days
        );
        vm.stopBroadcast();

        console.log("Proposal ID: %d", proposalId);
    }

    function run() external {
        vm.startBroadcast(deployerPrivateKey);
        IMultisig(multisigPlugin).approve(17, true);
        vm.stopBroadcast();
    }
}

interface IMultisig {
    function createProposal(
        bytes memory _description,
        Action[] memory _actions,
        uint256 _approvalThreshold,
        bool _isCancelable,
        bool _isTimed,
        uint64 _startDate,
        uint64 _endDate
    ) external returns (uint256);

    function approve(uint256 _proposalId, bool _approval) external;
}
