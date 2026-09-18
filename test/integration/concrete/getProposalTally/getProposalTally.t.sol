// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {BaseTest} from "../../../BaseTest.t.sol";
import {Errors} from "../../../../src/libraries/Errors.sol";
import {PluginA} from "../../../utils/dummy-plugins/PluginA/PluginA.sol";
import {StagedProposalProcessor as SPP} from "../../../../src/StagedProposalProcessor.sol";

import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

contract GetProposalTally_SPP_IntegrationTest is BaseTest {
    uint256 proposalId;

    modifier whenExistentProposal() {
        resultType = SPP.ResultType.Veto;
        proposalId = _configureStagesAndCreateDummyProposal(DUMMY_METADATA);

        _;
    }

    function test_WhenAllResultsAreReported() external whenExistentProposal {
        // it should return the correct tally.

        // execute proposals to report the results
        _executeStageProposals(0);

        (uint256 votes, uint256 vetos) = sppPlugin.getProposalTally(
            proposalId,
            sppPlugin.getProposal(proposalId).currentStage
        );

        // there should be 2 vetos and no vote
        assertEq(vetos, 2, "vetos");
        assertEq(votes, 0, "votes");
    }

    modifier whenSomeResultsAreNotReported() {
        _;
    }

    function test_WhenUnreportedProposalIsManual()
        external
        whenExistentProposal
        whenSomeResultsAreNotReported
    {
        // it should not count unreported results.

        resultType = SPP.ResultType.Veto;
        // setup stages
        SPP.Stage[] memory stages = _createDummyStages({
            _stageCount: 2,
            _body1Manual: false,
            _body2Manual: true,
            _body3Manual: false
        });
        sppPlugin.updateStages(stages);

        // create proposal
        Action[] memory actions = _createDummyActions();
        proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: abi.encode(DUMMY_METADATA, "0x01"),
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });

        (uint256 votes, uint256 vetos) = sppPlugin.getProposalTally(
            proposalId,
            sppPlugin.getProposal(proposalId).currentStage
        );

        // there should be no votes and 2 vetos but second sub proposal veto should not be counted because it is manual
        assertEq(vetos, 1, "vetos");
        assertEq(votes, 0, "votes");
    }

    modifier whenUnreportedProposalIsNonManual() {
        _;
    }

    function test_WhenTheBodyRevertsOnHasSucceeded()
        external
        whenExistentProposal
        whenSomeResultsAreNotReported
        whenUnreportedProposalIsNonManual
    {
        // it should not count unreported results.

        // create proposal, both sub proposals are created normally
        Action[] memory actions = _createDummyActions();
        proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: abi.encode(DUMMY_METADATA, "0x01"),
            _startDate: START_DATE,
            _proposalParams: defaultCreationParams
        });

        // make the second body revert on `hasSucceeded` so its result can not be read
        address secondBodyAddr = sppPlugin
        .getStages(sppPlugin.getCurrentConfigIndex())[0].bodies[1].addr;
        PluginA(secondBodyAddr).setRevertOnHasSucceeded(true);

        (uint256 votes, uint256 vetos) = sppPlugin.getProposalTally(
            proposalId,
            sppPlugin.getProposal(proposalId).currentStage
        );

        // there should be no votes and 1 vetos because one of the sub proposals result can not be read
        assertEq(vetos, 1, "vetos");
        assertEq(votes, 0, "votes");
    }

    modifier whenStoredProposalIdIsValid() {
        _;
    }

    function test_WhenUnreportedPluginResultCanBeExecuted()
        external
        whenExistentProposal
        whenSomeResultsAreNotReported
        whenUnreportedProposalIsNonManual
        whenStoredProposalIdIsValid
    {
        // it should count unreported results.

        (uint256 votes, uint256 vetos) = sppPlugin.getProposalTally(
            proposalId,
            sppPlugin.getProposal(proposalId).currentStage
        );

        // there should be 2 vetos and no vote
        assertEq(vetos, 2, "vetos");
        assertEq(votes, 0, "votes");
    }

    function test_WhenUnreportedPluginResultCanNotBeExecuted()
        external
        whenExistentProposal
        whenSomeResultsAreNotReported
        whenUnreportedProposalIsNonManual
        whenStoredProposalIdIsValid
    {
        // it should count unreported results.

        // set the can execute on sub body to false
        address secondBodyAddr = sppPlugin
        .getStages(sppPlugin.getCurrentConfigIndex())[0].bodies[1].addr;
        PluginA(secondBodyAddr).setCanExecuteResult(false);

        (uint256 votes, uint256 vetos) = sppPlugin.getProposalTally(
            proposalId,
            sppPlugin.getProposal(proposalId).currentStage
        );

        // there should be 1 vetos and no vote, because second body can not execute
        assertEq(vetos, 1, "vetos");
        assertEq(votes, 0, "votes");
    }

    function test_RevertWhen_NonExistentProposal() external {
        // it should revert.

        vm.expectRevert(
            abi.encodeWithSelector(Errors.NonexistentProposal.selector, NON_EXISTENT_PROPOSAL_ID)
        );

        sppPlugin.getProposalTally(NON_EXISTENT_PROPOSAL_ID, 0);
    }
}
