// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

library PluginSettings {
    string constant PLUGIN_CONTRACT_NAME = "StagedProposalProcessor";
    string constant PLUGIN_SETUP_CONTRACT_NAME = "StagedProposalProcessorSetup";
    string constant PLUGIN_REPO_ENS_SUBDOMAIN_NAME = "testting"; // 'spp.plugin.dao.eth'

    // Specify the version of your plugin that you are currently working on. The first version is v1.1.
    // For more details, visit https://devs.aragon.org/docs/osx/how-it-works/framework/plugin-management/plugin-repo.
    uint8 constant VERSION_RELEASE = 1;
    uint8 constant VERSION_BUILD = 1;

    // todo load value from src/build and release metadata json
    bytes constant BUILD_METADATA = "dummy";
    bytes constant RELEASE_METADATA = "dummy";
}
