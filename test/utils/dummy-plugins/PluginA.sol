// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {TrustedForwarder} from "../../../src/utils/TrustedForwarder.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {
    IProposal
} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract PluginA is IProposal, IERC165 {
    bool public created;
    uint256 public proposalId;
    TrustedForwarder public trustedForwarder;
    mapping(uint256 => IDAO.Action) public actions;

    bool public revertOnCreateProposal;

    constructor(address _trustedForwarder) {
        trustedForwarder = TrustedForwarder(_trustedForwarder);
    }

    event ProposalCreated(uint256 proposalId, uint64 startDate, uint64 endDate);

    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return
            _interfaceId == type(IProposal).interfaceId ||
            _interfaceId == type(IERC165).interfaceId;
    }

    function createProposal(
        bytes calldata _metadata,
        IDAO.Action[] calldata _actions,
        uint64 startDate,
        uint64 endDate,
        bytes memory
    ) external override returns (uint256 _proposalId) {
        if (revertOnCreateProposal) revert("revertOnCreateProposal");

        _proposalId = createProposalId(_actions, _metadata);
        proposalId = proposalId + 1;
        actions[_proposalId] = _actions[0];
        created = true;

        emit ProposalCreated(_proposalId, startDate, endDate);
        return _proposalId;
    }

    function createProposalId(
        IDAO.Action[] memory,
        bytes memory
    ) public view override returns (uint256) {
        return proposalId;
    }

    function canExecute(uint256) public pure returns (bool) {
        // TODO: for now
        return true;
    }

    function createProposalParamsABI() external pure override returns (string memory) {
        return "";
    }

    function execute(
        uint256 _proposalId
    ) external returns (bytes[] memory execResults, uint256 failureMap) {
        IDAO.Action[] memory mainActions = new IDAO.Action[](1);
        mainActions[0] = actions[_proposalId];
        (execResults, failureMap) = trustedForwarder.execute(bytes32(_proposalId), mainActions, 0);
    }

    function proposalCount() external view override returns (uint256) {
        return proposalId;
    }

    function setRevertOnCreateProposal(bool _revertOnCreateProposal) external {
        revertOnCreateProposal = _revertOnCreateProposal;
    }
}
