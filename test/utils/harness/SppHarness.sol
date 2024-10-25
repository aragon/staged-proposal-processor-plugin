// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {StagedProposalProcessor as SPP} from "../../../src/StagedProposalProcessor.sol";

contract SppHarness is SPP {
    // exposed function for internal `_createBodyProposals`
    function exposed_createBodyProposals(
        uint256 _proposalId,
        uint16 _stageId,
        uint64 _startDate,
        bytes[] memory _createProposalParams
    ) external {
        _createBodyProposals(_proposalId, _stageId, _startDate, _createProposalParams);
    }
}
