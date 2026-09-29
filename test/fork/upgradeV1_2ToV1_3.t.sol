// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ForkBaseTest} from "./ForkBaseTest.t.sol";
import {Permissions} from "../../src/libraries/Permissions.sol";
import {SPPRuleCondition} from "../../src/utils/SPPRuleCondition.sol";
import {StagedProposalProcessor as SPP} from "../../src/StagedProposalProcessor.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {
    hashHelpers,
    PluginSetupRef
} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {
    RuledCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/extensions/RuledCondition.sol";

/// @notice Forks a network where v1.2 is deployed (set RPC_URL accordingly), installs the SPP at
/// build 2 and exercises the v1.2 → v1.3 upgrade through the PSP. v1.3 is the published build 3
/// once it exists, otherwise the stand-in `ForkBaseTest` publishes from this source.
///
/// Unlike the v1.1 → v1.2 path, build 3 changes the plugin bytecode. `applyUpdate` therefore has
/// to swap the proxy implementation, which requires `UPGRADE_PLUGIN_PERMISSION` on the plugin
/// granted to the PSP for the duration of the call. That grant/revoke bracket is the only
/// operational difference versus a v1.1 → v1.2 apply.
///
/// Run with e.g. `RPC_URL=<sepolia rpc> just test-fork --match-test test_upgradeFromBuild2`.
contract UpgradeV1_2ToV1_3_ForkTest is ForkBaseTest {
    DAO internal dao;
    address internal installedAdminPlugin;

    function setUp() public override {
        super.setUp();

        DAOFactory.InstalledPlugin[] memory installed;
        (dao, installed) = _createDummyDaoAdmin();
        installedAdminPlugin = installed[0].plugin;
    }

    function test_upgradeFromBuild2_swapsImplementation_withUnchangedHelperAndNoPermissionChanges()
        external
    {
        // ---- 1. Install the SPP at build 2 (real v1.2 setup on the fork). ----
        PluginSetupRef memory build2Ref = PluginSetupRef({
            versionTag: PluginRepo.Tag({release: 1, build: 2}),
            pluginSetupRepo: sppRepo
        });

        (address plugin, address[] memory helpers) = _installPlugin(dao, build2Ref, _prepareSimpleInstallData());
        address helperBeforeUpdate = helpers[0];
        address implBeforeUpdate = _proxyImpl(plugin);

        // PSP rejects an update in the same block as the install.
        vm.roll(block.number + 1);

        // ---- 2. prepareUpdate(2 -> 3). ----
        PluginSetupRef memory build3Ref = sppVersionUnderTest();

        (
            bytes memory initData,
            IPluginSetup.PreparedSetupData memory preparedSetupData
        ) = psp.prepareUpdate(
                address(dao),
                PluginSetupProcessor.PrepareUpdateParams({
                    currentVersionTag: build2Ref.versionTag,
                    newVersionTag: build3Ref.versionTag,
                    pluginSetupRepo: sppRepo,
                    setupPayload: IPluginSetup.SetupPayload({
                        plugin: plugin,
                        currentHelpers: helpers,
                        data: ""
                    })
                })
            );

        // v1.2 → v1.3 is an impl-only upgrade: helper passed through unchanged, no
        // permission entries, empty initData.
        assertEq(initData.length, 0, "initData empty (no reinitializer)");
        assertEq(preparedSetupData.helpers.length, 1, "one helper");
        assertEq(
            preparedSetupData.helpers[0],
            helperBeforeUpdate,
            "helper is passed through unchanged"
        );
        assertEq(
            preparedSetupData.permissions.length,
            0,
            "no permission migrations on v1.2 -> v1.3"
        );

        // ---- 3. applyUpdate. Build 3's impl differs from build 2's, so PSP needs
        //         UPGRADE_PLUGIN_PERMISSION on the plugin as well as ROOT on the DAO. ----
        resetPrank(address(dao));
        dao.grant(address(dao), address(psp), dao.ROOT_PERMISSION_ID());
        dao.grant(plugin, address(psp), _upgradePluginPermissionId());

        psp.applyUpdate(
            address(dao),
            PluginSetupProcessor.ApplyUpdateParams({
                plugin: plugin,
                pluginSetupRef: build3Ref,
                initData: initData,
                permissions: preparedSetupData.permissions,
                helpersHash: hashHelpers(preparedSetupData.helpers)
            })
        );

        dao.revoke(plugin, address(psp), _upgradePluginPermissionId());
        dao.revoke(address(dao), address(psp), dao.ROOT_PERMISSION_ID());
        resetPrank(deployer);

        // ---- 4. Post-upgrade: proxy points at the new impl; helper still there,
        //         still holding the same rules; DAO still holds UPDATE_RULES on the
        //         helper (nothing about permissions changed for this update). ----
        address implAfterUpdate = _proxyImpl(plugin);
        assertNotEq(implAfterUpdate, implBeforeUpdate, "plugin impl actually changed");
        assertEq(implAfterUpdate, sppSetup.implementation(), "plugin impl is the version under test");

        assertEq(
            SPPRuleCondition(helperBeforeUpdate).getRules().length,
            0,
            "helper rules preserved (still empty)"
        );
        assertTrue(
            dao.hasPermission(
                helperBeforeUpdate,
                address(dao),
                Permissions.UPDATE_RULES_PERMISSION_ID,
                bytes("")
            ),
            "DAO still holds UPDATE_RULES on the helper"
        );
    }

    /// @dev Reproduces `keccak256("UPGRADE_PLUGIN_PERMISSION")` — the id PluginUUPSUpgradeable
    ///      requires for a proxy implementation swap. Kept as a local constant so this test
    ///      does not need to import the framework's permission id constant.
    function _upgradePluginPermissionId() private pure returns (bytes32) {
        return keccak256("UPGRADE_PLUGIN_PERMISSION");
    }

    function _prepareSimpleInstallData() internal view returns (bytes memory) {
        SPP.Stage[] memory stages = new SPP.Stage[](1);
        SPP.Body[] memory bodies = new SPP.Body[](1);
        bodies[0] = SPP.Body({
            addr: installedAdminPlugin,
            isManual: true,
            tryAdvance: true,
            resultType: SPP.ResultType.Approval
        });
        stages[0] = SPP.Stage({
            bodies: bodies,
            maxAdvance: 100,
            minAdvance: 30,
            voteDuration: 10,
            approvalThreshold: 1,
            vetoThreshold: 0,
            cancelable: false,
            editable: false
        });

        return
            abi.encode(
                "dummy spp metadata",
                stages,
                new RuledCondition.Rule[](0),
                IPlugin.TargetConfig({target: address(0), operation: IPlugin.Operation.Call})
            );
    }
}
