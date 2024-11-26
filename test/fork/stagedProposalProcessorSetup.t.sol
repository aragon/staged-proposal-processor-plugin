// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ForkBaseTest} from "./ForkBaseTest.t.sol";
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
import {
    PluginUpgradeableSetup
} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginUpgradeableSetup.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {
    RuledCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/extensions/RuledCondition.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";

contract stagedProposalProcessorSetup_ForkTest is ForkBaseTest {
    DAO internal dao;
    address installedAdminPlugin;
    address multisigPlugin;

    function setUp() public override {
        super.setUp();

        // get new dao
        DAOFactory.InstalledPlugin[] memory _installedPlugins;
        (dao, _installedPlugins) = _createDummyDaoAdmin();

        installedAdminPlugin = _installedPlugins[0].plugin;

        // install multisig and revoke execute permission
        multisigPlugin = _installMultisigAndRevokeRoot(dao);
    }

    function test_installSPP() external {
        // install spp stage 1 admin, stage 2 empty stage 3 multisig
        (address sppPlugin, ) = _installSPP(dao, _prepareInstallationData());

        // check spp plugin is installed
        assertNotEq(address(sppPlugin), address(0), "pluginAddr");

        // check spp has execute permission on dao
        assertTrue(
            dao.hasPermission({
                _where: address(dao),
                _who: address(sppPlugin),
                _permissionId: dao.EXECUTE_PERMISSION_ID(),
                _data: bytes("")
            }),
            "executePermission"
        );
    }

    function test_uninstallSPP() external {
        // install spp
        (address sppPlugin, address[] memory helpers) = _installSPP(dao, _prepareInstallationData());

        // check spp plugin is installed
        assertNotEq(address(sppPlugin), address(0), "pluginAddr");

        // check spp has execute permission on dao
        assertTrue(
            dao.hasPermission({
                _where: address(dao),
                _who: address(sppPlugin),
                _permissionId: dao.EXECUTE_PERMISSION_ID(),
                _data: bytes("")
            }),
            "executePermission"
        );

        // uninstall spp


        _uninstallSPP(dao, sppPlugin, members);

        // check spp has no execute permission on dao
        assertFalse(
            dao.hasPermission({
                _where: address(dao),
                _who: address(sppPlugin),
                _permissionId: dao.EXECUTE_PERMISSION_ID(),
                _data: bytes("")
            }),
            "executePermission"
        );
    }

    function _prepareInstallationData() internal view returns (bytes memory) {
        SPP.Stage[] memory stages = new SPP.Stage[](3);
        SPP.Body[] memory bodiesStage0 = new SPP.Body[](1);
        bodiesStage0[0] = SPP.Body({
            addr: installedAdminPlugin,
            isManual: true,
            tryAdvance: true,
            resultType: SPP.ResultType.Approval
        });
        stages[0] = SPP.Stage({
            bodies: bodiesStage0,
            maxAdvance: 100,
            minAdvance: 30,
            voteDuration: 10,
            approvalThreshold: 1,
            vetoThreshold: 0,
            cancelable: false,
            editable: false
        });
        stages[1] = SPP.Stage({
            bodies: new SPP.Body[](0),
            maxAdvance: 100,
            minAdvance: 30,
            voteDuration: 10,
            approvalThreshold: 0,
            vetoThreshold: 0,
            cancelable: true,
            editable: true
        });
        SPP.Body[] memory bodiesStage2 = new SPP.Body[](1);
        bodiesStage2[0] = SPP.Body({
            addr: multisigPlugin,
            isManual: true,
            tryAdvance: true,
            resultType: SPP.ResultType.Approval
        });
        stages[2] = SPP.Stage({
            bodies: bodiesStage2,
            maxAdvance: 100,
            minAdvance: 30,
            voteDuration: 10,
            approvalThreshold: 1,
            vetoThreshold: 0,
            cancelable: false,
            editable: false
        });
        RuledCondition.Rule[] memory rules = new RuledCondition.Rule[](0);
        bytes memory sppData = abi.encode(
            "dummy multisig metadata",
            stages,
            rules,
            IPlugin.TargetConfig({target: address(0), operation: IPlugin.Operation.Call})
        );
        return sppData;
    }
}
