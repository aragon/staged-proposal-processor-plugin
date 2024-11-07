// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

contract Constants {
    // solhint-disable max-line-length
    string public constant ARAGON_OSX_ASCII_ART =
        "                                        ____   _____      \n     /\\                                  / __ \\ / ____|     \n    /  \\   _ __ __ _  __ _  ___  _ __   | |  | | (_____  __ \n   / /\\ \\ | '__/ _` |/ _` |/ _ \\| '_ \\  | |  | |\\___ \\ \\/ / \n  / ____ \\| | | (_| | (_| | (_) | | | | | |__| |____) >  <  \n /_/    \\_\\_|  \\__,_|\\__, |\\___/|_| |_|  \\____/|_____/_/\\_\\ \n                      __/ |                                 \n                     |___/                                  \n";
    string public constant DEPLOYMENTS_PATH =
        "node_modules/@aragon/osx-commons-configs/dist/deployments/json";

    string public constant PLUGIN_FACTORY_ADDRESS_KEY = "PluginRepoFactory.address";
    string public constant MANAGEMENT_DAO_ADDRESS_KEY = "ManagementDAOProxy.address";
    string public constant DAO_FACTORY_ADDRESS_KEY = "DAOFactory.address";
    string public constant SPP_PLUGIN_REPO_KEY = "StagedProposalProcessorRepoProxy.address";
    string public constant BASE_PLUGIN_REPO_KEY = "PluginRepoBase.address";
}
