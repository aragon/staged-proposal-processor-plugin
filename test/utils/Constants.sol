// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

contract Constants {
    bytes internal constant EMPTY_DATA = "";
    bytes32 internal constant DUMMY_CALL_ID = "dummy call id";

    bytes internal constant DUMMY_METADATA = "dummy metadata";
    bytes internal constant EMPTY_METADATA = "";

    address internal constant ANY_ADDR = address(type(uint160).max);

    uint64 internal constant MIN_ADVANCE = 10;
    uint64 internal constant MAX_ADVANCE = 100;
    uint64 internal constant VOTE_DURATION = 50;
    uint64 internal constant START_DATE = 3;

    uint256 internal constant NON_EXISTENT_PROPOSAL_ID = uint256(0);

    uint256 internal constant TARGET_VALUE = 15;
    address internal constant TARGET_ADDRESS = address(0x1234567890123456789012345678901234567890);

    uint8 internal constant CONDITION_RULE_ID = 202;

    bytes32 internal constant IMPL_SLOT =
        bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
}
