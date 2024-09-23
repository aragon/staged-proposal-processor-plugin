// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../BaseTest.t.sol";
import {Errors} from "../../../src/libraries/Errors.sol";
import {PluginA} from "../../utils/dummy-plugins/PluginA.sol";
import {StagedProposalProcessor as SPP} from "../../../src/StagedProposalProcessor.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

contract SPP_Integration_FuzzTest is BaseTest {
    function testFuzz_advanceProposal_RevertWhen_NonExistent(uint256 _randomProposalId) external {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.ProposalNotExists.selector, _randomProposalId)
        );
        sppPlugin.advanceProposal(_randomProposalId);
    }

    // todo think on other fuzzy options
}
