// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ForkBaseTest} from "./ForkBaseTest.t.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {Permissions} from "../../src/libraries/Permissions.sol";
import {SPPRuleCondition} from "../../src/utils/SPPRuleCondition.sol";
import {StagedProposalProcessor as SPP} from "../../src/StagedProposalProcessor.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {
    _getAppliedSetupId,
    _getPluginInstallationId,
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

/// @notice Upgrades real SPPs that DAOs installed on Sepolia at build 1 (v1.1) to the version under
/// test, the way their DAO does it (the SPP executing the update actions on the DAO), and checks
/// that nothing they store changed and that they keep working.
///
/// The SPPs are pinned, picked from the ones installed on Sepolia to cover different wirings. A
/// test skips when its SPP is no longer installed at build 1.
///
/// Run with e.g. `RPC_URL=<sepolia rpc> just test-fork --match-contract UpgradeRealSpp`.
contract UpgradeRealSpp_ForkTest is ForkBaseTest {
    uint256 internal constant SEPOLIA = 11155111;

    address internal stranger = makeAddr("stranger");

    struct RealSpp {
        DAO dao;
        SPP spp;
        address helper;
        uint256[] proposalIds;
        // The creator of its latest proposal, and what the app passed as `_proposalParams` then.
        address creator;
        bytes[][] createParams;
    }

    /// @dev Bodies delegatecall the global executor; no rules, so anybody can create proposals.
    function test_globalExecutorBodies() external {
        uint256[] memory ids = new uint256[](8);
        ids[0] = 36450230532138041967764114472044345868246160747485655977166874797416257016080;
        ids[1] = 76653610639769981947426214831577783864417580126833611237915253325585701465571;
        ids[2] = 64969183594540862011755412822546541999664009964534466033160127074028022256759;
        ids[3] = 85938554144691092857429615611876468964370504913413729094184431339618437314905;
        ids[4] = 64468870082977156770336470508402926926766922235851736403845467163223496723567;
        ids[5] = 26375421033664530297696598376793512135091993054430850519024689750242883620177;
        ids[6] = 19390638206101679229728583551706593329759478400046930781894602681372864287990;
        ids[7] = 106822811472183048323914028184345019668062224072093802839038302353196231476407;

        _upgradeAndCheck(
            RealSpp({
                dao: DAO(payable(0x3637C1e7Ba77ee5F30Ed7107CF2eE32D753c7552)),
                spp: SPP(0xBd4DBBf954634E7a68d5c6ad9A0F51a5c2ae4506),
                helper: 0xC2d8FBe02F9484aEcEAe1Fe8abA31650f52E3e48,
                proposalIds: ids,
                creator: 0x376c649111543C46Ce15fD3a9386b4F202A6E06c,
                createParams: new bytes[][](0)
            })
        );
    }

    /// @dev Bodies delegatecall the global executor; proposal creation is restricted by a rule.
    function test_globalExecutorBodiesWithRules() external {
        uint256[] memory ids = new uint256[](10);
        ids[0] = 102582790372970368732007268454739186466199562664420583252896108463488854768097;
        ids[1] = 24911562803801189375954792962263097396182777683967357718439232778404184494557;
        ids[2] = 65103685281072199990359330035780164178626639702516974356627629868869457943665;
        ids[3] = 58441161810522071121613252506971512337783621790226307130436519280573883427000;
        ids[4] = 41907087502929417281370621587961010800472049296522836514318245541543452116653;
        ids[5] = 5647065756068568205566335308850855975410074077458292107759169161965756753334;
        ids[6] = 115549279269600737567332713522442228287280623744739436960941993596587821273661;
        ids[7] = 101031065782849422258185104994840566538345189963956864618123441085191920383655;
        ids[8] = 32037104085758110311276568843357564947489568449838172268681818139881280990938;
        ids[9] = 73210259468572323748458252446116462818032389148963368529543169276126712825657;

        _upgradeAndCheck(
            RealSpp({
                dao: DAO(payable(0x3eb4fc049637ddb6c4C0c06f4709Ac6BC8cd829e)),
                spp: SPP(0xeC887AdEd6a940217bE8461bfDdF8C45E0d52B70),
                helper: 0x3f56ddA2FDF9f5c0bB1AdD7f732b4e0c089B0A91,
                proposalIds: ids,
                creator: 0x061BB58c8C726e545618d9D594bb81D38fabe405,
                createParams: new bytes[][](1)
            })
        );
    }

    /// @dev A manual body next to an automatic one.
    function test_manualBody() external {
        uint256[] memory ids = new uint256[](6);
        ids[0] = 86064445454555529728241835093521632137776288283460885740585940675724015966553;
        ids[1] = 25919359737791970922901056273007736539974862810369268444639740208563794552977;
        ids[2] = 36932693091331348034946641397884982540727124071546836560185413977862024231165;
        ids[3] = 37825750333618933311790786016160728388393509228897886383704199373169673163773;
        ids[4] = 109091194274670314319588607554638739160381670439293479559488891846533643977576;
        ids[5] = 1157236298571661823139832674754406612861725162771607536840432994567212625076;

        // Its automatic body reverts on empty params: it decodes `(uint256 allowFailureMap)`.
        bytes[][] memory params = new bytes[][](2);
        params[0] = new bytes[](1);
        params[0][0] = abi.encode(uint256(0));

        _upgradeAndCheck(
            RealSpp({
                dao: DAO(payable(0xf3b726299c74597dCdcf1CAC4a04339467f32b51)),
                spp: SPP(0xAf591a1B3909b9f8464910c3c6a6529A67b7377f),
                helper: 0x9FB88eeC41A3299a51f410AdC8D2c94b7CC781FC,
                proposalIds: ids,
                creator: 0xcBc8a82E3dfc6Faa2506F3033271EBc7447f096B,
                createParams: params
            })
        );
    }

    /// @dev A Veto body that executes through its DAO with `Call`, so its reports reach the SPP
    ///      from the DAO. v1.3 must ignore them without reverting, or that body could no longer
    ///      execute its sub-proposals.
    function test_vetoBodyReportingThroughItsDao() external {
        uint256[] memory ids = new uint256[](2);
        ids[0] = 46523843781776831991400569427761639362663077318172704575811158927502843769159;
        ids[1] = 6948420032658123238849769207168482550157326635068069187010946260846898352748;

        RealSpp memory real = RealSpp({
            dao: DAO(payable(0xd85cbaedf8AA2AA16a3c42d02271d7109c149F39)),
            spp: SPP(0x177c05De3e216dE498C6e3267ECe39Ad7b9ECB01),
            helper: 0x6f0986aCFEa1e96e3fFe084E42D982460217D7af,
            proposalIds: ids,
            creator: 0xA7a5A2745f10D5C23d75a6fd228A408cEDe1CAE5,
            createParams: new bytes[][](1)
        });
        _upgradeAndCheck(real);

        // Stage 0 is a manual approver, stage 1 the veto body. Its sub-proposal targets the DAO
        // with `Call`, so its report reaches the SPP from the DAO.
        address approver = 0x2D7473039D40d26789981c907AbE9D37bf463e4E;
        address vetoBody = 0x3d98abB7AD5CB72285d8a13F06b3DeaEfF5112F7;
        (address targetOfVetoBody, ) = _targetConfig(vetoBody);
        assertEq(targetOfVetoBody, address(real.dao), "veto body executes through the DAO");

        // Under v1.3 a new proposal reaches stage 1, creating the sub-proposal on the veto body.
        uint256 proposalId = _createProposal(real, real.creator, "driven to the veto stage");
        resetPrank(approver);
        real.spp.reportProposalResult(proposalId, 0, SPP.ResultType.Approval, false);
        resetPrank(deployer);
        real.spp.advanceProposal(proposalId);
        assertEq(real.spp.getProposal(proposalId).currentStage, 1, "advanced to the veto stage");
        uint256 subProposalId = real.spp.getBodyProposalId(proposalId, 1, vetoBody);
        assertNotEq(subProposalId, 0, "sub-proposal created on the veto body");
        assertNotEq(subProposalId, type(uint256).max, "sub-proposal created on the veto body");

        // Its report, arriving from the DAO, is ignored instead of reverting its execution.
        resetPrank(address(real.dao));
        vm.record();
        real.spp.reportProposalResult(proposalId, 1, SPP.ResultType.Veto, false);
        (, bytes32[] memory writes) = vm.accesses(address(real.spp));
        assertEq(writes.length, 0, "report from the DAO wrote storage");

        // The veto body itself can only veto, and its veto counts.
        resetPrank(vetoBody);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.ResultTypeNotAllowed.selector,
                uint16(1),
                vetoBody,
                uint8(SPP.ResultType.Approval)
            )
        );
        real.spp.reportProposalResult(proposalId, 1, SPP.ResultType.Approval, false);
        real.spp.reportProposalResult(proposalId, 1, SPP.ResultType.Veto, false);
        resetPrank(deployer);
        (, uint256 vetoes) = real.spp.getProposalTally(proposalId, 1);
        assertEq(vetoes, 1, "veto counted");
    }

    // ===== Upgrade and checks =====

    function _upgradeAndCheck(RealSpp memory _real) internal {
        if (!_isInstalledAtBuild1(_real)) {
            vm.skip(true);
            return;
        }

        address bodyFailingOnV11 = _bodyFailingOnV11(_real);
        address newHelper = _upgrade(_real);
        _assertReportingRule(_real);
        _assertCreatesProposals(_real, newHelper, bodyFailingOnV11);
    }

    function _isInstalledAtBuild1(RealSpp memory _real) internal view returns (bool) {
        if (block.chainid != SEPOLIA) return false;

        (, bytes32 appliedSetupId) = psp.states(
            _getPluginInstallationId(address(_real.dao), address(_real.spp))
        );
        return
            appliedSetupId ==
            _getAppliedSetupId(_build1Ref(), hashHelpers(_asArray(_real.helper)));
    }

    /// @return newHelper The rule condition after the update.
    function _upgrade(RealSpp memory _real) internal returns (address newHelper) {
        DAO dao = _real.dao;
        address spp = address(_real.spp);

        address implBefore = _proxyImpl(spp);
        assertEq(
            implBefore,
            IPluginSetup(sppRepo.getVersion(_build1Ref().versionTag).pluginSetup).implementation(),
            "runs the build 1 implementation"
        );
        RuledCondition.Rule[] memory rulesBefore = SPPRuleCondition(_real.helper).getRules();

        (bytes memory initData, IPluginSetup.PreparedSetupData memory prepared) = psp
            .prepareUpdate(
                address(dao),
                PluginSetupProcessor.PrepareUpdateParams({
                    currentVersionTag: _build1Ref().versionTag,
                    newVersionTag: sppVersionUnderTest().versionTag,
                    pluginSetupRepo: sppRepo,
                    setupPayload: IPluginSetup.SetupPayload({
                        plugin: spp,
                        currentHelpers: _asArray(_real.helper),
                        data: ""
                    })
                })
            );
        Action[] memory actions = _updateActions(dao, spp, initData, prepared);

        // Executed the way a passed SPP proposal executes: the SPP calling `execute` on its DAO.
        bytes memory stateBefore = _sppState(_real.spp, _real.proposalIds);
        resetPrank(spp);
        dao.execute(bytes32(uint256(1)), actions, 0);
        resetPrank(deployer);
        bytes memory stateAfter = _sppState(_real.spp, _real.proposalIds);

        assertEq(stateAfter, stateBefore, "state preserved across the upgrade");
        assertEq(_proxyImpl(spp), sppSetup.implementation(), "implementation is v1.3");

        newHelper = prepared.helpers[0];
        assertEq(SPPRuleCondition(newHelper).getRules(), rulesBefore, "rules preserved");
        assertTrue(
            dao.hasPermission(newHelper, address(dao), Permissions.UPDATE_RULES_PERMISSION_ID, ""),
            "new helper managed by the DAO"
        );
        assertFalse(
            dao.hasPermission(address(dao), address(psp), dao.ROOT_PERMISSION_ID(), ""),
            "PSP root revoked"
        );
        assertFalse(
            dao.hasPermission(spp, address(psp), UPGRADE_PLUGIN_PERMISSION_ID, ""),
            "PSP upgrade permission revoked"
        );
    }

    /// @dev On the latest pinned proposal: a body of its first stage can not report the other
    ///      result type, and reports from addresses that are not bodies are ignored, the DAO's
    ///      included.
    function _assertReportingRule(RealSpp memory _real) internal {
        uint256 proposalId = _real.proposalIds[_real.proposalIds.length - 1];
        SPP.Body[] memory bodies = _real
            .spp
            .getStages(_real.spp.getProposal(proposalId).stageConfigIndex)[0]
            .bodies;

        for (uint256 i; i < bodies.length; ++i) {
            SPP.ResultType other = bodies[i].resultType == SPP.ResultType.Approval
                ? SPP.ResultType.Veto
                : SPP.ResultType.Approval;

            resetPrank(bodies[i].addr);
            vm.expectRevert(
                abi.encodeWithSelector(
                    Errors.ResultTypeNotAllowed.selector,
                    uint16(0),
                    bodies[i].addr,
                    uint8(other)
                )
            );
            _real.spp.reportProposalResult(proposalId, 0, other, false);
        }

        _assertReportIgnored(_real, proposalId, stranger);
        _assertReportIgnored(_real, proposalId, address(_real.dao));
        resetPrank(deployer);
    }

    function _assertReportIgnored(
        RealSpp memory _real,
        uint256 _proposalId,
        address _sender
    ) internal {
        resetPrank(_sender);
        vm.record();
        _real.spp.reportProposalResult(_proposalId, 0, SPP.ResultType.Veto, true);
        (, bytes32[] memory writes) = vm.accesses(address(_real.spp));
        assertEq(writes.length, 0, "non-body report wrote storage");
    }

    /// @dev Proposal creation under v1.3, compared with what v1.1 does in the same state: where v1.1
    ///      created every sub-proposal, so does v1.3. Where a body failed to create its sub-proposal
    ///      and v1.1 silently went on without it, v1.3 reverts naming that body. Anybody else gets
    ///      exactly what the preserved rules say.
    function _assertCreatesProposals(
        RealSpp memory _real,
        address _newHelper,
        address _bodyFailingOnV11
    ) internal {
        assertTrue(_canCreate(_real, _newHelper, _real.creator), "the real creator is still allowed");

        if (_bodyFailingOnV11 == address(0)) {
            uint256 proposalId = _createProposal(_real, _real.creator, "created on v1.3");
            SPP.Body[] memory bodies = _firstStageBodies(_real);
            for (uint256 i; i < bodies.length; ++i) {
                if (bodies[i].isManual) continue;
                uint256 subProposalId = _real.spp.getBodyProposalId(proposalId, 0, bodies[i].addr);
                assertNotEq(subProposalId, 0, "sub-proposal created on the real body");
                assertNotEq(subProposalId, type(uint256).max, "sub-proposal created on the real body");
            }
        } else {
            resetPrank(_real.creator);
            (bool success, bytes memory revertData) = address(_real.spp).call(
                abi.encodeWithSignature(
                    "createProposal(bytes,(address,uint256,bytes)[],uint128,uint64,bytes[][])",
                    bytes("created on v1.3"),
                    _createActions(),
                    uint128(0),
                    uint64(block.timestamp),
                    _real.createParams
                )
            );
            resetPrank(deployer);

            assertFalse(success, "v1.3 does not create a proposal missing a sub-proposal");
            address failedBody;
            assembly {
                failedBody := mload(add(revertData, 36))
            }
            assertEq(
                bytes4(revertData),
                Errors.SubProposalCreationFailed.selector,
                "reverts with SubProposalCreationFailed"
            );
            assertEq(failedBody, _bodyFailingOnV11, "names the body that failed on v1.1");
        }

        if (!_canCreate(_real, _newHelper, stranger)) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    DaoUnauthorized.selector,
                    address(_real.dao),
                    address(_real.spp),
                    stranger,
                    Permissions.CREATE_PROPOSAL_PERMISSION_ID
                )
            );
            _createProposal(_real, stranger, "created by a stranger");
        }
    }

    /// @dev Creates a proposal as the real creator under v1.1 and undoes it.
    /// @return failed The first automatic body whose sub-proposal v1.1 could not create, if any.
    function _bodyFailingOnV11(RealSpp memory _real) internal returns (address failed) {
        uint256 snapshot = vm.snapshotState();

        uint256 proposalId = _createProposal(_real, _real.creator, "created on v1.1");
        SPP.Body[] memory bodies = _firstStageBodies(_real);
        for (uint256 i; i < bodies.length; ++i) {
            if (bodies[i].isManual) continue;
            // v1.1's marker for a sub-proposal it could not create.
            if (_real.spp.getBodyProposalId(proposalId, 0, bodies[i].addr) == type(uint256).max) {
                failed = bodies[i].addr;
                break;
            }
        }

        vm.revertToState(snapshot);
    }

    function _firstStageBodies(RealSpp memory _real) internal view returns (SPP.Body[] memory) {
        return _real.spp.getStages(_real.spp.getCurrentConfigIndex())[0].bodies;
    }

    function _canCreate(
        RealSpp memory _real,
        address _helper,
        address _creator
    ) internal view returns (bool) {
        return
            SPPRuleCondition(_helper).isGranted(
                address(_real.spp),
                _creator,
                Permissions.CREATE_PROPOSAL_PERMISSION_ID,
                ""
            );
    }

    function _createProposal(
        RealSpp memory _real,
        address _creator,
        bytes memory _metadata
    ) internal returns (uint256 proposalId) {
        resetPrank(_creator);
        proposalId = _real.spp.createProposal({
            _metadata: _metadata,
            _actions: _createActions(),
            _allowFailureMap: 0,
            _startDate: uint64(block.timestamp),
            _proposalParams: _real.createParams
        });
        resetPrank(deployer);
    }

    function _createActions() internal view returns (Action[] memory actions) {
        actions = new Action[](1);
        actions[0] = Action({to: address(target), value: 0, data: ""});
    }

    // ===== Helpers =====

    function _build1Ref() internal view returns (PluginSetupRef memory) {
        return
            PluginSetupRef({
                versionTag: PluginRepo.Tag({release: 1, build: 1}),
                pluginSetupRepo: sppRepo
            });
    }

    function _targetConfig(address _plugin) internal view returns (address, uint8) {
        (bool success, bytes memory data) = _plugin.staticcall(
            abi.encodeWithSignature("getTargetConfig()")
        );
        assertTrue(success, "getTargetConfig");
        return abi.decode(data, (address, uint8));
    }
}
