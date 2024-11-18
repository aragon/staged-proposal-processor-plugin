// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

contract UpdateMetadata_SPP_UnitTest is BaseTest {
    function test_RevertWhen_CallerIsNotAllowed() external {
        // it should revert

        resetPrank(users.unauthorized);

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(sppPlugin),
                users.unauthorized,
                sppPlugin.SET_METADATA_PERMISSION_ID()
            )
        );
        sppPlugin.setMetadata(DUMMY_METADATA);
    }

    modifier whenCallerIsAllowed() {
        _;
    }

    function test_WhenMetadataIsEmpty() external whenCallerIsAllowed {
        // it should update metadata.
        // it should emit an event.

        vm.expectEmit({emitter: address(sppPlugin)});
        emit MetadataSet(EMPTY_METADATA);

        sppPlugin.setMetadata(EMPTY_METADATA);

        bytes memory _newMetadata = sppPlugin.getMetadata();
        assertEq(_newMetadata, EMPTY_METADATA);
    }

    function test_WhenMetadataIsNotEmpty() external whenCallerIsAllowed {
        // it should emit an event.
        // it should update metadata.

        vm.expectEmit({emitter: address(sppPlugin)});
        emit MetadataSet(DUMMY_METADATA);

        sppPlugin.setMetadata(DUMMY_METADATA);

        bytes memory _newMetadata = sppPlugin.getMetadata();
        assertEq(_newMetadata, DUMMY_METADATA);
    }
}
