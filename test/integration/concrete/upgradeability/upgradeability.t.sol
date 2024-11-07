// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {BaseTest} from "../../../BaseTest.t.sol";
import {Errors} from "../../../../src/libraries/Errors.sol";
import {StagedProposalProcessor as SPP} from "../../../../src/StagedProposalProcessor.sol";

contract Upgradeability_SPP_IntegrationTest is BaseTest {
    address implementation;
    address proxy;

    function setUp() public override {
        super.setUp();

        implementation = address(new SPP());

        proxy = createProxyAndCall(
            implementation,
            abi.encodeCall(
                SPP.initialize,
                (
                    dao,
                    address(trustedForwarder),
                    new SPP.Stage[](0),
                    DUMMY_METADATA,
                    defaultTargetConfig
                )
            )
        );
    }

    function test_initializable() external {
        // it should not initialize the implementation contract
        // it should initialize the proxy contract

        // implementation contract is not initialized
        assertEq(SPP(implementation).getMetadata(), (new bytes(0)));

        // proxy already initialized
        (bool success, ) = address(proxy).call(
            abi.encodeCall(
                SPP.initialize,
                (
                    dao,
                    address(trustedForwarder),
                    new SPP.Stage[](0),
                    DUMMY_METADATA,
                    defaultTargetConfig
                )
            )
        );
        assertFalse(success);
    }

    function test_proxyImplSlot() external {
        // checks the implementation address inside the IMPL_SLOT

        bytes32 proxySlot = vm.load(address(proxy), IMPL_SLOT);
        assertEq(proxySlot, bytes32(uint256(uint160(address(implementation)))));
    }

    function test_implUpgradeTo() external {
        resetPrank(users.unauthorized);
        SPP implementation2 = new SPP();

        vm.expectRevert();
        (bool succeed, ) = address(proxy).delegatecall(
            abi.encodeWithSignature("upgradeTo(address)", address(implementation2))
        );
        assertFalse(succeed);

        resetPrank(users.manager);

        // Checking the IMPL_SLOT before upgrading the implementation contract
        bytes32 proxySlotBefore = vm.load(address(proxy), IMPL_SLOT);
        assertEq(proxySlotBefore, bytes32(uint256(uint160(address(implementation)))));

        (bool success, ) = address(proxy).delegatecall(
            abi.encodeWithSignature("upgradeTo(address)", address(implementation2))
        );
        assertTrue(success);

        bytes32 proxySlotAfter = vm.load(address(proxy), IMPL_SLOT);
        assertEq(proxySlotAfter, bytes32(uint256(uint160(address(implementation)))));
    }

    function test_validateUpgrade() external {
        /**
         *  todo add a validity test using oz foundry upgrades,
         *  todo it is no currently validating legacy upgrades new deployments
         *  todo just new upgrades,
         *  tets for storage layout and _gaps are needed
         */

        vm.skip(true);
    }
}
