// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

// import {StdUtils} from "forge-std/src/StdUtils.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {Stage, Plugin} from "../utils/Types.sol";
import {StagedProposalProcessor as SPP} from "../../src/StagedProposalProcessor.sol";

import "forge-std/console.sol";

abstract contract Fuzzers is StdUtils {
    function fuzzSppStages(
        Stage[] memory _stages,
        Plugin[] memory _plugins
    ) internal pure returns (SPP.Stage[] memory _fuzzedStages) {
        SPP.Plugin[] memory fuzzPlugins = fuzzSppPlugins(_plugins);

        _fuzzedStages = new SPP.Stage[](_stages.length);
        for (uint256 i = 0; i < _stages.length; ++i) {
            _fuzzedStages[i] = SPP.Stage({
                maxAdvance: _stages[i].maxAdvance,
                minAdvance: _stages[i].minAdvance,
                stageDuration: _stages[i].stageDuration,
                approvalThreshold: uint16(bound(_stages[i].approvalThreshold, 0, _stages.length)),
                vetoThreshold: uint16(bound(_stages[i].vetoThreshold, 0, _stages.length)),
                plugins: fuzzPlugins
            });
        }
    }

    function fuzzSppPlugins(
        Plugin[] memory _plugins
    ) internal pure returns (SPP.Plugin[] memory _fuzzedPlugins) {
        // todo set the plugin address and the allowed bodies like deployed plugins
        _fuzzedPlugins = new SPP.Plugin[](_plugins.length);
        for (uint256 i = 0; i < _plugins.length; ++i) {
            _fuzzedPlugins[i] = SPP.Plugin({
                pluginAddress: _plugins[i].pluginAddress,
                isManual: _plugins[i].isManual,
                allowedBody: _plugins[i].allowedBody,
                proposalType: SPP.ProposalType(bound(_plugins[i].proposalType, 0, 1))
            });
        }
    }
}
