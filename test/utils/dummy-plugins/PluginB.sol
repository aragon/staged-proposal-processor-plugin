// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {TrustedForwarder} from "../../../src/utils/TrustedForwarder.sol";

import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

contract PluginB {
    error NotPossible();

    TrustedForwarder public trustedForwarder;

    constructor(address _trustedForwarder) {
        trustedForwarder = TrustedForwarder(_trustedForwarder);
    }

    function execute(
        uint256 proposalId,
        Action[] memory actions
    ) external returns (bytes[] memory execResults, uint256 failureMap) {
        (execResults, failureMap) = trustedForwarder.execute(bytes32(proposalId), actions, 0);
    }
}
