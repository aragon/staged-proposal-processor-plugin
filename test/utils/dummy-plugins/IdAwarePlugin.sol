// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {
    IProposal
} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {Proposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/Proposal.sol";

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

// dummy plugin whose `hasSucceeded` depends on the proposal id it is asked about, unlike
// `PluginA` which answers the same for every id. Its sub-proposal ids start at 1, so the
// zero SPP holds in `bodyProposalIds` before writing the real id never matches one.
contract IdAwarePlugin is IERC165, Proposal {
    uint256 public nextProposalId = 1;

    mapping(uint256 => bool) public succeeded;

    function supportsInterface(
        bytes4 _interfaceId
    ) public view virtual override(Proposal, IERC165) returns (bool) {
        return
            _interfaceId == type(IProposal).interfaceId ||
            _interfaceId == type(IERC165).interfaceId;
    }

    function setSucceeded(uint256 _proposalId, bool _succeeded) external {
        succeeded[_proposalId] = _succeeded;
    }

    function createProposal(
        bytes calldata,
        Action[] calldata,
        uint64,
        uint64,
        bytes memory
    ) external override returns (uint256 _proposalId) {
        _proposalId = nextProposalId;
        nextProposalId = nextProposalId + 1;
    }

    function _createProposalId(bytes32) internal view override returns (uint256) {
        return nextProposalId;
    }

    function hasSucceeded(uint256 _proposalId) public view returns (bool) {
        return succeeded[_proposalId];
    }

    function customProposalParamsABI() external pure override returns (string memory) {
        return "";
    }

    function canExecute(uint256 _proposalId) external view returns (bool) {
        return succeeded[_proposalId];
    }

    function execute(uint256) external pure {
        revert("IdAwarePlugin: execute not supported");
    }

    function proposalCount() public view override returns (uint256) {
        return nextProposalId - 1;
    }
}
