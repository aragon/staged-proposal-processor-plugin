// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ForkBaseTest} from "./ForkBaseTest.t.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {Permissions} from "../../src/libraries/Permissions.sol";
import {StagedProposalProcessor as SPP} from "../../src/StagedProposalProcessor.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {
    hashHelpers,
    PluginSetupRef
} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {Executor} from "@aragon/osx-commons-contracts/src/executors/Executor.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {
    RuledCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/extensions/RuledCondition.sol";

/// @notice End-to-end upgrade of an SPP installed from the published build 1 (v1.1) or build 2
/// (v1.2) to the version under test (v1.3), applied the way a DAO does it: through a proposal of
/// the SPP itself, while other proposals are in flight.
///
/// Stages, wired as on production DAOs (bodies execute by delegatecalling an `Executor`):
/// - stage 0: a Multisig (automatic, approves) and `vetoer` (manual, vetoes).
/// - stage 1: `approver` (manual, approves).
///
/// In-flight proposals, created before the upgrade:
/// - `upgradedAtStage1`: passed stage 0 before the upgrade, completed after it.
/// - `upgradedAtStage0`: its Multisig sub-proposal is half approved when the upgrade executes.
///
/// Run with e.g. `RPC_URL=<sepolia rpc> just test-fork --match-contract UpgradeViaProposal`.
contract UpgradeViaProposal_ForkTest is ForkBaseTest {
    DAO internal dao;
    SPP internal spp;
    address internal multisig;
    address internal helperBeforeUpdate;
    address internal _currentHelper;

    address internal vetoer = makeAddr("vetoer");
    address internal approver = makeAddr("approver");
    address internal stranger = makeAddr("stranger");

    uint256 internal upgradedAtStage1;
    uint256 internal upgradedAtStage0;

    function setUp() public override {
        super.setUp();
        (dao, ) = _createDummyDaoAdmin();
    }

    function test_upgradeFromBuild1ViaProposal() external {
        _upgradeViaProposal(1);

        // v1.1 → v1.3 replaces the rule condition, moving its permissions to the new one.
        address helperAfterUpdate = _currentHelper;
        assertNotEq(helperAfterUpdate, helperBeforeUpdate, "helper replaced");
        assertFalse(
            dao.hasPermission(
                helperBeforeUpdate,
                address(dao),
                Permissions.UPDATE_RULES_PERMISSION_ID,
                ""
            ),
            "old helper no longer managed by the DAO"
        );
        assertTrue(
            dao.hasPermission(
                helperAfterUpdate,
                address(dao),
                Permissions.UPDATE_RULES_PERMISSION_ID,
                ""
            ),
            "new helper managed by the DAO"
        );

        _assertWorksAfterUpgrade();
    }

    function test_upgradeFromBuild2ViaProposal() external {
        _upgradeViaProposal(2);

        // v1.2 → v1.3 only swaps the implementation.
        assertEq(_currentHelper, helperBeforeUpdate, "helper unchanged");
        assertTrue(
            dao.hasPermission(
                helperBeforeUpdate,
                address(dao),
                Permissions.UPDATE_RULES_PERMISSION_ID,
                ""
            ),
            "helper still managed by the DAO"
        );

        _assertWorksAfterUpgrade();
    }

    // ===== The upgrade =====

    /// @dev Installs build `_fromBuild`, puts proposals in flight and upgrades through a proposal.
    ///      Asserts that the upgrade changed nothing in the SPP's state but its implementation.
    function _upgradeViaProposal(uint16 _fromBuild) internal {
        PluginSetupRef memory fromRef = PluginSetupRef({
            versionTag: PluginRepo.Tag({release: 1, build: _fromBuild}),
            pluginSetupRepo: sppRepo
        });
        address implBeforeUpdate = _installFrom(fromRef);
        // The Multisig checks membership at the block before a proposal is created.
        vm.roll(block.number + 1);

        // ---- In flight: passes stage 0 before the upgrade.
        upgradedAtStage1 = _create("passes stage 0 before the upgrade", TARGET_VALUE);
        _approveOnMultisig(upgradedAtStage1, 0, 0, 2);
        vm.warp(block.timestamp + STAGE_VOTE_DURATION + 1);
        spp.advanceProposal(upgradedAtStage1);
        assertEq(spp.getProposal(upgradedAtStage1).currentStage, 1, "in flight at stage 1");
        assertEq(
            spp.getBodyResult(upgradedAtStage1, 0, multisig),
            SPP.ResultType.Approval,
            "result recorded by the old version"
        );

        // ---- The upgrade proposal. PSP rejects an update in the install block.
        vm.roll(block.number + 1);
        (bytes memory initData, IPluginSetup.PreparedSetupData memory prepared) = psp
            .prepareUpdate(
                address(dao),
                PluginSetupProcessor.PrepareUpdateParams({
                    currentVersionTag: fromRef.versionTag,
                    newVersionTag: sppVersionUnderTest().versionTag,
                    pluginSetupRepo: sppRepo,
                    setupPayload: IPluginSetup.SetupPayload({
                        plugin: address(spp),
                        currentHelpers: _asArray(helperBeforeUpdate),
                        data: ""
                    })
                })
            );
        uint256 upgrade = _create("upgrade to v1.3", _updateActions(initData, prepared));
        _approveOnMultisig(upgrade, 0, 0, 2);
        vm.warp(block.timestamp + STAGE_VOTE_DURATION + 1);
        spp.advanceProposal(upgrade);

        // ---- In flight: its sub-proposal is only half approved when the upgrade executes.
        upgradedAtStage0 = _create("half approved when the upgrade executes", TARGET_VALUE + 1);
        _approveOnMultisig(upgradedAtStage0, 0, 0, 1);

        // ---- Execute the upgrade.
        _report(approver, upgrade, 1, SPP.ResultType.Approval);
        vm.warp(block.timestamp + STAGE_MIN_ADVANCE + 1);

        bytes memory stateBefore = _state();
        spp.execute(upgrade);
        bytes memory stateAfter = _state();

        // The SPP upgraded itself while executing the proposal, and still marked it executed.
        assertTrue(spp.getProposal(upgrade).executed, "upgrade proposal executed");
        assertNotEq(_proxyImpl(address(spp)), implBeforeUpdate, "implementation swapped");
        assertEq(_proxyImpl(address(spp)), sppSetup.implementation(), "implementation is v1.3");
        assertEq(stateAfter, stateBefore, "state preserved across the upgrade");

        // The PSP holds no temporary permission afterwards.
        assertFalse(
            dao.hasPermission(address(dao), address(psp), dao.ROOT_PERMISSION_ID(), ""),
            "PSP root revoked"
        );
        assertFalse(
            dao.hasPermission(address(spp), address(psp), UPGRADE_PLUGIN_PERMISSION_ID, ""),
            "PSP upgrade permission revoked"
        );

        _currentHelper = prepared.helpers[0];
    }

    /// @dev The SPP keeps working under v1.3: in-flight proposals complete or get vetoed, the
    ///      reporting rule applies to them, and a new proposal runs end to end.
    function _assertWorksAfterUpgrade() internal {
        // ---- The in-flight proposal at stage 1 completes.
        _report(approver, upgradedAtStage1, 1, SPP.ResultType.Approval);
        vm.warp(block.timestamp + STAGE_MIN_ADVANCE + 1);
        spp.execute(upgradedAtStage1);
        assertTrue(spp.getProposal(upgradedAtStage1).executed, "in-flight proposal executed");
        assertEq(target.val(), TARGET_VALUE, "in-flight proposal actions ran");

        // ---- The reporting rule applies to a proposal created before the upgrade.
        // A body can not report the other result type.
        resetPrank(vetoer);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ResultTypeNotAllowed.selector,
                uint16(0),
                vetoer,
                uint8(SPP.ResultType.Approval)
            )
        );
        spp.reportProposalResult(upgradedAtStage0, 0, SPP.ResultType.Approval, false);

        // A non-body report is ignored.
        resetPrank(stranger);
        vm.record();
        spp.reportProposalResult(upgradedAtStage0, 0, SPP.ResultType.Approval, true);
        (, bytes32[] memory writes) = vm.accesses(address(spp));
        assertEq(writes.length, 0, "non-body report wrote storage");
        resetPrank(deployer);

        // The Multisig sub-proposal created before the upgrade executes under v1.3 and reports.
        _approveOnMultisig(upgradedAtStage0, 0, 1, 2);
        assertEq(
            spp.getBodyResult(upgradedAtStage0, 0, multisig),
            SPP.ResultType.Approval,
            "multisig reported under v1.3"
        );

        // The vetoer blocks it.
        _report(vetoer, upgradedAtStage0, 0, SPP.ResultType.Veto);
        vm.warp(block.timestamp + STAGE_VOTE_DURATION + 1);
        assertFalse(spp.canProposalAdvance(upgradedAtStage0), "vetoed proposal can not advance");

        // ---- A new proposal runs end to end.
        uint256 created = _create("created after the upgrade", TARGET_VALUE + 2);
        _approveOnMultisig(created, 0, 0, 2);
        vm.warp(block.timestamp + STAGE_VOTE_DURATION + 1);
        spp.advanceProposal(created);
        _report(approver, created, 1, SPP.ResultType.Approval);
        vm.warp(block.timestamp + STAGE_MIN_ADVANCE + 1);
        spp.execute(created);
        assertEq(target.val(), TARGET_VALUE + 2, "new proposal actions ran");
    }

    // ===== Helpers =====

    /// @return The implementation the installed SPP runs.
    function _installFrom(PluginSetupRef memory _ref) internal returns (address) {
        multisig = _installMultisigAndRevokeRoot(
            dao,
            IPlugin.TargetConfig({
                target: address(new Executor()),
                operation: IPlugin.Operation.DelegateCall
            })
        );

        SPP.Body[] memory stage0 = new SPP.Body[](2);
        stage0[0] = SPP.Body({
            addr: multisig,
            isManual: false,
            tryAdvance: false,
            resultType: SPP.ResultType.Approval
        });
        stage0[1] = SPP.Body({
            addr: vetoer,
            isManual: true,
            tryAdvance: false,
            resultType: SPP.ResultType.Veto
        });
        SPP.Body[] memory stage1 = new SPP.Body[](1);
        stage1[0] = SPP.Body({
            addr: approver,
            isManual: true,
            tryAdvance: false,
            resultType: SPP.ResultType.Approval
        });

        SPP.Stage[] memory stages = new SPP.Stage[](2);
        stages[0] = _stage(stage0, 1);
        stages[1] = _stage(stage1, 0);

        bytes memory data = abi.encode(
            "spp installed before the upgrade",
            stages,
            new RuledCondition.Rule[](0),
            IPlugin.TargetConfig({target: address(0), operation: IPlugin.Operation.Call})
        );

        address[] memory helpers;
        address plugin;
        (plugin, helpers) = _installPlugin(dao, _ref, data);
        spp = SPP(plugin);
        helperBeforeUpdate = helpers[0];

        resetPrank(address(dao));
        dao.grant(multisig, address(spp), Permissions.CREATE_PROPOSAL_PERMISSION_ID);
        resetPrank(deployer);

        address impl = _proxyImpl(plugin);
        assertEq(
            impl,
            IPluginSetup(sppRepo.getVersion(_ref.versionTag).pluginSetup).implementation(),
            "installed the published build"
        );
        return impl;
    }

    function _stage(
        SPP.Body[] memory _bodies,
        uint16 _vetoThreshold
    ) internal pure returns (SPP.Stage memory) {
        return
            SPP.Stage({
                bodies: _bodies,
                maxAdvance: STAGE_MAX_ADVANCE,
                minAdvance: STAGE_MIN_ADVANCE,
                voteDuration: STAGE_VOTE_DURATION,
                approvalThreshold: 1,
                vetoThreshold: _vetoThreshold,
                cancelable: false,
                editable: false
            });
    }

    /// @dev The actions of a DAO proposal applying a prepared update: grant the PSP what it needs,
    ///      apply, and revoke again.
    function _updateActions(
        bytes memory _initData,
        IPluginSetup.PreparedSetupData memory _prepared
    ) internal view returns (Action[] memory actions) {
        actions = new Action[](5);
        actions[0] = _daoCall(
            abi.encodeCall(dao.grant, (address(spp), address(psp), UPGRADE_PLUGIN_PERMISSION_ID))
        );
        actions[1] = _daoCall(
            abi.encodeCall(dao.grant, (address(dao), address(psp), dao.ROOT_PERMISSION_ID()))
        );
        actions[2] = Action({
            to: address(psp),
            value: 0,
            data: abi.encodeCall(
                psp.applyUpdate,
                (
                    address(dao),
                    PluginSetupProcessor.ApplyUpdateParams({
                        plugin: address(spp),
                        pluginSetupRef: sppVersionUnderTest(),
                        initData: _initData,
                        permissions: _prepared.permissions,
                        helpersHash: hashHelpers(_prepared.helpers)
                    })
                )
            )
        });
        actions[3] = _daoCall(
            abi.encodeCall(dao.revoke, (address(dao), address(psp), dao.ROOT_PERMISSION_ID()))
        );
        actions[4] = _daoCall(
            abi.encodeCall(dao.revoke, (address(spp), address(psp), UPGRADE_PLUGIN_PERMISSION_ID))
        );
    }

    function _daoCall(bytes memory _data) internal view returns (Action memory) {
        return Action({to: address(dao), value: 0, data: _data});
    }

    function _create(string memory _metadata, uint256 _targetValue) internal returns (uint256) {
        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            to: address(target),
            value: 0,
            data: abi.encodeCall(target.setValue, (_targetValue))
        });
        return _create(_metadata, actions);
    }

    function _create(string memory _metadata, Action[] memory _actions) internal returns (uint256) {
        resetPrank(deployer);
        return
            spp.createProposal({
                _metadata: bytes(_metadata),
                _actions: _actions,
                _allowFailureMap: 0,
                _startDate: uint64(block.timestamp),
                _proposalParams: new bytes[][](0)
            });
    }

    /// @dev Approves the Multisig sub-proposal with members `_from` to `_to` (excluded). The second
    ///      approval executes it, which reports the result on the SPP.
    function _approveOnMultisig(
        uint256 _proposalId,
        uint16 _stageId,
        uint256 _from,
        uint256 _to
    ) internal {
        uint256 subProposalId = spp.getBodyProposalId(_proposalId, _stageId, multisig);
        for (uint256 i = _from; i < _to; ++i) {
            resetPrank(members[i]);
            (bool success, ) = multisigCallApprove(multisig, subProposalId, true);
            assertTrue(success, "multisig approve");
        }
        resetPrank(deployer);
    }

    function _report(
        address _body,
        uint256 _proposalId,
        uint16 _stageId,
        SPP.ResultType _resultType
    ) internal {
        resetPrank(_body);
        spp.reportProposalResult(_proposalId, _stageId, _resultType, false);
        resetPrank(deployer);
    }

    /// @dev Everything the SPP stores that an upgrade must preserve, for the in-flight proposals:
    ///      configuration, every stage config, and each proposal with its sub-proposal ids, results
    ///      and tallies on every stage it reached.
    function _state() internal view returns (bytes memory state) {
        uint256 configIndex = spp.getCurrentConfigIndex();
        state = abi.encode(
            configIndex,
            spp.getTrustedForwarder(),
            spp.getTargetConfig(),
            spp.getMetadata()
        );
        for (uint256 i = 1; i <= configIndex; ++i) {
            state = abi.encode(state, spp.getStages(i));
        }

        uint256[2] memory ids = [upgradedAtStage1, upgradedAtStage0];
        for (uint256 p; p < ids.length; ++p) {
            SPP.Proposal memory proposal = spp.getProposal(ids[p]);
            SPP.Stage[] memory stages = spp.getStages(proposal.stageConfigIndex);
            state = abi.encode(state, proposal, spp.state(ids[p]));

            for (uint16 s; s <= proposal.currentStage; ++s) {
                (uint256 approvals, uint256 vetoes) = spp.getProposalTally(ids[p], s);
                state = abi.encode(state, approvals, vetoes);

                for (uint256 b; b < stages[s].bodies.length; ++b) {
                    address body = stages[s].bodies[b].addr;
                    state = abi.encode(
                        state,
                        spp.getBodyProposalId(ids[p], s, body),
                        spp.getBodyResult(ids[p], s, body)
                    );
                }
            }
        }
    }

    function _asArray(address _a) internal pure returns (address[] memory array) {
        array = new address[](1);
        array[0] = _a;
    }
}
