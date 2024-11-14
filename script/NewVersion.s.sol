// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseScript} from "./Base.sol";
import {PluginSettings} from "../src/utils/PluginSettings.sol";
import {StagedProposalProcessorSetup as SPPSetup} from "../src/StagedProposalProcessorSetup.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

contract NewVersion is BaseScript {
    struct ProposalData {
        string title;
        string description;
        Action[] actions;
    }

    function run() external {
        _printAragonArt();
        // get deployed contracts
        sppRepo = PluginRepo(getPluginRepoAddress());
        managementDao = getManagementDaoAddress();

        // check if the deployer is maintainer of the repo

        bool isDeployerMaintainer = sppRepo.isGranted(
            address(sppRepo),
            address(deployer),
            sppRepo.MAINTAINER_PERMISSION_ID(),
            new bytes(0)
        );

        vm.startBroadcast(deployerPrivateKey);

        SPPSetup sppSetup;
        if (isDeployerMaintainer) {
            // if deployer has permission create new version
            _createAndCheckNewVersion();
        } else {
            sppSetup = new SPPSetup();
            string memory json = _serializeToJson(_buildProposalData(address(sppSetup)));

            // Write the serialized JSON data to a file
            string memory filePath = string(
                abi.encodePacked("./createVersionProposalData-", network, ".json")
            );

            vm.writeFile(filePath, json);
        }
        vm.stopBroadcast();
    }

    function _buildProposalData(
        address _sppSetup
    ) internal view returns (ProposalData memory _proposalData) {
        _proposalData.title = string(
            abi.encodePacked(
                "Publish Staged Proposal Plugin ",
                _versionString(PluginSettings.VERSION_RELEASE, PluginSettings.VERSION_BUILD)
            )
        );
        _proposalData.description = string(
            abi.encodePacked(
                "Publishes ",
                _versionString(PluginSettings.VERSION_RELEASE, PluginSettings.VERSION_BUILD),
                " of the Staged Proposal Plugin"
            )
        );
        _proposalData.actions = new Action[](1);
        _proposalData.actions[0] = Action({
            to: address(sppRepo),
            value: 0,
            data: abi.encodeWithSelector(
                sppRepo.createVersion.selector,
                PluginSettings.VERSION_RELEASE,
                _sppSetup,
                PluginSettings.BUILD_METADATA,
                PluginSettings.RELEASE_METADATA
            )
        });
    }

    function _serializeToJson(
        ProposalData memory _proposalData
    ) internal returns (string memory json) {
        string memory proposalData;
        vm.serializeString(proposalData, "title", _proposalData.title);
        vm.serializeString(proposalData, "description", _proposalData.description);

        string[] memory actions = new string[](1);
        // solhint-disable quotes
        actions[0] = string(
            abi.encodePacked(
                '{"to": "',
                vm.toString(_proposalData.actions[0].to),
                '", "value": "',
                vm.toString(_proposalData.actions[0].value),
                '", "data": "',
                vm.toString(_proposalData.actions[0].data),
                '"}'
            )
        );

        json = vm.serializeString(proposalData, "actions", actions);
    }
}
