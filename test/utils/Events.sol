// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {StagedProposalProcessor as SPP} from "../../src/StagedProposalProcessor.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

contract Events {
    event ProposalAdvanced(bytes32 indexed proposalId, uint256 indexed stageId);
    event ProposalResult(bytes32 indexed proposalId, address indexed plugin);
    event MetadataUpdated(bytes releaseMetadata);
    event Initialized(uint8 version);
    event StagesUpdated(SPP.Stage[] stages);
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed creator,
        uint64 startDate,
        uint64 endDate,
        bytes metadata,
        IDAO.Action[] actions,
        uint256 allowFailureMap
    );
    event ProposalCreated(uint256 proposalId, uint64 startDate, uint64 endDate);
}
