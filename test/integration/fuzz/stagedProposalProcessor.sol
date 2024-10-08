// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../BaseTest.t.sol";
import {Errors} from "../../../src/libraries/Errors.sol";

contract SPP_Integration_FuzzTest is BaseTest {
    function testFuzz_advanceProposal_RevertWhen_NonExistent(uint256 _randomProposalId) external {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ProposalNotExists.selector, _randomProposalId)
        );
        sppPlugin.advanceProposal(_randomProposalId);
    }

    // todo think on other fuzzy options
}
