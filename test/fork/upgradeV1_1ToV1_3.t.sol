// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ForkBaseTest} from "./ForkBaseTest.t.sol";
import {Permissions} from "../../src/libraries/Permissions.sol";
import {SPPRuleCondition} from "../../src/utils/SPPRuleCondition.sol";
import {StagedProposalProcessor as SPP} from "../../src/StagedProposalProcessor.sol";
import {AddressCheckConditionMock} from "../utils/AddressCheckConditionMock.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {
    hashHelpers,
    PluginSetupRef
} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {
    RuledCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/extensions/RuledCondition.sol";

/// @notice Forks a network where v1.1 is deployed (set RPC_URL accordingly), installs the SPP at
/// build 1 and exercises the v1.1 → v1.3 upgrade through the PSP: the rule condition is replaced
/// with one that keeps the rules, the IF_ELSE `_where`/`_who` swap is fixed end to end, and the
/// implementation is swapped.
///
/// Run with e.g. `RPC_URL=<sepolia rpc> just test-fork --match-test test_upgradeFromBuild1`.
contract UpgradeV1_1ToV1_3_ForkTest is ForkBaseTest {
    DAO internal dao;
    address internal installedAdminPlugin;

    // Op enum and rule-id values mirrored as raw uint8 to keep the test independent of internal
    // enum ordering — a change there would itself be a bug.
    uint8 internal constant OP_RET = 7;
    uint8 internal constant OP_IF_ELSE = 12;
    uint8 internal constant LOGIC_OP_RULE_ID = 203;
    uint8 internal constant VALUE_RULE_ID = 204;

    address internal creator = makeAddr("creator");
    address internal stranger = makeAddr("stranger");

    function setUp() public override {
        super.setUp();

        DAOFactory.InstalledPlugin[] memory installed;
        (dao, installed) = _createDummyDaoAdmin();
        installedAdminPlugin = installed[0].plugin;
    }

    function test_upgradeFromBuild1_replacesHelper_preservesRules_andFixesIfElseSwap() external {
        // ---- 1. Install the SPP at build 1 (real v1.1 setup on the fork). ----
        PluginSetupRef memory build1Ref = PluginSetupRef({
            versionTag: PluginRepo.Tag({release: 1, build: 1}),
            pluginSetupRepo: sppRepo
        });

        (address plugin, address[] memory helpers) = _installPlugin(
            dao,
            build1Ref,
            _prepareSimpleInstallData(installedAdminPlugin)
        );
        address oldCondition = helpers[0];
        address implBeforeUpdate = _proxyImpl(plugin);
        assertEq(SPPRuleCondition(oldCondition).getRules().length, 0, "starts with no rules");

        // ---- 2. Restrict proposal creation to `creator` with an IF_ELSE rule whose predicate is
        //         asymmetric in (`_where`, `_who`). Build 1 ships with the swap bug, so the
        //         predicate sees the arguments in the wrong order and the IF_ELSE routes to the
        //         failure branch. ----
        AddressCheckConditionMock asymCondition = new AddressCheckConditionMock();
        asymCondition.setExpected(plugin, creator);

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

        // Bug witness on v1.1: `creator` should be allowed to create proposals, but the swapped
        // predicate routes the IF_ELSE to its failure branch.
        assertFalse(
            SPPRuleCondition(oldCondition).isGranted(
                plugin,
                creator,
                Permissions.CREATE_PROPOSAL_PERMISSION_ID,
                bytes("")
            ),
            "v1.1: IF_ELSE swap bug returns false where it should return true"
        );
        _expectCreateProposalDenied(plugin, creator);
        _createProposal(plugin, creator, "denied on v1.1");

        // PSP rejects an update in the same block as the install.
        vm.roll(block.number + 1);

        // ---- 3. prepareUpdate(1 -> 3). ----
        PluginSetupRef memory build3Ref = sppVersionUnderTest();

        (
            bytes memory initData,
            IPluginSetup.PreparedSetupData memory preparedSetupData
        ) = psp.prepareUpdate(
                address(dao),
                PluginSetupProcessor.PrepareUpdateParams({
                    currentVersionTag: build1Ref.versionTag,
                    newVersionTag: build3Ref.versionTag,
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

        // ---- 4. applyUpdate. The PSP needs ROOT on the DAO to apply the helper-swap
        //         permissions, and UPGRADE_PLUGIN on the plugin to swap the implementation. ----
        resetPrank(address(dao));
        dao.grant(address(dao), address(psp), dao.ROOT_PERMISSION_ID());
        dao.grant(plugin, address(psp), UPGRADE_PLUGIN_PERMISSION_ID);

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

        dao.revoke(plugin, address(psp), UPGRADE_PLUGIN_PERMISSION_ID);
        dao.revoke(address(dao), address(psp), dao.ROOT_PERMISSION_ID());
        resetPrank(deployer);

        // ---- 5. Post-upgrade: implementation swapped, rules preserved, permissions migrated,
        //         bug fixed. ----
        address implAfterUpdate = _proxyImpl(plugin);
        assertNotEq(implAfterUpdate, implBeforeUpdate, "plugin impl actually changed");
        assertEq(implAfterUpdate, sppSetup.implementation(), "plugin impl is the version under test");

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
                creator,
                Permissions.CREATE_PROPOSAL_PERMISSION_ID,
                bytes("")
            ),
            "v1.3: IF_ELSE predicate now evaluates with the correct (_where, _who) order"
        );

        // And through the SPP: the new condition guards proposal creation, `creator` passes and
        // anybody else still hits the failure branch.
        _createProposal(plugin, creator, "allowed on v1.3");
        _expectCreateProposalDenied(plugin, stranger);
        _createProposal(plugin, stranger, "still denied on v1.3");
    }

    function _createProposal(address _plugin, address _creator, bytes memory _metadata) internal {
        Action[] memory actions = new Action[](1);
        actions[0] = Action({to: address(target), value: 0, data: ""});

        resetPrank(_creator);
        SPP(_plugin).createProposal({
            _metadata: _metadata,
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: uint64(block.timestamp),
            _proposalParams: new bytes[][](0)
        });
        resetPrank(deployer);
    }

    function _expectCreateProposalDenied(address _plugin, address _creator) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                _plugin,
                _creator,
                Permissions.CREATE_PROPOSAL_PERMISSION_ID
            )
        );
    }
}
