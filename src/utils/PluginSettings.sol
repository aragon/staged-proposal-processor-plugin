// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.18;

/// @title PluginSettings
/// @author Aragon X - 2024
/// @notice Provides constant values and metadata for the "StagedProposalProcessor" plugin,
///         including contract names, versioning, and IPFS metadata for builds and releases.
library PluginSettings {
    string public constant PLUGIN_CONTRACT_NAME = "StagedProposalProcessor";
    string public constant PLUGIN_SETUP_CONTRACT_NAME = "StagedProposalProcessorSetup";
    string public constant PLUGIN_REPO_ENS_SUBDOMAIN_NAME = "spp"; // 'spp.plugin.dao.eth'

    // Specify the version of your plugin that you are currently working on. The first version is v1.1.
    // For more details, visit https://devs.aragon.org/docs/osx/how-it-works/framework/plugin-management/plugin-repo.
    uint8 public constant VERSION_RELEASE = 1;
    uint8 public constant VERSION_BUILD = 1;
}
