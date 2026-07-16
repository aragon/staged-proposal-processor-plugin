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
import {
    AddressCheckConditionMock
} from "@aragon/osx-commons-contracts/src/mocks/permission/condition/AddressCheckConditionMock.sol";

/// @notice Forks a network where v1.1 is deployed (set RPC_URL accordingly), installs the SPP at
/// build 1, exercises the v1.1 → v1.2 upgrade through the PSP, and asserts that the helper has
/// been swapped, the rules preserved, and the IF_ELSE `_where`/`_who` swap fixed end-to-end. Run
/// with e.g. `RPC_URL=<sepolia rpc> just test-fork --match-test test_upgradeFromBuild1`.
contract UpgradeV1_1ToV1_2_ForkTest is ForkBaseTest {
    DAO internal dao;
    address internal installedAdminPlugin;

    // Op enum and rule-id values mirrored as raw uint8 to keep the test independent of internal
    // enum ordering — a change there would itself be a bug.
    uint8 internal constant OP_RET = 7;
    uint8 internal constant OP_IF_ELSE = 12;
    uint8 internal constant LOGIC_OP_RULE_ID = 203;
    uint8 internal constant VALUE_RULE_ID = 204;

    function setUp() public override {
        super.setUp();

        DAOFactory.InstalledPlugin[] memory installed;
        (dao, installed) = _createDummyDaoAdmin();
        installedAdminPlugin = installed[0].plugin;
    }

    function test_upgradeFromBuild1_replacesHelper_preservesRules_andFixesIfElseSwap() external {
        // ---- 1. Install the SPP at build 1 (the v1.1 setup that lives on the fork). ----
        PluginSetupRef memory build1Ref = PluginSetupRef({
            versionTag: PluginRepo.Tag({release: 1, build: 1}),
            pluginSetupRepo: sppRepo
        });

        (address plugin, address[] memory helpers) = _installSPPAtRef(
            dao,
            _prepareSimpleInstallData(),
            build1Ref
        );
        address oldCondition = helpers[0];
        assertEq(SPPRuleCondition(oldCondition).getRules().length, 0, "starts with no rules");

        // ---- 2. Seed the old condition with an IF_ELSE rule whose predicate is asymmetric in
        //         (`_where`, `_who`). Build 1 ships with the swap bug, so the predicate sees the
        //         arguments in the wrong order and the IF_ELSE routes to the failure branch. ----
        AddressCheckConditionMock asymCondition = new AddressCheckConditionMock();
        address aliceWho = makeAddr("aliceWho");
        asymCondition.setExpected(plugin, aliceWho);

        RuledCondition.Rule[] memory rules = new RuledCondition.Rule[](4);
        rules[0] = RuledCondition.Rule({
            id: LOGIC_OP_RULE_ID,
            op: OP_IF_ELSE,
            value: SPPRuleCondition(oldCondition).encodeIfElse(1, 2, 3),
            permissionId: Permissions.CREATE_PROPOSAL_PERMISSION_ID
        });
        rules[1] = RuledCondition.Rule({
            id: 202, // CONDITION_RULE_ID
            op: 1, // EQ
            value: uint160(address(asymCondition)),
            permissionId: Permissions.CREATE_PROPOSAL_PERMISSION_ID
        });
        rules[2] = RuledCondition.Rule({
            id: VALUE_RULE_ID,
            op: OP_RET,
            value: 1,
            permissionId: Permissions.CREATE_PROPOSAL_PERMISSION_ID
        });
        rules[3] = RuledCondition.Rule({
            id: VALUE_RULE_ID,
            op: OP_RET,
            value: 0,
            permissionId: Permissions.CREATE_PROPOSAL_PERMISSION_ID
        });

        resetPrank(address(dao));
        SPPRuleCondition(oldCondition).updateRules(rules);
        resetPrank(deployer);

        // Bug witness on v1.1: `isGranted(plugin, aliceWho, ...)` should evaluate the predicate
        // with `(_where=plugin, _who=aliceWho)` and route to the success branch (return true).
        // Because of the swap, the predicate sees `(_where=aliceWho, _who=plugin)`, doesn't
        // match the expected pair, and the IF_ELSE returns false instead.
        assertFalse(
            SPPRuleCondition(oldCondition).isGranted(
                plugin,
                aliceWho,
                Permissions.CREATE_PROPOSAL_PERMISSION_ID,
                bytes("")
            ),
            "v1.1: IF_ELSE swap bug returns false where it should return true"
        );

        // PSP rejects an update in the same block as the install.
        vm.roll(block.number + 1);

        // ---- 3. prepareUpdate(1 -> 2). The new setup published in setUp handles the migration. ----
        PluginSetupRef memory build2Ref = PluginSetupRef({
            versionTag: PluginRepo.Tag({release: 1, build: 2}),
            pluginSetupRepo: sppRepo
        });

        (
            bytes memory initData,
            IPluginSetup.PreparedSetupData memory preparedSetupData
        ) = psp.prepareUpdate(
                address(dao),
                PluginSetupProcessor.PrepareUpdateParams({
                    currentVersionTag: build1Ref.versionTag,
                    newVersionTag: build2Ref.versionTag,
                    pluginSetupRepo: sppRepo,
                    setupPayload: IPluginSetup.SetupPayload({
                        plugin: plugin,
                        currentHelpers: helpers,
                        data: ""
                    })
                })
            );

        address newCondition = preparedSetupData.helpers[0];
        assertNotEq(newCondition, oldCondition, "helper replaced");
        assertEq(initData.length, 0, "initData empty (no reinitializer)");
        assertEq(preparedSetupData.permissions.length, 4, "four permission migrations");

        // ---- 4. applyUpdate. NewVersion.s.sol publishes v1.2 with the same `IMPLEMENTATION`
        //         as v1.1 (bytecode is identical), so PSP.applyUpdate sees the proxy already
        //         points at the right impl and skips the upgrade — no UPGRADE_PLUGIN_PERMISSION
        //         bracket needed. The PSP only needs ROOT temporarily to apply the helper-swap
        //         permissions. ----
        resetPrank(address(dao));
        dao.grant(address(dao), address(psp), dao.ROOT_PERMISSION_ID());

        psp.applyUpdate(
            address(dao),
            PluginSetupProcessor.ApplyUpdateParams({
                plugin: plugin,
                pluginSetupRef: build2Ref,
                initData: initData,
                permissions: preparedSetupData.permissions,
                helpersHash: hashHelpers(preparedSetupData.helpers)
            })
        );

        dao.revoke(address(dao), address(psp), dao.ROOT_PERMISSION_ID());
        resetPrank(deployer);

        // ---- 5. Post-upgrade assertions: rules preserved, permissions migrated, bug fixed. ----
        assertEq(SPPRuleCondition(newCondition).getRules(), rules, "rules preserved on new helper");

        assertTrue(
            dao.hasPermission(
                newCondition,
                address(dao),
                Permissions.UPDATE_RULES_PERMISSION_ID,
                bytes("")
            ),
            "new helper grants UPDATE_RULES to DAO"
        );
        assertFalse(
            dao.hasPermission(
                oldCondition,
                address(dao),
                Permissions.UPDATE_RULES_PERMISSION_ID,
                bytes("")
            ),
            "old helper no longer grants UPDATE_RULES to DAO"
        );

        // The same call that returned the wrong answer on v1.1 must now return the right one.
        assertTrue(
            SPPRuleCondition(newCondition).isGranted(
                plugin,
                aliceWho,
                Permissions.CREATE_PROPOSAL_PERMISSION_ID,
                bytes("")
            ),
            "v1.2: IF_ELSE predicate now evaluates with the correct (_where, _who) order"
        );
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

    function _installSPPAtRef(
        DAO _dao,
        bytes memory _data,
        PluginSetupRef memory _ref
    ) internal returns (address plugin, address[] memory helpers) {
        resetPrank(address(_dao));

        IPluginSetup.PreparedSetupData memory preparedSetupData;
        (plugin, preparedSetupData) = psp.prepareInstallation(
            address(_dao),
            PluginSetupProcessor.PrepareInstallationParams(_ref, _data)
        );

        helpers = preparedSetupData.helpers;

        _dao.grant(address(_dao), address(psp), _dao.ROOT_PERMISSION_ID());

        psp.applyInstallation(
            address(_dao),
            PluginSetupProcessor.ApplyInstallationParams(
                _ref,
                plugin,
                preparedSetupData.permissions,
                hashHelpers(preparedSetupData.helpers)
            )
        );

        _dao.revoke(address(_dao), address(psp), _dao.ROOT_PERMISSION_ID());
        resetPrank(deployer);
    }
}
