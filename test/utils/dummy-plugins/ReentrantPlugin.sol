// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {
    IProposal
} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {Proposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/Proposal.sol";

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {StagedProposalProcessor as SPP} from "../../../src/StagedProposalProcessor.sol";

// dummy plugin that calls back into SPP from inside its own `createProposal`, while SPP
// has not yet written this body's entry in `bodyProposalIds`
contract ReentrantPlugin is IERC165, Proposal {
    uint256 public proposalId;

    SPP public spp;

    // the id `createProposal` returns, so the stored id can be told apart from the zero
    // the mapping holds before SPP writes it
    uint256 public returnedProposalId;

    // arbitrary call to make against SPP during `createProposal`, empty to only observe
    bytes public reentrantCalldata;

    // whether a failed reentrant call fails this body's own `createProposal` too, or is
    // swallowed so that the outer call carries on as if nothing happened
    bool public propagateFailure = true;

    // the proposal and stage SPP asked this body to create a sub-proposal for, decoded
    // from the metadata SPP passes
    bool public reentered;
    uint256 public sppProposalId;
    uint16 public sppStageId;

    // what SPP exposed during the reentrant window
    uint256 public observedBodyProposalId;
    uint8 public observedState;
    bool public observedCanAdvance;

    // outcome of `reentrantCalldata`, recorded rather than bubbled up so that the test
    // decides whether a failure matters
    bool public reentrantCallMade;
    bool public reentrantCallSucceeded;
    bytes public reentrantCallReturnData;

    function supportsInterface(
        bytes4 _interfaceId
    ) public view virtual override(Proposal, IERC165) returns (bool) {
        return
            _interfaceId == type(IProposal).interfaceId ||
            _interfaceId == type(IERC165).interfaceId;
    }

    function setUpReentrancy(
        SPP _spp,
        uint256 _returnedProposalId,
        bytes memory _reentrantCalldata
    ) external {
        spp = _spp;
        returnedProposalId = _returnedProposalId;
        reentrantCalldata = _reentrantCalldata;
    }

    function setPropagateFailure(bool _propagateFailure) external {
        propagateFailure = _propagateFailure;
    }

    function createProposal(
        bytes calldata _metadata,
        Action[] calldata,
        uint64,
        uint64,
        bytes memory
    ) external override returns (uint256) {
        proposalId = proposalId + 1;

        if (address(spp) != address(0) && !reentered) {
            reentered = true;

            // SPP passes `(address spp, uint256 proposalId, uint16 stageId)` as metadata,
            // so the proposal being created does not have to be predicted by the test.
            (, sppProposalId, sppStageId) = abi.decode(
                _metadata,
                (address, uint256, uint16)
            );

            // SPP has not written this body's id yet, so this reads the default.
            observedBodyProposalId = spp.getBodyProposalId(
                sppProposalId,
                sppStageId,
                address(this)
            );

            observedCanAdvance = spp.canProposalAdvance(sppProposalId);
            observedState = uint8(spp.state(sppProposalId));

            if (reentrantCalldata.length != 0) {
                reentrantCallMade = true;
                // solhint-disable-next-line avoid-low-level-calls
                (bool success, bytes memory data) = address(spp).call(reentrantCalldata);
                reentrantCallSucceeded = success;
                reentrantCallReturnData = data;

                // A body that does not swallow the failure lets it propagate, which fails
                // its own `createProposal` and so the whole outer call. The original
                // revert data is bubbled up so that tests can assert the exact SPP error.
                if (!success && propagateFailure) {
                    // solhint-disable-next-line no-inline-assembly
                    assembly {
                        revert(add(data, 32), mload(data))
                    }
                }
            }
        }

        return returnedProposalId;
    }

    function _createProposalId(bytes32) internal view override returns (uint256) {
        return proposalId;
    }

    // always reports success, so a tally that read the wrong id would still count it
    function hasSucceeded(uint256) public pure returns (bool) {
        return true;
    }

    function customProposalParamsABI() external pure override returns (string memory) {
        return "";
    }

    function canExecute(uint256) external pure returns (bool) {
        return true;
    }

    function execute(uint256) external pure {
        revert("ReentrantPlugin: execute not supported");
    }

    function proposalCount() public view override returns (uint256) {
        return proposalId;
    }
}
