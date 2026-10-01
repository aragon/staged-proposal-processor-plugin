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
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @dev `createVersion` assigns the build number on-chain, so `NewVersion.s.sol` must refuse to run
///      unless the repo's next build is `VERSION_BUILD` (e.g. a network still at build 1).
contract NewVersion_Script_UnitTest is Test {
    NewVersionHarness newVersion;
    PluginRepo repo;
    PlaceholderSetup placeholder;

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
        placeholder = new PlaceholderSetup();
    }

    function _publishBuilds(uint256 _count) internal {
        for (uint256 i = 0; i < _count; ++i) {
            repo.createVersion(PluginSettings.VERSION_RELEASE, address(placeholder), "build", "release");
        }
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
        // it should pass.
        _publishBuilds(PluginSettings.VERSION_BUILD - 1);
        newVersion.exposed_requireNextBuild(repo);

        // and the build the repo would assign is indeed `VERSION_BUILD`.
        _publishBuilds(1);
        assertEq(repo.buildCount(PluginSettings.VERSION_RELEASE), PluginSettings.VERSION_BUILD);
    }

    function test_RevertWhen_VersionAlreadyPublished() external {
        // it should revert, publishing again would create build `VERSION_BUILD + 1`.
        _publishBuilds(PluginSettings.VERSION_BUILD);
        _expectInvalidBuild(PluginSettings.VERSION_BUILD);
        newVersion.exposed_requireNextBuild(repo);
    }

    function test_RevertWhen_RepoIsMoreThanOneBuildBehind() external {
        // it should revert, the version would be published under a lower build number.
        _publishBuilds(PluginSettings.VERSION_BUILD - 2);
        _expectInvalidBuild(PluginSettings.VERSION_BUILD - 2);
        newVersion.exposed_requireNextBuild(repo);
    }

    function test_RevertWhen_ReleaseHasNoBuilds() external {
        // it should revert.
        _expectInvalidBuild(0);
        newVersion.exposed_requireNextBuild(repo);
    }
}
