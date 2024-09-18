// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../BaseTest.t.sol";
import {PluginA} from "../../../utils/dummy-plugins/PluginA.sol";
import {StagedProposalProcessor as SPP} from "../../../../src/StagedProposalProcessor.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

contract GetProposalTally_SPP_IntegrationTest is BaseTest {
    bytes32 proposalId;

    modifier whenExistentProposal() {
        proposalType = SPP.ProposalType.Veto;
        proposalId = _configureStagesAndCreateDummyProposal();

        _;
    }

    function test_WhenAllResultsAreReported() external whenExistentProposal {
        // it should return the correct tally.

        // execute proposals to report the results
        _executeStageProposals(0);

        (uint256 votes, uint256 vetos) = sppPlugin.getProposalTally(proposalId);

        // there should be 2 vetos and no vote
        assertEq(vetos, 2, "vetos");
        assertEq(votes, 0, "votes");
    }

    modifier whenSomeResultsAreNotReported() {
        _;
    }

    function test_WhenVetoThresholdIsZero()
        external
        whenExistentProposal
        whenSomeResultsAreNotReported
    {
        // it should not count unreported results.

        vetoThreshold = 0;
        proposalType = SPP.ProposalType.Veto;
        proposalId = _configureStagesAndCreateDummyProposal();

        (uint256 votes, uint256 vetos) = sppPlugin.getProposalTally(proposalId);

        // there should be no votes and 2 vetos but they should not be counted
        assertEq(vetos, 0, "vetos");
        assertEq(votes, 0, "votes");
    }

    modifier whenVetoThresholdIsNotZero() {
        _;
    }

    function test_WhenUnreportedProposalIsNonOptimistic()
        external
        whenExistentProposal
        whenSomeResultsAreNotReported
        whenVetoThresholdIsNotZero
    {
        // it should not count unreported results of non optimistic proposals.

        // set non optimistic stages
        proposalType = SPP.ProposalType.Approval;
        proposalId = _configureStagesAndCreateDummyProposal();

        (uint256 votes, uint256 vetos) = sppPlugin.getProposalTally(proposalId);

        // there should be no vote and no veto
        assertEq(vetos, 0, "vetos");
        assertEq(votes, 0, "votes");
    }

    modifier whenUnreportedProposalIsOptimistic() {
        _;
    }

    function test_WhenUnreportedProposalIsManual()
        external
        whenExistentProposal
        whenSomeResultsAreNotReported
        whenVetoThresholdIsNotZero
        whenUnreportedProposalIsOptimistic
    {
        // it should not count unreported results of manual proposals.
        proposalType = SPP.ProposalType.Veto;
        // setup stages
        SPP.Stage[] memory stages = _createDummyStages({
            _stageCount: 2,
            _plugin1Manual: false,
            _plugin2Manual: true,
            _plugin3Manual: false
        });
        sppPlugin.updateStages(stages);

        // create proposal
        IDAO.Action[] memory actions = _createDummyActions();
        proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE
        });

        (uint256 votes, uint256 vetos) = sppPlugin.getProposalTally(proposalId);

        // there should be no votes and 2 vetos but second sub proposal veto should not be counted because it is manual
        assertEq(vetos, 1, "vetos");
        assertEq(votes, 0, "votes");
    }

    modifier whenUnreportedProposalIsNonManual() {
        _;
    }

    function test_WhenStoredProposalIdIsNotValid()
        external
        whenExistentProposal
        whenSomeResultsAreNotReported
        whenVetoThresholdIsNotZero
        whenUnreportedProposalIsOptimistic
        whenUnreportedProposalIsNonManual
    {
        // it should not count unreported results of proposals with no valid id.

        // make a plugin revet when creating proposal so the proposal id is not valid
        address secondPluginAddr = sppPlugin.getStages()[0].plugins[1].pluginAddress;
        PluginA(secondPluginAddr).setRevertOnCreateProposal(true);

        // create proposal
        IDAO.Action[] memory actions = _createDummyActions();
        proposalId = sppPlugin.createProposal({
            _actions: actions,
            _allowFailureMap: 0,
            _metadata: DUMMY_METADATA,
            _startDate: START_DATE
        });

        SPP.Proposal memory proposal = sppPlugin.getProposal(proposalId);

        (uint256 votes, uint256 vetos) = sppPlugin.getProposalTally(proposalId);

        // there should be no votes and 1 vetos because one of the sub proposals id not valid
        assertEq(vetos, 1, "vetos");
        assertEq(votes, 0, "votes");
        // check sub proposal id is not valid
        assertEq(
            sppPlugin.pluginProposalIds(proposalId, proposal.currentStage, secondPluginAddr),
            type(uint256).max,
            "invalid subProposalId"
        );
    }

    function test_WhenStoredProposalIdIsValid()
        external
        whenExistentProposal
        whenSomeResultsAreNotReported
        whenVetoThresholdIsNotZero
        whenUnreportedProposalIsOptimistic
        whenUnreportedProposalIsNonManual
    {
        // it should count unreported results of non manual, optimistic proposals with valid id.

        (uint256 votes, uint256 vetos) = sppPlugin.getProposalTally(proposalId);

        // there should be 2 vetos and no vote
        assertEq(vetos, 2, "vetos");
        assertEq(votes, 0, "votes");
    }

    function test_WhenNonExistentProposal() external {
        // it should have zero tally.
        (uint256 votes, uint256 vetos) = sppPlugin.getProposalTally(NON_EXISTENT_PROPOSAL_ID);

        // there should be no vetos and no vote
        assertEq(vetos, 0, "vetos");
        assertEq(votes, 0, "votes");
    }
}
