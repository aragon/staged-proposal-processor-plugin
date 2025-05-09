// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

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

    // exposed function for internal `_msgSender`
    function exposed_msgSender() external view returns (address) {
        return _msgSender();
    }

    // exposed function for internal `_msgData`
    function exposed_msgData() external view returns (bytes calldata) {
        return _msgData();
    }
}
