// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.18;

import {console} from "forge-std/console.sol";

import {BaseScript} from "./Base.sol";
import {PluginSettings} from "../src/utils/PluginSettings.sol";
import {StagedProposalProcessor as SPP} from "../src/StagedProposalProcessor.sol";
import {StagedProposalProcessorSetup as SPPSetup} from "../src/StagedProposalProcessorSetup.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";

/// @dev Minimal subset of the management DAO Multisig plugin ABI used by this script.
/// Mirrors the 7-arg `createProposal` overload (selector `0xfbd56e41`); using this typed
/// interface with `abi.encodeCall` makes the compiler enforce the signature match instead
/// of trusting a string we hand to `abi.encodeWithSignature`.
interface IManagementDaoMultisig {
    function createProposal(
        bytes calldata _metadata,
        Action[] calldata _actions,
        uint256 _allowFailureMap,
        bool _approveProposal,
        bool _tryExecution,
        uint64 _startDate,
        uint64 _endDate
    ) external returns (uint256 proposalId);
}

/// @notice Deploys a new SPPSetup implementation and prints both the inner
/// `createVersion` action and the outer management DAO multisig
/// `createProposal` calldata. Submit the printed multisig calldata from any
/// listed multisig member to publish this version.
contract NewVersion is BaseScript {
    function run() external {
        sppRepo = PluginRepo(vm.envAddress("SPP_PLUGIN_REPO_ADDRESS"));
        address managementDaoMultisig = vm.envAddress("MANAGEMENT_DAO_MULTISIG_ADDRESS");

        // Reuse the previous build's plugin implementation. v1.2's bytecode is identical to v1.1's
        SPP existingImpl = _readLatestImplementation();

        vm.startBroadcast(deployerPrivateKey);
        sppSetup = new SPPSetup(existingImpl);
        vm.stopBroadcast();

        console.log("- SPP PluginSetup:           ", address(sppSetup));
        console.log(
            "- Version:                   ",
            _versionString(PluginSettings.VERSION_RELEASE, PluginSettings.VERSION_BUILD)
        );

        bytes memory createVersionData = abi.encodeCall(
            sppRepo.createVersion,
            (
                PluginSettings.VERSION_RELEASE,
                address(sppSetup),
                bytes(PluginSettings.BUILD_METADATA),
                bytes(PluginSettings.RELEASE_METADATA)
            )
        );

        console.log("\nDAO action to publish this version:");
        console.log("  to:    ", address(sppRepo));
        console.log("  value: 0");
        console.log("  data:  ");
        console.logBytes(createVersionData);

        // Wrap the action in a management DAO multisig proposal. The 7-arg
        // `createProposal` is the multisig-specific overload; passing
        // `_approveProposal=true` means the submitter also casts their vote
        // in the same transaction.
        Action[] memory actions = new Action[](1);
        actions[0] = Action({to: address(sppRepo), value: 0, data: createVersionData});

        bytes memory metadata = bytes(PluginSettings.PROPOSAL_METADATA);
        uint64 endDate = uint64(vm.envOr("PROPOSAL_END_DATE", block.timestamp + 30 days));
        bytes memory multisigCalldata = abi.encodeCall(
            IManagementDaoMultisig.createProposal,
            (
                metadata,
                actions,
                uint256(0), // _allowFailureMap
                true, // _approveProposal
                false, // _tryExecution
                uint64(0), // _startDate (0 = now, evaluated at submission time)
                endDate
            )
        );

        // The Multisig derives proposalId as
        //   keccak256(abi.encode(chainid, block.number, multisig, keccak256(abi.encode(actions, metadata))))
        // (see Multisig.createProposal -> Proposal._createProposalId in osx-commons).
        // Submission block isn't known at script time, so we print the deterministic
        // salt; the actual proposalId is also surfaced via the `ProposalCreated` event
        // on the submission tx receipt.
        bytes32 proposalSalt = keccak256(abi.encode(actions, metadata));

        console.log("\nManagement DAO multisig proposal to publish this version:");
        console.log("  to:    ", managementDaoMultisig);
        console.log("  value: 0");
        console.log("  data:  ");
        console.logBytes(multisigCalldata);
        console.log("\n  proposal metadata: ", PluginSettings.PROPOSAL_METADATA);
        console.log("  defaults: allowFailureMap=0, approveProposal=true, tryExecution=false, startDate=0");
        console.log("  endDate (unix):    ", uint256(endDate));
        console.log("\n  proposal id (deterministic salt):");
        console.logBytes32(proposalSalt);
        console.log("  full id = keccak256(abi.encode(chainid, block.number @ submission, multisig, salt))");
        console.log("  or read it from the `ProposalCreated` event on the submission tx receipt.");
    }

    function _readLatestImplementation() internal view returns (SPP) {
        uint8 latestRelease = sppRepo.latestRelease();
        uint16 latestBuild = uint16(sppRepo.buildCount(latestRelease));
        PluginRepo.Tag memory latestTag = PluginRepo.Tag({release: latestRelease, build: latestBuild});
        address latestSetup = sppRepo.getVersion(latestTag).pluginSetup;
        return SPP(IPluginSetup(latestSetup).implementation());
    }
}
