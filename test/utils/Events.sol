// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {StagedProposalProcessor as SPP} from "../../src/StagedProposalProcessor.sol";

import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

contract Events {
    event ProposalAdvanced(uint256 indexed proposalId, uint256 indexed stageId);
    event ProposalResultReported(uint256 indexed proposalId, address indexed plugin);
    event MetadataSet(bytes metadata);
    event Initialized(uint8 version);
    event StagesUpdated(SPP.Stage[] stages);
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed creator,
        uint64 startDate,
        uint64 endDate,
        bytes metadata,
        Action[] actions,
        uint256 allowFailureMap
    );
    event ProposalCreated(uint256 proposalId, uint64 startDate, uint64 endDate);
}
