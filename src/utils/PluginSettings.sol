// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.18;

/// @title PluginSettings
/// @author Aragon X - 2024
/// @notice Provides constant values and metadata for the "StagedProposalProcessor" plugin,
///         including contract names, versioning, and IPFS metadata for builds and releases.
library PluginSettings {
    string public constant PLUGIN_CONTRACT_NAME = "StagedProposalProcessor";
    string public constant PLUGIN_SETUP_CONTRACT_NAME = "StagedProposalProcessorSetup";
    string public constant PLUGIN_REPO_ENS_SUBDOMAIN_NAME = "spp";

    // Specify the version of your plugin that you are currently working on. The first version is v1.1.
    // For more details, visit https://devs.aragon.org/docs/osx/how-it-works/framework/plugin-management/plugin-repo.
    uint8 public constant VERSION_RELEASE = 1;
    uint8 public constant VERSION_BUILD = 2;

    // Per-build flow when bumping VERSION_BUILD (or VERSION_RELEASE):
    // 1. Edit the matching JSON file:
    //      - `src/build-metadata.json`                       → BUILD_METADATA
    //      - `script/new-version-proposal-metadata.json`     → PROPOSAL_METADATA
    //      - `src/release-metadata.json` (only on a new release) → RELEASE_METADATA
    // 2. Pin via `just ipfs-pin <path>`.
    // 3. Paste the returned `ipfs://<cid>` into the matching constant below.

    string public constant BUILD_METADATA =
        "ipfs://QmaxGSvvnTAZcDLYz2BMtaXmcx3i1GcaKGaxNEpfQe3Vyv";
    string public constant RELEASE_METADATA =
        "ipfs://bafkreif23p6yw325rkwwlhgkudiasvq64lonqmfnt7ls5ksfam5hedcb4m";

    /// @notice Title/summary/description/resources JSON pinned for this version's management DAO proposal.
    /// @dev Re-pin and update on every VERSION_BUILD bump. Source: `script/new-version-proposal-metadata.json`.
    string public constant PROPOSAL_METADATA =
        "ipfs://QmTS3Nrjrs8nuMeqUqSRjBxbGUhZB4nW6N1GiK8vFmfDcD";

    /// @notice Aragon's canonical empty-schema placeholder build metadata, used when filling skipped builds
    /// on a fresh-network deploy so on-chain build numbers stay aligned across networks.
    /// @dev Content-addressed; the file at `lib/osx/.../placeholder/placeholder-build-metadata.json` always pins to this CID.
    string public constant PLACEHOLDER_BUILD_METADATA =
        "ipfs://QmZDx8G5xuF9vqVbFGZ3KhF5nioL8gXwV3JbsEsSHvNMiz";
}
