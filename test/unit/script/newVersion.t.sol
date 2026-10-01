// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";

import {BaseScript} from "../../../script/Base.sol";
import {PluginSettings} from "../../../src/utils/PluginSettings.sol";
import {NewVersionHarness} from "../../utils/harness/NewVersionHarness.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {
    PlaceholderSetup
} from "@aragon/osx/framework/plugin/repo/placeholder/PlaceholderSetup.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @dev `createVersion` assigns the build number on-chain. `NewVersion.s.sol` must publish exactly
///      as many builds as needed for the new setup to land on `VERSION_BUILD`, and refuse to run
///      once that build exists.
contract NewVersion_Script_UnitTest is Test {
    NewVersionHarness newVersion;
    PluginRepo repo;
    PlaceholderSetup previousSetup;
    PlaceholderSetup newSetup;

    function setUp() public {
        // `BaseScript` requires a deployer key on construction; keep a real one if present.
        if (vm.envOr("DEPLOYER_KEY", uint256(0)) == 0) {
            vm.setEnv("DEPLOYER_KEY", vm.toString(uint256(1)));
        }
        newVersion = new NewVersionHarness();

        address repoImpl = address(new PluginRepo());
        repo = PluginRepo(
            address(
                new ERC1967Proxy(repoImpl, abi.encodeCall(PluginRepo.initialize, (address(this))))
            )
        );
        previousSetup = new PlaceholderSetup();
        newSetup = new PlaceholderSetup();
    }

    /// @dev Builds that existed before this version, published with another setup.
    function _publishPreviousBuilds(uint256 _count) internal {
        for (uint256 i = 0; i < _count; ++i) {
            repo.createVersion(PluginSettings.VERSION_RELEASE, address(previousSetup), "b", "r");
        }
    }

    /// @dev Runs what the script would put in the management DAO proposal. This test contract
    ///      holds `MAINTAINER_PERMISSION` on the repo, standing in for the management DAO.
    function _executePrintedActions() internal returns (uint256 count) {
        count = newVersion.exposed_buildsToPublish(repo);
        Action[] memory actions = newVersion.exposed_createVersionActions(
            repo,
            address(newSetup),
            count
        );
        assertEq(actions.length, count, "one action per build");

        for (uint256 i = 0; i < actions.length; ++i) {
            assertEq(actions[i].to, address(repo), "action target");
            assertEq(actions[i].value, 0, "action value");
            (bool success, ) = actions[i].to.call(actions[i].data);
            assertTrue(success, "createVersion action");
        }
    }

    function _setupOf(uint16 _build) internal view returns (address) {
        return repo.getVersion(PluginRepo.Tag(PluginSettings.VERSION_RELEASE, _build)).pluginSetup;
    }

    function _expectInvalidBuild(uint256 _latestBuild) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseScript.InvalidVersionBuild.selector,
                PluginSettings.VERSION_BUILD,
                uint8(_latestBuild)
            )
        );
    }

    function test_WhenRepoIsOneBuildBehind() external {
        // it should publish a single build, landing on `VERSION_BUILD`.
        _publishPreviousBuilds(PluginSettings.VERSION_BUILD - 1);

        assertEq(_executePrintedActions(), 1, "builds to publish");
        assertEq(repo.buildCount(PluginSettings.VERSION_RELEASE), PluginSettings.VERSION_BUILD);
        assertEq(_setupOf(PluginSettings.VERSION_BUILD), address(newSetup), "new build");
        assertEq(_setupOf(PluginSettings.VERSION_BUILD - 1), address(previousSetup), "untouched");
    }

    function test_WhenRepoIsMoreThanOneBuildBehind() external {
        // it should fill the gap with the same setup and land on `VERSION_BUILD`.
        _publishPreviousBuilds(PluginSettings.VERSION_BUILD - 2);

        assertEq(_executePrintedActions(), 2, "builds to publish");
        assertEq(repo.buildCount(PluginSettings.VERSION_RELEASE), PluginSettings.VERSION_BUILD);
        assertEq(_setupOf(PluginSettings.VERSION_BUILD), address(newSetup), "new build");
        // The same setup on both builds is what makes the PSP treat the update between them as
        // a no-op, so an installation on the gap build already runs this version.
        assertEq(_setupOf(PluginSettings.VERSION_BUILD - 1), address(newSetup), "gap build");
        assertEq(_setupOf(PluginSettings.VERSION_BUILD - 2), address(previousSetup), "untouched");

        // and the script refuses to run again.
        _expectInvalidBuild(PluginSettings.VERSION_BUILD);
        newVersion.exposed_buildsToPublish(repo);
    }

    function test_WhenReleaseHasNoBuilds() external {
        // it should publish every build up to `VERSION_BUILD` with the same setup.
        assertEq(_executePrintedActions(), PluginSettings.VERSION_BUILD, "builds to publish");
        assertEq(repo.buildCount(PluginSettings.VERSION_RELEASE), PluginSettings.VERSION_BUILD);
        for (uint16 b = 1; b <= PluginSettings.VERSION_BUILD; ++b) {
            assertEq(_setupOf(b), address(newSetup), "every build");
        }
    }

    function test_RevertWhen_VersionAlreadyPublished() external {
        // it should revert, publishing again would create build `VERSION_BUILD + 1`.
        _publishPreviousBuilds(PluginSettings.VERSION_BUILD);
        _expectInvalidBuild(PluginSettings.VERSION_BUILD);
        newVersion.exposed_buildsToPublish(repo);
    }

    function test_RevertWhen_RepoIsAheadOfVersion() external {
        // it should revert.
        _publishPreviousBuilds(PluginSettings.VERSION_BUILD + 1);
        _expectInvalidBuild(PluginSettings.VERSION_BUILD + 1);
        newVersion.exposed_buildsToPublish(repo);
    }
}
