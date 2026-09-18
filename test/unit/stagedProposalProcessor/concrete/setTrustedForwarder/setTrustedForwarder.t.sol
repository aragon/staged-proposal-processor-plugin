// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {BaseTest} from "../../../../BaseTest.t.sol";
import {Permissions} from "../../../../../src/libraries/Permissions.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

contract SetTrustedForwarder_SPP_UnitTest is BaseTest {
    address newTrustedForwarder = address(1);

    function test_RevertWhen_CallerIsNotAllowed() external {
        // it should revert.

        resetPrank(users.unauthorized);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(sppPlugin),
                users.unauthorized,
                Permissions.SET_TRUSTED_FORWARDER_PERMISSION_ID
            )
        );
        sppPlugin.setTrustedForwarder(newTrustedForwarder);
    }

    function test_WhenCallerIsAllowed() external {
        // it should set the trusted forwarder.
        // it should emit TrustedForwarderUpdated event.

        // grant permission to manager
        DAO(payable(address(dao))).grant(
            address(sppPlugin),
            users.manager,
            Permissions.SET_TRUSTED_FORWARDER_PERMISSION_ID
        );

        vm.expectEmit({emitter: address(sppPlugin)});
        emit TrustedForwarderUpdated(newTrustedForwarder);

        sppPlugin.setTrustedForwarder(newTrustedForwarder);

        // check new trusted forwarder
        assertEq(sppPlugin.getTrustedForwarder(), newTrustedForwarder);
    }
}
