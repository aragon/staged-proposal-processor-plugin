// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {Errors} from "./libraries/Errors.sol";

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {
    PluginUUPSUpgradeable
} from "@aragon/osx-commons-contracts-new/src/plugin/PluginUUPSUpgradeable.sol";
import {IDAO} from "@aragon/osx-commons-contracts-new/src/dao/IDAO.sol";
import {
    IProposal
} from "@aragon/osx-commons-contracts-new/src/plugin/extensions/proposal/IProposal.sol";

import "forge-std/console.sol";

contract StagedProposalProcessor is IProposal, PluginUUPSUpgradeable {
    using Counters for Counters.Counter;
    using ERC165Checker for address;

    /// @notice The ID of the permission required to call the `createProposal` function.
    bytes32 public constant CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");

    /// @notice The ID of the permission required to call the `advanceProposal` function.
    bytes32 public constant ADVANCE_PROPOSAL_PERMISSION_ID =
        keccak256("ADVANCE_PROPOSAL_PERMISSION");

    /// @notice The ID of the permission required to call the `updateMetadata` function.
    bytes32 public constant UPDATE_METADATA_PERMISSION_ID = keccak256("UPDATE_METADATA_PERMISSION");

    /// @notice The ID of the permission required to call the `updateStages` function.
    bytes32 public constant UPDATE_STAGES_PERMISSION_ID = keccak256("UPDATE_STAGES_PERMISSION");

    /// @notice The incremental ID for proposals.
    Counters.Counter private counter;

    enum ProposalType {
        Approval,
        Veto
    }

    struct Plugin {
        address pluginAddress;
        bool isManual;
        address allowedBody;
        ProposalType proposalType;
    }

    // Stage Settings
    struct Stage {
        Plugin[] plugins;
        uint64 maxAdvance;
        uint64 minAdvance;
        uint64 voteDuration;
        uint16 approvalThreshold;
        uint16 vetoThreshold;
    }

    struct Proposal {
        uint256 allowFailureMap;
        address creator;
        uint64 lastStageTransition;
        bytes metadata;
        IDAO.Action[] actions;
        uint16 currentStage; // At which stage the proposal is.
        uint16 stageConfigIndex; // What stage configuration the proposal is using
        bool executed;
    }

    // proposalId => stageId => pluginAddress => subProposalId
    mapping(bytes32 => mapping(uint256 => mapping(address => uint256))) public pluginProposalIds;

    // proposalId => stageId => proposalType => allowedBody => true/false
    mapping(bytes32 => mapping(uint16 => mapping(ProposalType => mapping(address => bool))))
        private pluginResults;

    mapping(bytes32 => Proposal) private proposals;
    mapping(uint => Stage[]) private stages;

    // the StagedProposalProcessor metadata cid
    bytes private metadata;

    uint16 private currentConfigIndex; // Index from `stages` storage mapping
    address public trustedForwarder;

    event ProposalAdvanced(bytes32 indexed proposalId, uint256 indexed stageId);
    event ProposalResult(bytes32 indexed proposalId, address indexed plugin);
    event MetadataUpdated(bytes releaseMetadata);
    event StagesUpdated(Stage[] stages);

    /// @notice Initializes the component.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    /// @param _dao The IDAO interface of the associated DAO.
    /// @param _trustedForwarder The trusted forwarder responsible for extracting the original sender.
    /// @param _stages The stages configuration.
    /// @param _metadata The utf8 bytes of a content addressing cid that stores plugin's information.
    function initialize(
        IDAO _dao,
        address _trustedForwarder,
        Stage[] calldata _stages,
        bytes calldata _metadata
    ) external initializer {
        __PluginUUPSUpgradeable_init(_dao);

        // Allows installation even if `stages` are not present.
        // This ensures flexibility as users can still install the plugin and decide
        // later to apply configurations.
        if (_stages.length > 0) {
            _updateStages(_stages);
        }

        _updateMetadata(_metadata);

        trustedForwarder = _trustedForwarder;
    }

    /// @notice Allows to update stage configuration.
    /// @param _stages The stages configuration.
    function updateStages(Stage[] calldata _stages) external auth(UPDATE_STAGES_PERMISSION_ID) {
        if (_stages.length == 0) {
            revert Errors.StageCountZero();
        }
        _updateStages(_stages);
    }

    /// @notice Allows to update only the metadata.
    /// @param _metadata The utf8 bytes of a content addressing cid that stores plugin's information.
    function updateMetadata(bytes calldata _metadata) external auth(UPDATE_METADATA_PERMISSION_ID) {
        _updateMetadata(_metadata);
    }

    /// @notice Creates a proposal only on non-manual plugins of the first stage.
    /// @param _metadata The metadata of the proposal.
    /// @param _actions The actions that will be executed after the proposal passes.
    /// @param _allowFailureMap Allows proposal to succeed even if an action reverts.
    /// Uses bitmap representation.
    /// If the bit at index `x` is 1, the tx succeeds even if the action at `x` failed.
    /// Passing 0 will be treated as atomic execution.
    /// @return proposalId The ID of the proposal.
    function createProposal(
        bytes calldata _metadata,
        IDAO.Action[] calldata _actions,
        uint256 _allowFailureMap,
        uint64 _startDate
    ) public auth(CREATE_PROPOSAL_PERMISSION_ID) returns (bytes32 proposalId) {
        // If `currentConfigIndex` is 0, this means the plugin was installed
        // with empty configurations and still hasn't updated stages
        // in which case we should revert.
        uint16 index = getCurrentConfigIndex();
        if (index == 0) {
            revert Errors.StageCountZero();
        }

        uint256 _proposalId = counter.current();
        counter.increment();

        // Include block.timestamp to minimize the chance
        // for sub-plugins to create proposals in advance.
        proposalId = keccak256(abi.encode(block.timestamp, address(this), _proposalId));

        Proposal storage proposal = proposals[proposalId];
        proposal.allowFailureMap = _allowFailureMap;
        proposal.metadata = _metadata;
        proposal.creator = msg.sender;
        // store stage configuration per proposal to avoid
        // changing it while proposal is still open
        proposal.stageConfigIndex = index;

        // if the startDate is in the past use the current block timestamp
        proposal.lastStageTransition = _startDate > uint64(block.timestamp)
            ? _startDate
            : uint64(block.timestamp);

        for (uint256 i = 0; i < _actions.length; ) {
            proposal.actions.push(_actions[i]);

            unchecked {
                ++i;
            }
        }

        _createPluginProposals(proposalId, 0, proposal.lastStageTransition);

        emit ProposalCreated({
            proposalId: uint256(proposalId),
            creator: msg.sender,
            startDate: proposal.lastStageTransition,
            endDate: 0,
            metadata: _metadata,
            actions: _actions,
            allowFailureMap: _allowFailureMap
        });
    }

    function createProposal(
        bytes calldata _metadata,
        IDAO.Action[] calldata _actions,
        uint64 _startDate,
        uint64 /** */
    ) external override returns (uint256 proposalId) {
        proposalId = uint256(createProposal(_metadata, _actions, 0, _startDate));
    }

    /// @notice Returns all information for a proposal by its ID.
    /// @param _proposalId The ID of the proposal.
    /// @return Proposal The proposal struct
    function getProposal(bytes32 _proposalId) public view returns (Proposal memory) {
        return proposals[_proposalId];
    }

    /// @notice Returns whether the plugin has submitted its result or not.
    /// @param _proposalId The ID of the proposal.
    /// @param _stageId Stage number in the stages array.
    /// @param _proposalType The type setting that plugin is assigned(veto/approval).
    /// @return bool Returns true if the plugin already reported the result.
    function getPluginResult(
        bytes32 _proposalId,
        uint16 _stageId,
        ProposalType _proposalType,
        address _body
    ) public view virtual returns (bool) {
        return pluginResults[_proposalId][_stageId][_proposalType][_body];
    }

    /// @inheritdoc IProposal
    function proposalCount() public view override returns (uint256) {
        return counter.current();
    }

    /// @notice Returns the current config index at which current configurations of stages are stored.
    /// @return The current config index.
    function getCurrentConfigIndex() public view virtual returns (uint16) {
        return currentConfigIndex;
    }

    /// @notice Returns the metadata currently applied.
    /// @return The metadata.
    function getMetadata() public view virtual returns (bytes memory) {
        return metadata;
    }

    /// @notice Returns the current stages.
    /// @return The metadata.
    function getStages() public view virtual returns (Stage[] memory) {
        return stages[getCurrentConfigIndex()];
    }

    /// @dev This can be called by any address that is not in the stage configuration.
    // `canProposalAdvance` is where it checks whether addresses that reported are actually in the stage configuration.
    /// @notice Reports and records the result.
    /// @param _proposalId The ID of the proposal.
    /// @param _proposalType Whether to include report as a veto or approval.
    /// @param _tryAdvance If true, tries to advance the proposal if it can be advanced.
    function reportProposalResult(
        bytes32 _proposalId,
        ProposalType _proposalType,
        bool _tryAdvance
    ) external {
        _processProposalResult(_proposalId, _proposalType);

        if (_tryAdvance) {
            // uses public function for permission check
            advanceProposal(_proposalId);
        }
    }

    /// @notice Advances the proposal to the next stage in case it's allowed.
    /// @dev `ADVANCE_PROPOSAL_PERMISSION_ID` is callable by ANY_ADDR at the time of plugin installation.
    /// Useful for plugin uninstallation when revoked from ANY_ADDR, leaving no one with this permission.
    /// @param _proposalId The ID of the proposal.
    function advanceProposal(
        bytes32 _proposalId
    ) public virtual auth(ADVANCE_PROPOSAL_PERMISSION_ID) {
        Proposal storage proposal = proposals[_proposalId];
        // TODO: do we want to restrict this ? it could be useful that proposal is created with only metadata
        // so people don't need actual action, but to vote on some "description" only.
        if (proposal.actions.length == 0) {
            revert Errors.ProposalNotExists(_proposalId);
        }

        Stage[] storage _stages = stages[proposal.stageConfigIndex];

        if (canProposalAdvance(_proposalId)) {
            proposal.lastStageTransition = uint64(block.timestamp);

            if (proposal.currentStage < _stages.length - 1) {
                uint16 newStage = proposal.currentStage + 1;
                proposal.currentStage = newStage;

                _createPluginProposals(_proposalId, newStage, uint64(block.timestamp));

                emit ProposalAdvanced(_proposalId, newStage);
            } else {
                // always execute if it is the last stage
                _executeProposal(_proposalId);
            }
        }
    }

    /// @notice Decides if the proposal can be advanced to the next stage.
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if the proposal can be advanced.
    function canProposalAdvance(bytes32 _proposalId) public view virtual returns (bool) {
        Proposal storage proposal = proposals[_proposalId];
        if (proposal.executed) {
            return false;
        }

        uint16 currentStage = proposal.currentStage;

        Stage storage stage = stages[proposal.stageConfigIndex][currentStage];

        if (proposal.lastStageTransition + stage.maxAdvance < block.timestamp) {
            return false;
        }

        if (proposal.lastStageTransition + stage.minAdvance > block.timestamp) {
            return false;
        }

        // Allow `voteDuration` to pass for plugins to have veto possibility.
        if (stage.vetoThreshold > 0) {
            if (proposal.lastStageTransition + stage.voteDuration > block.timestamp) {
                return false;
            }
        }

        (uint256 approvals, uint256 vetoes) = getProposalTally(_proposalId);

        if (stage.vetoThreshold > 0 && vetoes >= stage.vetoThreshold) {
            return false;
        }

        if (approvals >= stage.approvalThreshold) {
            return true;
        }

        return false;
    }

    /// @notice Calculates the votes and vetoes for a proposal.
    /// @param _proposalId The ID of the proposal.
    /// @return votes The number of votes for the proposal.
    /// @return vetoes The number of vetoes for the proposal.
    function getProposalTally(
        bytes32 _proposalId
    ) public view virtual returns (uint256 votes, uint256 vetoes) {
        Proposal storage proposal = proposals[_proposalId];

        uint16 currentStage = proposal.currentStage;

        Stage storage stage = stages[proposal.stageConfigIndex][currentStage];

        for (uint256 i = 0; i < stage.plugins.length; ) {
            Plugin storage plugin = stage.plugins[i];
            address allowedBody = plugin.allowedBody;

            uint256 pluginProposalId = pluginProposalIds[_proposalId][currentStage][
                plugin.pluginAddress
            ];

            if (pluginResults[_proposalId][currentStage][plugin.proposalType][allowedBody]) {
                if (plugin.proposalType == ProposalType.Approval) {
                    ++votes;
                } else {
                    ++vetoes;
                }
            } else if (
                stage.vetoThreshold > 0 &&
                plugin.proposalType == ProposalType.Veto &&
                !plugin.isManual &&
                pluginProposalId != type(uint256).max
            ) {
                if (IProposal(stage.plugins[i].pluginAddress).canExecute(pluginProposalId)) {
                    ++vetoes;
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Necessary to abide the rules of IProposal interface.
    /// @dev One must convert bytes32 proposalId into uint256 type and pass it.
    /// @param _proposalId The proposal Id.
    /// @return bool Returns if proposal can be executed or not.
    function canExecute(uint256 _proposalId) public view returns (bool) {
        bytes32 id = bytes32(_proposalId);
        Proposal storage proposal = proposals[id];
        if (proposal.creator == address(0)) {
            return false;
        }

        Stage[] storage _stages = stages[proposal.stageConfigIndex];

        if (proposal.currentStage == _stages.length - 1 && canProposalAdvance(id)) {
            return true;
        }

        return false;
    }

    // =========================== INTERNAL/PRIVATE FUNCTIONS =============================

    /// @notice Internal function to update stage configuration.
    /// @dev It's a caller's responsibility not to call this in case `_stages` are empty.
    /// @param _stages The stages configuration.
    function _updateStages(Stage[] calldata _stages) internal virtual {
        Stage[] storage storedStages = stages[++currentConfigIndex];

        for (uint256 i = 0; i < _stages.length; i++) {
            for (uint256 j = 0; j < _stages[i].plugins.length; j++) {
                if (
                    !_stages[i].plugins[j].isManual &&
                    !_stages[i].plugins[j].pluginAddress.supportsInterface(
                        type(IProposal).interfaceId
                    )
                ) {
                    revert Errors.InterfaceNotSupported();
                }
            }
            storedStages.push(_stages[i]);
        }

        emit StagesUpdated(_stages);
    }

    /// @notice Internal function to update stage configuration.
    /// @param _metadata The utf8 bytes of a content addressing cid that stores plugin's information.
    function _updateMetadata(bytes calldata _metadata) internal virtual {
        if (_metadata.length == 0) {
            revert Errors.EmptyMetadata();
        }

        metadata = _metadata;
        emit MetadataUpdated(_metadata);
    }

    /// @notice Internal function that executes the proposal's actions.
    /// @param _proposalId The ID of the proposal.
    function _executeProposal(bytes32 _proposalId) internal virtual {
        Proposal storage proposal = proposals[_proposalId];
        proposal.executed = true;
        dao().execute(_proposalId, proposal.actions, proposal.allowFailureMap);
    }

    /// @notice Records the result by the caller.
    /// @dev Results can be recorded at any time, but only once per plugin.
    /// @param _proposalId The ID of the proposal.
    /// @param _proposalType which method to use when reporting(veto or approval)
    function _processProposalResult(
        bytes32 _proposalId,
        ProposalType _proposalType
    ) internal virtual {
        Proposal storage proposal = proposals[_proposalId];

        address sender = msg.sender;
        // if sender is a trusted trustedForwarder, that means
        // it would appended the sender in the calldata
        if (msg.data.length >= 20 && msg.sender == trustedForwarder) {
            assembly {
                // get the last 20 bytes as an address which was appended
                // by the trustedForwarder before calling this function.
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        }

        pluginResults[_proposalId][proposal.currentStage][_proposalType][sender] = true;
        emit ProposalResult(_proposalId, sender);
    }

    /// @notice Creates proposals on the non-manual plugins of the `stageId`.
    /// @param _proposalId The ID of the proposal.
    /// @param _stageId stage number of the stages configuration array.
    function _createPluginProposals(
        bytes32 _proposalId,
        uint16 _stageId,
        uint64 _startDate
    ) internal virtual {
        Proposal storage proposal = proposals[_proposalId];

        Stage storage stage = stages[proposal.stageConfigIndex][_stageId];

        for (uint256 i = 0; i < stage.plugins.length; i++) {
            Plugin storage plugin = stage.plugins[i];

            // If plugin proposal creation should be manual, skip it
            if (plugin.isManual) continue;

            bytes memory actionData = abi.encodeCall(
                this.reportProposalResult,
                (_proposalId, plugin.proposalType, stage.vetoThreshold == 0)
            );

            IDAO.Action[] memory actions = new IDAO.Action[](1);
            actions[0] = IDAO.Action({to: address(this), value: 0, data: actionData});

            bytes memory proposalMetadata = abi.encode(address(this), _proposalId, _stageId);

            // Make sure that the `createProposal` call did not fail because
            // 63/64 of `gasleft()` was insufficient to execute the external call.
            // In specific scenarios, the sender could force-fail `createProposal`
            // where 63/64 is insufficient causing it to fail, but where
            // the remaining 1/64 gas are sufficient to successfully finish the call.
            uint256 gasBefore = gasleft();

            // TODO: in the createProposal standardization, shall we rename it to `data` instead of `metadata` ?
            // This way, people would understand that it could be anything.
            try
                IProposal(stage.plugins[i].pluginAddress).createProposal(
                    proposalMetadata,
                    actions,
                    _startDate,
                    _startDate + stage.voteDuration
                )
            returns (uint256 pluginProposalId) {
                pluginProposalIds[_proposalId][_stageId][
                    stage.plugins[i].pluginAddress
                ] = pluginProposalId;
            } catch {
                pluginProposalIds[_proposalId][_stageId][stage.plugins[i].pluginAddress] = type(
                    uint256
                ).max;

                uint256 gasAfter = gasleft();

                if (gasAfter < gasBefore / 64) {
                    revert Errors.InsufficientGas();
                }
            }
        }
    }

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps

    /// TODO: adjust the reserved gap size
    uint256[43] private __gap;
}
