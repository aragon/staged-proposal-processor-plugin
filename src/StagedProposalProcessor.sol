// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {Errors} from "./libraries/Errors.sol";

import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {
    PluginUUPSUpgradeable
} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {
    IProposal
} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {
    ProposalUpgradeable
} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/ProposalUpgradeable.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {MetadataExtensionUpgradeable} from "@aragon/osx-commons-contracts/src/utils/metadata/MetadataExtensionUpgradeable.sol";

contract StagedProposalProcessor is ProposalUpgradeable, MetadataExtensionUpgradeable, PluginUUPSUpgradeable {
    using ERC165Checker for address;

    /// @notice The ID of the permission required to call the `createProposal` function.
    bytes32 public constant CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");

    /// @notice The ID of the permission required to call the `setTrustedForwarder` function.
    bytes32 public constant SET_TRUSTED_FORWARDER_PERMISSION_ID = keccak256("SET_TRUSTED_FORWARDER_PERMISSION");

    /// @notice The ID of the permission required to call the `updateStages` function.
    bytes32 public constant UPDATE_STAGES_PERMISSION_ID = keccak256("UPDATE_STAGES_PERMISSION");

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
        Action[] actions;
        uint16 currentStage; // At which stage the proposal is.
        uint16 stageConfigIndex; // What stage configuration the proposal is using
        bool executed;
        TargetConfig targetConfig;
    }

    // proposalId => stageId => pluginAddress => subProposalId
    mapping(uint256 => mapping(uint256 => mapping(address => uint256))) public pluginProposalIds;

    // proposalId => stageId => proposalType => allowedBody => true/false
    mapping(uint256 => mapping(uint16 => mapping(ProposalType => mapping(address => bool))))
        private pluginResults;

    mapping(uint256 => Proposal) private proposals;
    mapping(uint256 => Stage[]) private stages;
    mapping(uint256 => bytes[][]) private createProposalParams;

    uint16 private currentConfigIndex; // Index from `stages` storage mapping
    address private trustedForwarder;

    event ProposalAdvanced(uint256 indexed proposalId, uint256 indexed stageId);
    event ProposalResultReported(uint256 indexed proposalId, address indexed plugin);
    event StagesUpdated(Stage[] stages);
    event TrustedForwarderUpdated(address indexed forwarder);

    /// @notice Initializes the component.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    /// @param _dao The IDAO interface of the associated DAO.
    /// @param _trustedForwarder The trusted forwarder responsible for extracting the original sender.
    /// @param _stages The stages configuration.
    /// @param _pluginMetadata The utf8 bytes of a content addressing cid that stores plugin's information.
    function initialize(
        IDAO _dao,
        address _trustedForwarder,
        Stage[] calldata _stages,
        bytes calldata _pluginMetadata,
        TargetConfig calldata _targetConfig
    ) external initializer {
        __PluginUUPSUpgradeable_init(_dao);

        // Allows installation even if `stages` are not present.
        // This ensures flexibility as users can still install the plugin and decide
        // later to apply configurations.
        if (_stages.length > 0) {
            _updateStages(_stages);
        }

        if(_trustedForwarder != address(0)) {
            _setTrustedForwarder(_trustedForwarder);
        }

        _updateMetadata(_pluginMetadata);
        _setTargetConfig(_targetConfig);
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(
        bytes4 _interfaceId
    ) public view virtual override(PluginUUPSUpgradeable, MetadataExtensionUpgradeable, ProposalUpgradeable) returns (bool) {
        return super.supportsInterface(_interfaceId);
    }

    /// @notice Allows to update stage configuration.
    /// @param _stages The stages configuration.
    function updateStages(Stage[] calldata _stages) external auth(UPDATE_STAGES_PERMISSION_ID) {
        if (_stages.length == 0) {
            revert Errors.StageCountZero();
        }
        _updateStages(_stages);
    }
    
    /// @notice Sets a new trusted forwarder address.
    /// @param _forwarder The trusted forwarder.
    function setTrustedForwarder(address _forwarder) public virtual auth(SET_TRUSTED_FORWARDER_PERMISSION_ID) {
        _setTrustedForwarder(_forwarder);
    }

    /// @return Returns the address of the trusted forwarder.
    function getTrustedForwarder() public virtual view returns (address){
        return trustedForwarder;
    }

    /// @notice Creates a proposal only on non-manual plugins of the first stage.
    /// @param _metadata The metadata of the proposal.
    /// @param _actions The actions that will be executed after the proposal passes.
    /// @param _allowFailureMap Allows proposal to succeed even if an action reverts.
    /// Uses bitmap representation.
    /// If the bit at index `x` is 1, the tx succeeds even if the action at `x` failed.
    /// Passing 0 will be treated as atomic execution.
    /// @param _data The extra abi encoded parameters for each sub-plugin's createProposal function.
    /// @return proposalId The ID of the proposal.
    function createProposal(
        bytes memory _metadata,
        Action[] memory _actions,
        uint256 _allowFailureMap,
        uint64 _startDate,
        bytes[][] memory _data
    ) public virtual auth(CREATE_PROPOSAL_PERMISSION_ID) returns (uint256 proposalId) {
        // If `currentConfigIndex` is 0, this means the plugin was installed
        // with empty configurations and still hasn't updated stages
        // in which case we should revert.
        uint16 index = getCurrentConfigIndex();
        if (index == 0) {
            revert Errors.StageCountZero();
        }

        proposalId = createProposalId(_actions, _metadata);

        Proposal storage proposal = proposals[proposalId];

        if (proposal.lastStageTransition != 0) {
            revert Errors.ProposalAlreadyExists(proposalId);
        }

        proposal.allowFailureMap = _allowFailureMap;
        proposal.metadata = _metadata;
        proposal.creator = msg.sender; 
        proposal.targetConfig = getTargetConfig();

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

        // No need to store the very first stage's data as it only 
        // gets used in this very transaction. 
        if (_data.length > 1) {
            bytes[][] memory tempData = new bytes[][](_data.length - 1);
            for (uint i = 1; i < _data.length; i++) {
                tempData[i - 1] = _data[i];
            }
            createProposalParams[proposalId] = tempData;
        }

        _createPluginProposals(
            proposalId,
            0,
            proposal.lastStageTransition,
            _data.length > 0 ? _data[0] : new bytes[](0)
        );

        emit ProposalCreated({
            proposalId: proposalId,
            creator: msg.sender,
            startDate: proposal.lastStageTransition,
            endDate: 0,
            metadata: _metadata,
            actions: _actions,
            allowFailureMap: _allowFailureMap
        });
    }

    /// @inheritdoc IProposal
    function createProposal(
        bytes memory _metadata,
        Action[] memory _actions,
        uint64 _startDate,
        uint64 /** */,
        bytes memory _data
    ) public virtual override returns (uint256 proposalId) {
        proposalId = uint256(
            createProposal(_metadata, _actions, 0, _startDate, abi.decode(_data, (bytes[][])))
        );
    }

    /// @inheritdoc IProposal
    /// @dev Since SPP is also IProposal, it's required to override. Though, ABI can not be defined at compile time.
    function createProposalParamsABI() external pure virtual override returns (string memory) {
        return "";
    }

    /// @notice Hashing function used to (re)build the proposal id from the proposal details..
    /// @dev The proposal id is produced by hashing the ABI encoded `targets` array, the `values` array, the `calldatas` array
    /// and the descriptionHash (bytes32 which itself is the keccak256 hash of the description string). This proposal id
    /// can be produced from the proposal data which is part of the {ProposalCreated} event. It can even be computed in
    /// advance, before the proposal is submitted.
    /// The chainId and the governor address are not part of the proposal id computation. Consequently, the
    /// same proposal (with same operation and same description) will have the same id if submitted on multiple governors
    /// across multiple networks. This also means that in order to execute the same operation twice (on the same
    /// governor) the proposer will have to change the description in order to avoid proposal id conflicts.
    /// @param _actions The actions that will be executed after the proposal passes.
    /// @param _metadata The metadata of the proposal.
    /// @return proposalId The ID of the proposal.
    function createProposalId(
        Action[] memory _actions,
        bytes memory _metadata
    ) public pure virtual override returns (uint256) {
        return uint256(keccak256(abi.encode(_actions, _metadata)));
    }

    /// @notice Returns all information for a proposal by its ID.
    /// @param _proposalId The ID of the proposal.
    /// @return Proposal The proposal struct
    function getProposal(uint256 _proposalId) public view returns (Proposal memory) {
        return proposals[_proposalId];
    }

    /// @notice Returns whether the plugin has submitted its result or not.
    /// @param _proposalId The ID of the proposal.
    /// @param _stageId Stage number in the stages array.
    /// @param _proposalType The type setting that plugin is assigned(veto/approval).
    /// @return bool Returns true if the plugin already reported the result.
    function getPluginResult(
        uint256 _proposalId,
        uint16 _stageId,
        ProposalType _proposalType,
        address _body
    ) public view virtual returns (bool) {
        return pluginResults[_proposalId][_stageId][_proposalType][_body];
    }

    /// @notice Returns the current config index at which current configurations of stages are stored.
    /// @return The current config index.
    function getCurrentConfigIndex() public view virtual returns (uint16) {
        return currentConfigIndex;
    }

    /// @notice Returns the current stages.
    /// @return The currently applied stages.
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
        uint256 _proposalId,
        ProposalType _proposalType,
        bool _tryAdvance
    ) external virtual {
        Proposal storage proposal = proposals[_proposalId];

        if (proposal.lastStageTransition == 0) {
            revert Errors.ProposalNotExists(_proposalId);
        }

        _processProposalResult(_proposalId, _proposalType);

        if (_tryAdvance && _canProposalAdvance(_proposalId)) {
            // advance proposal
            _advanceProposal(_proposalId);
        }
    }

    /// @notice Advances the proposal to the next stage in case it's allowed.
    /// Useful for plugin uninstallation when revoked from ANY_ADDR, leaving no one with this permission.
    /// @param _proposalId The ID of the proposal.
    function advanceProposal(uint256 _proposalId) public virtual {
        Proposal storage proposal = proposals[_proposalId];

        if (proposal.lastStageTransition == 0) {
            revert Errors.ProposalNotExists(_proposalId);
        }

        if (_canProposalAdvance(_proposalId)) {
            // advance
            _advanceProposal(_proposalId);
        } else {
            //  revert
            revert Errors.ProposalCannotAdvance(_proposalId);
        }
    }

    /// @notice Decides if the proposal can be advanced to the next stage.
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if the proposal can be advanced.
    function canProposalAdvance(uint256 _proposalId) public view virtual returns (bool) {
        Proposal storage proposal = proposals[_proposalId];
        if (proposal.lastStageTransition == 0) {
            revert Errors.ProposalNotExists(_proposalId);
        }

        return _canProposalAdvance(_proposalId);
    }

    /// @notice Calculates the votes and vetoes for a proposal.
    /// @param _proposalId The ID of the proposal.
    /// @return votes The number of votes for the proposal.
    /// @return vetoes The number of vetoes for the proposal.
    function getProposalTally(
        uint256 _proposalId
    ) public view virtual returns (uint256 votes, uint256 vetoes) {
        Proposal storage proposal = proposals[_proposalId];

        if (proposal.lastStageTransition == 0) {
            revert Errors.ProposalNotExists(_proposalId);
        }

        return _getProposalTally(_proposalId);
    }

    /// @notice Necessary to abide the rules of IProposal interface.
    /// @param _proposalId The proposal Id.
    /// @return bool Returns if proposal can be executed or not.
    function canExecute(uint256 _proposalId) public view virtual override returns (bool) {
        Proposal storage proposal = proposals[_proposalId];
        if (proposal.lastStageTransition == 0) {
            revert Errors.ProposalNotExists(_proposalId);
        }

        Stage[] storage _stages = stages[proposal.stageConfigIndex];

        if (proposal.currentStage == _stages.length - 1 && _canProposalAdvance(_proposalId)) {
            return true;
        }

        return false;
    }

    /// @param _proposalId The ID of the proposal.
    /// @return The subplugins' createProposal's `data` parameter encoded. This doesn't include the very first stage's data.
    function getCreateProposalParams(uint256 _proposalId) public view returns (bytes[][] memory) {
        return createProposalParams[_proposalId];
    }

    // =========================== INTERNAL/PRIVATE FUNCTIONS =============================

    /// @notice Internal function to update stage configuration.
    /// @dev It's a caller's responsibility not to call this in case `_stages` are empty.
    /// @param _stages The stages configuration.
    function _updateStages(Stage[] memory _stages) internal virtual {
        Stage[] storage storedStages = stages[++currentConfigIndex];

        for (uint256 i = 0; i < _stages.length;) {
            Stage storage stage = storedStages.push();

            for (uint256 j = 0; j < _stages[i].plugins.length;) {
                if (
                    !_stages[i].plugins[j].isManual &&
                    !_stages[i].plugins[j].pluginAddress.supportsInterface(
                        type(IProposal).interfaceId
                    )
                ) {
                    revert Errors.InterfaceNotSupported();
                }

                // If not copied manually, requires via-ir compilation 
                // pipeline which is still slow.
                stage.plugins.push(_stages[i].plugins[j]);

                unchecked {
                    ++j;
                }
            }

            stage.maxAdvance = _stages[i].maxAdvance;
            stage.minAdvance = _stages[i].minAdvance;
            stage.approvalThreshold = _stages[i].approvalThreshold;
            stage.vetoThreshold = _stages[i].vetoThreshold;
            stage.voteDuration = _stages[i].voteDuration;

            unchecked {
                ++i;
            }
        }

        emit StagesUpdated(_stages);
    }

    /// @notice Internal function that executes the proposal's actions.
    /// @param _proposalId The ID of the proposal.
    function _executeProposal(uint256 _proposalId) internal virtual {
        Proposal storage proposal = proposals[_proposalId];
        proposal.executed = true;

        _execute(
            proposal.targetConfig.target,
            bytes32(_proposalId),
            proposal.actions,
            proposal.allowFailureMap,
            proposal.targetConfig.operation
        );

        emit ProposalExecuted(_proposalId);
    }

    /// @notice Records the result by the caller.
    /// @dev Results can be recorded at any time, but only once per plugin.
    /// @param _proposalId The ID of the proposal.
    /// @param _proposalType which method to use when reporting(veto or approval)
    function _processProposalResult(
        uint256 _proposalId,
        ProposalType _proposalType
    ) internal virtual {
        Proposal storage proposal = proposals[_proposalId];

        address sender = msg.sender;

        // If sender is a trusted trustedForwarder, that means
        // it would have appended the original sender in the calldata.
        if (sender == trustedForwarder) {
            assembly {
                // get the last 20 bytes as an address which was appended
                // by the trustedForwarder before calling this function.
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        }

        pluginResults[_proposalId][proposal.currentStage][_proposalType][sender] = true;
        emit ProposalResultReported(_proposalId, sender);
    }

    /// @notice Creates proposals on the non-manual plugins of the `stageId`.
    /// @param _proposalId The ID of the proposal.
    /// @param _stageId stage number of the stages configuration array.
    function _createPluginProposals(
        uint256 _proposalId,
        uint16 _stageId,
        uint64 _startDate,
        bytes[] memory _createProposalParams
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

            Action[] memory actions = new Action[](1);
            actions[0] = Action({to: address(this), value: 0, data: actionData});

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
                    _startDate + stage.voteDuration,
                    _createProposalParams.length > 0 ? _createProposalParams[i] : bytes("")
                )
            returns (uint256 pluginProposalId) {
                pluginProposalIds[_proposalId][_stageId][
                    stage.plugins[i].pluginAddress
                ] = pluginProposalId;
            } catch {
                // Handles the edge case where:
                // on success: it could return 0
                // on failure: default 0 would be used
                // In order to differentiate, we store `uint256.max` on failure.

                uint256 gasAfter = gasleft();

                if (gasAfter < gasBefore / 64) {
                    revert Errors.InsufficientGas();
                }

                pluginProposalIds[_proposalId][_stageId][stage.plugins[i].pluginAddress] = type(
                    uint256
                ).max;
            }
        }
    }

    /// @notice Internal function that decides if the proposal can be advanced to the next stage.
    /// @dev Note that it's a caller's responsibility to check if proposal exists.
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if the proposal can be advanced.
    function _canProposalAdvance(uint256 _proposalId) internal view virtual returns (bool) {
        // Cheaper to do 2nd sload than to pass Proposal memory.
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

        (uint256 approvals, uint256 vetoes) = _getProposalTally(_proposalId);

        if (stage.vetoThreshold > 0 && vetoes >= stage.vetoThreshold) {
            return false;
        }

        if (approvals >= stage.approvalThreshold) {
            return true;
        }

        return false;
    }

    /// @notice Internal function to calculate the votes and vetoes for a proposal.
    /// @param _proposalId The proposal Id.
    /// @return votes The number of votes for the proposal.
    /// @return vetoes The number of vetoes for the proposal.
    function _getProposalTally(
        uint256 _proposalId
    ) internal view returns (uint256 votes, uint256 vetoes) {
        // Cheaper to do 2nd sload than to pass Proposal memory.
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
                // result was already reported
                plugin.proposalType == ProposalType.Approval ? ++votes : ++vetoes;
            } else if (pluginProposalId != type(uint256).max && !plugin.isManual) {
                // result was not reported yet
                if (IProposal(stage.plugins[i].pluginAddress).canExecute(pluginProposalId)) {
                    plugin.proposalType == ProposalType.Approval ? ++votes : ++vetoes;
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Internal function to advance the proposal.
    /// @dev Note that is assumes the proposal can advance.
    /// @param _proposalId The proposal Id.
    function _advanceProposal(uint256 _proposalId) internal virtual {
        Proposal storage _proposal = proposals[_proposalId];
        Stage[] storage _stages = stages[_proposal.stageConfigIndex];

        _proposal.lastStageTransition = uint64(block.timestamp);

        if (_proposal.currentStage < _stages.length - 1) {
            uint16 newStage = ++_proposal.currentStage;

            bytes[][] memory params = createProposalParams[_proposalId];

            _createPluginProposals(
                _proposalId,
                newStage,
                uint64(block.timestamp),
                // Because we don't store the very first stage's `_data`, 
                // subtract 1 to retrieve next stage's data.
                params.length > 0 ? params[newStage - 1] : new bytes[](0)
            );

            emit ProposalAdvanced(_proposalId, newStage);
        } else {
            // always execute if it is the last stage
            _executeProposal(_proposalId);
        }
    }

    /// @notice Sets a new trusted forwarder address and emits the event.
    /// @param _forwarder The trusted forwarder.
    function _setTrustedForwarder(address _forwarder) internal virtual {
        trustedForwarder = _forwarder;

        emit TrustedForwarderUpdated(_forwarder);
    }

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps

    /// TODO: adjust the reserved gap size
    uint256[43] private __gap;
}
