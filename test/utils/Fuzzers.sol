// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

// import {StdUtils} from "forge-std/src/StdUtils.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {Stage, Body} from "../utils/Types.sol";
import {StagedProposalProcessor as SPP} from "../../src/StagedProposalProcessor.sol";

abstract contract Fuzzers is StdUtils {
    function fuzzSppStages(
        Stage[] memory _stages,
        Body[] memory _bodies
    ) internal pure returns (SPP.Stage[] memory _fuzzedStages) {
        SPP.Body[] memory fuzzBodies = fuzzSppBodies(_bodies);

        _fuzzedStages = new SPP.Stage[](_stages.length);
        for (uint256 i = 0; i < _stages.length; ++i) {
            _fuzzedStages[i] = SPP.Stage({
                maxAdvance: _stages[i].maxAdvance,
                minAdvance: _stages[i].minAdvance,
                voteDuration: _stages[i].voteDuration,
                approvalThreshold: uint16(bound(_stages[i].approvalThreshold, 0, _stages.length)),
                vetoThreshold: uint16(bound(_stages[i].vetoThreshold, 0, _stages.length)),
                bodies: fuzzBodies
            });
        }
    }

    function fuzzSppBodies(
        Body[] memory _bodies
    ) internal pure returns (SPP.Body[] memory _fuzzedBodies) {
        _fuzzedBodies = new SPP.Body[](_bodies.length);
        for (uint256 i = 0; i < _bodies.length; ++i) {
            _fuzzedBodies[i] = SPP.Body({
                addr: _bodies[i].addr,
                isManual: _bodies[i].isManual,
                tryAdvance: _bodies[i].tryAdvance,
                resultType: SPP.ResultType(bound(_bodies[i].resultType, 0, 1))
            });
        }
    }
}
