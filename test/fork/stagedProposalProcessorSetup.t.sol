// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ForkBaseTest} from "./ForkBaseTest.t.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";

import {console} from "forge-std/console.sol";

contract stagedProposalProcessorSetup_ForkTest is ForkBaseTest {
    function test_installSPP() external {
        // install spp

        (DAO dao, DAOFactory.InstalledPlugin[] memory installedPlugins) = _createDummyDaoAdmin();

        // console.log(address(dao));
        // console.log(installedPlugins.length);
        // console.log(installedPlugins[0].plugin);

        // check if spp is installed
    }
}
