// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";

import {StagedProposalProcessorSetup as SPPSetup} from "../src/StagedProposalProcessorSetup.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

contract BaseScript is Script {
    error InvalidVersionBuild(uint8 build, uint8 latestBuild);

    /// @dev Slug + canonical ENS the artifacts-hub reserves for this plugin.
    ///      Must match the entry in aragon/artifacts-hub/scripts/lib/plugin-catalog.ts.
    string internal constant PLUGIN_SLUG = "spp";
    string internal constant PLUGIN_ENS = "staged-proposal-processor.plugin.dao.eth";

    SPPSetup public sppSetup;
    PluginRepo public sppRepo;

    uint256 internal deployerPrivateKey = vm.envUint("DEPLOYER_KEY");

    // solhint-disable immutable-vars-naming
    address internal immutable deployer = vm.addr(deployerPrivateKey);

    function _versionString(uint8 _release, uint8 _build) internal pure returns (string memory) {
        return string(abi.encodePacked("v", vm.toString(_release), ".", vm.toString(_build)));
    }

    /// @notice Writes a single-version `PluginArtifact` envelope to
    ///         `artifacts/artifacts-<NETWORK_NAME>-<block.timestamp>.json` in the
    ///         shape defined by `PluginArtifact` in aragon/artifacts-hub's
    ///         `scripts/schema.ts`. `just import-plugin <path>` in that repo
    ///         merges the file into `addresses/<chainId>.json` under
    ///         `plugins.spp` — identity fields are cross-checked, and the
    ///         new (release, build) is appended if it's not already recorded.
    ///
    ///         Skipped in simulations. Placeholder builds (created by
    ///         Deploy.s.sol when a fresh chain has gaps) are NOT emitted;
    ///         run `just ingest` in artifacts-hub to enumerate the full
    ///         on-chain version list when that matters.
    function _writeArtifact(
        address _maintainer,
        uint8 _release,
        uint16 _build,
        address _setup,
        address _implementation
    ) internal {
        if (vm.envOr("SIMULATION", false)) return;

        string memory networkName = vm.envString("NETWORK_NAME");
        string memory timestampStr = vm.toString(block.timestamp);

        // `implementation` is optional in the schema; omit the field entirely
        // when it isn't known (e.g. placeholder setups have no distinct impl).
        string memory implLine = _implementation == address(0)
            ? ""
            : string.concat(
                "        \"implementation\": \"", vm.toString(_implementation), "\",\n"
            );

        string memory header = string.concat(
            "{\n",
            "  \"chainId\": ", vm.toString(block.chainid), ",\n",
            "  \"network\": \"", networkName, "\",\n",
            "  \"timestamp\": ", timestampStr, ",\n",
            "  \"slug\": \"", PLUGIN_SLUG, "\",\n"
        );
        string memory pluginBody = string.concat(
            "  \"plugin\": {\n",
            "    \"repo\": \"", vm.toString(address(sppRepo)), "\",\n",
            "    \"ens\": \"", PLUGIN_ENS, "\",\n",
            "    \"maintainer\": \"", vm.toString(_maintainer), "\",\n"
        );
        string memory versionsBlock = string.concat(
            "    \"versions\": [\n",
            "      {\n",
            "        \"release\": ", vm.toString(uint256(_release)), ",\n",
            "        \"build\": ", vm.toString(uint256(_build)), ",\n",
            "        \"setup\": \"", vm.toString(_setup), "\",\n",
            implLine,
            "        \"current\": true\n",
            "      }\n",
            "    ]\n",
            "  }\n",
            "}\n"
        );

        string memory artifactsDir = string.concat(vm.projectRoot(), "/artifacts");
        vm.createDir(artifactsDir, true);
        string memory outPath = string.concat(
            artifactsDir, "/artifacts-", networkName, "-", timestampStr, ".json"
        );
        vm.writeFile(outPath, string.concat(header, pluginBody, versionsBlock));
    }
}
