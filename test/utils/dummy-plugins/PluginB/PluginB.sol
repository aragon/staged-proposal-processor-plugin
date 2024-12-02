// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {TrustedForwarder} from "../../../utils/TrustedForwarder.sol";

import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

contract PluginB {
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

    function hasPermission(address _who, bytes memory data) public pure returns (bool) {
        (_who, data);
        (uint256 id, uint256 value) = abi.decode(data, (uint256, uint256));
        return id == 1 && value == 1;
    }
}
