// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {TrustedForwarder} from "../../../../src/utils/TrustedForwarder.sol";

import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {
    IProposal
} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {IExecutor} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {Proposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/Proposal.sol";

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract PluginA is IERC165, Proposal {
    bool public created;
    uint256 public proposalId;

    IPlugin.TargetConfig public targetConfig;

    mapping(uint256 => Action) public actions;
    mapping(uint256 => bytes) public extraParams;

    bool public revertOnCreateProposal;
    bool public needExtraParams;
    bool public canExecuteResult = true;

    mapping(address => bool) public members;

    constructor(IPlugin.TargetConfig memory _targetConfig) {
        targetConfig = _targetConfig;
    }

    event ProposalCreated(uint256 proposalId, uint64 startDate, uint64 endDate);

    function supportsInterface(
        bytes4 _interfaceId
    ) public view virtual override(Proposal, IERC165) returns (bool) {
        return
            _interfaceId == type(IProposal).interfaceId ||
            _interfaceId == type(IERC165).interfaceId;
    }

    function createProposal(
        bytes calldata _metadata,
        Action[] calldata _actions,
        uint64 startDate,
        uint64 endDate,
        bytes memory data
    ) external override returns (uint256 _proposalId) {
        if (revertOnCreateProposal) revert("revertOnCreateProposal");

        _proposalId = _createProposalId(keccak256(_metadata));
        proposalId = proposalId + 1;
        actions[_proposalId] = _actions[0];
        created = true;

        emit ProposalCreated(_proposalId, startDate, endDate);

        if (needExtraParams) {
            if (data.length == 0) {
                revert("needExtraParams");
            } else {
                extraParams[_proposalId] = data;
            }
        }

        return _proposalId;
    }

    function isMember(address _who) public view returns (bool) {
        return members[_who];
    }

    function setMember(address _who) external {
        members[_who] = true;
    }

    function _createProposalId(bytes32) internal view override returns (uint256) {
        return proposalId;
    }

    function hasSucceeded(uint256) public view returns (bool) {
        return canExecuteResult;
    }

    function customProposalParamsABI() external pure override returns (string memory) {
        return "";
    }

    function execute(
        uint256 _proposalId
    ) external returns (bytes[] memory execResults, uint256 failureMap) {
        Action[] memory mainActions = new Action[](1);
        mainActions[0] = actions[_proposalId];
        if (targetConfig.operation == IPlugin.Operation.DelegateCall) {
            bool success;
            bytes memory data;
            (success, data) = targetConfig.target.delegatecall(
                abi.encodeCall(IExecutor.execute, (bytes32(_proposalId), mainActions, 1))
            );
            (execResults, failureMap) = abi.decode(data, (bytes[], uint256));

            // (execResults, failureMap) = targetConfig.target.execute(
            //     bytes32(_proposalId),
            //     mainActions,
            //     1
            // );
        } else {
            (execResults, failureMap) = IExecutor(targetConfig.target).execute(
                bytes32(_proposalId),
                mainActions,
                0
            );
        }
    }

    function proposalCount() public view override returns (uint256) {
        return proposalId;
    }

    function setRevertOnCreateProposal(bool _revertOnCreateProposal) external {
        revertOnCreateProposal = _revertOnCreateProposal;
    }

    function setCanExecuteResult(bool _canExecuteResult) external {
        canExecuteResult = _canExecuteResult;
    }

    function setNeedExtraParams(bool _needExtraParams) external {
        needExtraParams = _needExtraParams;
    }
}
