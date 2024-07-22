// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.8;

import {TrustedForwarder} from "../../../src/utils/TrustedForwarder.sol";

import {IDAO} from "@aragon/osx-commons-contracts-new/src/dao/IDAO.sol";

contract PluginB {
    error NotPossible();

    TrustedForwarder public trustedForwarder;

    constructor(address _trustedForwarder) {
        trustedForwarder = TrustedForwarder(_trustedForwarder);
    }

    function execute(
        bytes32 proposalId,
        IDAO.Action[] memory actions
    ) external returns (bytes[] memory execResults, uint256 failureMap) {
        (execResults, failureMap) = trustedForwarder.execute(proposalId, actions, 0);
    }
}
