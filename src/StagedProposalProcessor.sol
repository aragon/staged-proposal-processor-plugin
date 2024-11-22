// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Errors} from "./libraries/Errors.sol";
import {Permissions} from "./libraries/Permissions.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {
    PluginUUPSUpgradeable
} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {
    IProposal
} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {
    MetadataExtensionUpgradeable
} from "@aragon/osx-commons-contracts/src/utils/metadata/MetadataExtensionUpgradeable.sol";
import {
    ProposalUpgradeable
} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/ProposalUpgradeable.sol";

import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

/// @title StagedProposalProcessor
/// @author Aragon X - 2024
/// @notice A multi-stage proposal processor where proposals progress through defined stages.
///         Each stage is evaluated by the responsible bodies, determining whether the proposal advances
///         to the next stage. Once a proposal successfully passes all stages, it can be executed.
contract StagedProposalProcessor is
    ProposalUpgradeable,
    MetadataExtensionUpgradeable,
    PluginUUPSUpgradeable
{
    using ERC165Checker for address;

    /// @notice Used to distinguish proposals where the SPP was not able to create a proposal on a sub-body.
    uint256 private constant PROPOSAL_WITHOUT_ID = type(uint256).max;

    /// @notice The different types that bodies can be registered as.
    /// @param None Used to check if the body reported the result or not.
    /// @param Approval Used to allow a body to report approval result.
    /// @param Veto Used to allow a body to report veto result.
    enum ResultType {
        None,
        Approval,
        Veto
    }

    /// @notice The states of the proposal.
    /// TODO: add
    enum ProposalState {
        Active,
        Canceled,
        Executed,
        Advanceable,
        Expired
    }

    /// @notice A container for Body-related information.
    /// @param addr The address responsible for reporting results. For automatic bodies,
    ///     it is also where the SPP creates proposals.
    /// @param isManual Whether SPP should create a proposal on a body. If true, it will not create.
    /// @param tryAdvance Whether to try to automatically advance the stage when a body reports results.
    /// @param resultType The type(`Approval` or `Veto`) this body is registered with.
    struct Body {
        address addr;
        bool isManual;
        bool tryAdvance;
        ResultType resultType;
    }

    /// @notice A container for stage-related information.
    /// @param bodies The bodies that are responsible for advancing the stage.
    /// @param maxAdvance The maximum duration after which stage can not be advanced.
    /// @param minAdvance The minimum duration until when stage can not be advanced.
    /// @param voteDuration The time to give vetoing bodies to make decisions in optimistic stage.
    ///     Note that this also is used as an endDate time for bodies, see `_createBodyProposals`.
    /// @param approvalThreshold The number of bodies that are required to pass to advance the proposal.
    /// @param vetoThreshold If this number of bodies veto, the proposal can never advance
    ///     even if `approvalThreshold` is satisfied.
    struct Stage {
        Body[] bodies;
        uint64 maxAdvance;
        uint64 minAdvance;
        uint64 voteDuration;
        uint16 approvalThreshold;
        uint16 vetoThreshold;
        bool cancelable;
        bool editable;
    }

    /// @notice A container for proposal-related information.
    /// @param allowFailureMap A bitmap allowing the proposal to succeed, even if individual actions might revert.
    /// @param lastStageTransition The timestamp at which proposal's current stage has started.
    /// @param currentStage Which stage the proposal is at.
    /// @param stageConfigIndex The stage configuration that this proposal uses.
    /// @param executed Whether the proposal is executed or not.
    /// @param canceled Whether the proposal is canceled or not.
    /// @param creator The creator of the proposal.
    /// @param actions The actions to be executed when the proposal passes.
    /// @param targetConfig The target to which this contract will pass actions with an operation type.
    struct Proposal {
        uint128 allowFailureMap;
        uint64 lastStageTransition;
        uint16 currentStage;
        uint16 stageConfigIndex;
        bool executed;
        bool canceled;
        address creator;
        Action[] actions;
        TargetConfig targetConfig;
    }

    /// @notice A mapping to track sub-proposal IDs for a given proposal, stage, and body.
    mapping(uint256 proposalId => mapping(uint16 stageId => mapping(address body => uint256 subProposalId)))
        private bodyProposalIds;

    /// @notice A mapping to store the result types reported by bodies for a given proposal and stage.
    mapping(uint256 proposalId => mapping(uint16 stageId => mapping(address body => ResultType resultType)))
        private bodyResults;

    /// @notice A mapping to store custom proposal parameters data for a given proposal, stage, and body index.
    mapping(uint256 proposalId => mapping(uint16 stageId => mapping(uint256 bodyIndex => bytes customParams)))
        private createProposalParams;

    /// @notice A mapping between proposal IDs and their associated proposal information.
    mapping(uint256 proposalId => Proposal) private proposals;

    /// @notice A mapping between stage configuration indices and the corresponding stage configurations.
    mapping(uint256 configIndex => Stage[]) private stages;

    /// @notice The index of the current stage configuration in the `stages` mapping.
    uint16 private currentConfigIndex;

    /// @notice The address of the trusted forwarder.
    /// @dev The trusted forwarder appends the original sender's address to the calldata. If an executor is the
    ///      trusted forwarder, the `_msgSender` function extracts the original sender from the calldata.
    address private trustedForwarder;

    /// @notice Emitted when the proposal is advanced to the next stage.
    /// @param proposalId The proposal id.
    /// @param stageId The stage id.
    event ProposalAdvanced(uint256 indexed proposalId, uint256 indexed stageId);

    /// @notice Emitted when the proposal gets cancelled.
    /// @param proposalId the proposal id.
    /// @param stageId The stage id in which the proposal was cancelled.
    /// @param sender The sender that canceled the proposal.
    event ProposalCanceled(
        uint256 indexed proposalId,
        uint256 indexed stageId,
        address indexed sender
    );

    /// @notice Emitted when the proposal gets editted.
    /// @param proposalId the proposal id.
    /// @param stageId The stage id in which the proposal was editted.
    /// @param sender The sender that editted the proposal.
    /// @param metadata The new metadata that replaces old metadata.
    /// @param actions The new actions that replaces old actions.
    event ProposalEdited(
        uint256 indexed proposalId,
        uint256 indexed stageId,
        address indexed sender,
        bytes metadata,
        Action[] actions
    );

    /// @notice Emitted when a body reports results by calling `reportProposalResult`.
    /// @param proposalId The proposal id.
    /// @param stageId The stage id.
    /// @param body The sender that reported the result.
    event ProposalResultReported(
        uint256 indexed proposalId,
        uint16 indexed stageId,
        address indexed body
    );

    /// @notice Emitted when this plugin successfully creates a proposal on sub-body.
    /// @param proposalId The proposal id.
    /// @param stageId The stage id.
    /// @param body The sub-body on which sub-proposal has been created.
    /// @param bodyProposalId The proposal id that sub-body returns for later usage by this plugin.
    event SubProposalCreated(
        uint256 indexed proposalId,
        uint16 indexed stageId,
        address indexed body,
        uint256 bodyProposalId
    );

    /// @notice Emitted when this plugin fails in creating a proposal on sub-body.
    /// @param proposalId The proposal id.
    /// @param stageId The stage id.
    /// @param body The sub-body on which sub-proposal failed to be created.
    /// @param reason The reason why it was failed.
    event SubProposalNotCreated(
        uint256 indexed proposalId,
        uint16 indexed stageId,
        address indexed body,
        bytes reason
    );

    /// @notice Emitted when the stage configuration is updated for a proposal process.
    /// @param stages The array of `Stage` structs representing the updated stage configuration.
    event StagesUpdated(Stage[] stages);

    /// @notice Emitted when the trusted forwarder is updated.
    /// @param forwarder The new trusted forwarder address.
    event TrustedForwarderUpdated(address indexed forwarder);

    /// @notice Initializes the component.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    /// @param _dao The IDAO interface of the associated DAO.
    /// @param _trustedForwarder The trusted forwarder responsible for extracting the original sender.
    /// @param _stages The stages configuration.
    /// @param _pluginMetadata The utf8 bytes of a content addressing cid that stores plugin's information.
    /// @param _targetConfig The target to which this contract will pass actions with an operation type.
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

        if (_trustedForwarder != address(0)) {
            _setTrustedForwarder(_trustedForwarder);
        }

        _setMetadata(_pluginMetadata);
        _setTargetConfig(_targetConfig);
    }

    /// @notice Allows to update stage configuration.
    /// @dev Requires the caller to have the `UPDATE_STAGES_PERMISSION_ID` permission.
    ///      Reverts if the provided `_stages` array is empty.
    /// @param _stages The new stage configuration as an array of `Stage` structs.
    function updateStages(
        Stage[] calldata _stages
    ) external auth(Permissions.UPDATE_STAGES_PERMISSION_ID) {
        if (_stages.length == 0) {
            revert Errors.StageCountZero();
        }
        _updateStages(_stages);
    }

    /// @notice Reports and records the result for a proposal at a specific stage.
    /// @dev This function can be called by any address even if it is not included in the stage configuration.
    ///      `_canProposalAdvance` function ensures that only records from addresses
    ///      in the stage configuration are used.
    ///      If `_tryAdvance` is true, the proposal will attempt to advance to the next stage if eligible.
    ///      Requires the caller to have the `EXECUTE_PERMISSION_ID` permission to execute the final stage.
    /// @param _proposalId The ID of the proposal.
    /// @param _stageId The ID of the stage being reported on. Must not exceed the current stage of the proposal.
    /// @param _resultType The result type being reported (`Approval` or `Veto`).
    /// @param _tryAdvance Whether to attempt advancing the proposal to the next stage if conditions are met.
    function reportProposalResult(
        uint256 _proposalId,
        uint16 _stageId,
        ResultType _resultType,
        bool _tryAdvance
    ) external virtual {
        Proposal storage proposal = proposals[_proposalId];

        uint16 currentStage = proposal.currentStage;

        // Ensure that result can not be submitted
        // for the stage that has not yet become active.
        if (_stageId > currentStage) {
            revert Errors.StageIdInvalid(currentStage, _stageId);
        }

        _processProposalResult(_proposalId, _stageId, _resultType);

        if (!_tryAdvance) {
            return;
        }

        address sender = _msgSender();

        // If the last stage, caller must have `EXECUTE_PERMISSION_ID`, otherwise `ADVANCE_PERMISSION_ID`.
        bool hasPermission = isAtLastStage(proposal)
            ? hasExecutePermission(sender)
            : hasAdvancePermission(sender);

        // It's important to not revert and silentely succeed even if proposal
        // can not advance due to permission or state, because as sub-body's
        // proposals could contain other actions that should still succeed.
        if (hasPermission && state(_proposalId) == ProposalState.Advanceable) {
            _advanceProposal(_proposalId);
        }
    }

    /// @inheritdoc IProposal
    /// @dev This plugin inherits from `IProposal`, requiring an override for this function.
    function customProposalParamsABI() external pure virtual override returns (string memory) {
        return "(bytes[][] subBodiesCustomProposalParamsABI)";
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(
        bytes4 _interfaceId
    )
        public
        view
        virtual
        override(PluginUUPSUpgradeable, MetadataExtensionUpgradeable, ProposalUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(_interfaceId);
    }

    /// @notice Sets a new trusted forwarder address.
    /// @dev Requires the caller to have the `SET_TRUSTED_FORWARDER_PERMISSION_ID` permission.
    /// @param _forwarder The new trusted forwarder address.
    function setTrustedForwarder(
        address _forwarder
    ) public virtual auth(Permissions.SET_TRUSTED_FORWARDER_PERMISSION_ID) {
        _setTrustedForwarder(_forwarder);
    }

    /// @notice Creates a new proposal in this `StagedProposalProcessor` plugin.
    /// @dev Requires the caller to have the `CREATE_PROPOSAL_PERMISSION_ID` permission.
    ///      Also creates proposals for non-manual bodies in the first stage of the proposal process.
    /// @param _metadata The metadata of the proposal.
    /// @param _actions The actions that will be executed after the proposal passes.
    /// @param _allowFailureMap Allows proposal to succeed even if an action reverts.
    ///     Uses bitmap representation.
    ///     If the bit at index `x` is 1, the tx succeeds even if the action at `x` failed.
    ///     Passing 0 will be treated as atomic execution.
    /// @param _startDate The date at which first stage's bodies' proposals must be started at.
    /// @param _proposalParams The extra abi encoded parameters for each sub-body's createProposal function.
    /// @return proposalId The ID of the proposal.
    function createProposal(
        bytes memory _metadata,
        Action[] memory _actions,
        uint128 _allowFailureMap,
        uint64 _startDate,
        bytes[][] memory _proposalParams
    ) public virtual auth(Permissions.CREATE_PROPOSAL_PERMISSION_ID) returns (uint256 proposalId) {
        // If `currentConfigIndex` is 0, this means the plugin was installed
        // with empty configurations and still hasn't updated stages
        // in which case we should revert.
        uint16 index = getCurrentConfigIndex();
        if (index == 0) {
            revert Errors.StageCountZero();
        }

        proposalId = _createProposalId(keccak256(abi.encode(_actions, _metadata, _msgSender())));

        Proposal storage proposal = proposals[proposalId];

        if (_proposalExists(proposal)) {
            revert Errors.ProposalAlreadyExists(proposalId);
        }

        proposal.allowFailureMap = _allowFailureMap;
        proposal.targetConfig = getTargetConfig();
        proposal.creator = _msgSender();

        // store stage configuration per proposal to avoid
        // changing it while proposal is still open
        proposal.stageConfigIndex = index;

        if(_startDate == 0) {
            _startDate = uint64(block.timestamp);
        } else if (_startDate < uint64(block.timestamp)) {
            revert Errors.StartDateInvalid(_startDate);
        }

        proposal.lastStageTransition = _startDate;

        for (uint256 i = 0; i < _actions.length; ++i) {
            proposal.actions.push(_actions[i]);
        }

        if(_proposalParams.length > type(uint16).max) {
            revert Errors.Uint16MaxSizeExceeded();
        }

        // To reduce the gas costs significantly, don't store the very
        // first stage's params in storage as they only get used in this
        // current tx and will not be needed later on for advancing.
        for (uint256 i = 1; i < _proposalParams.length; ++i) {
            for (uint256 j = 0; j < _proposalParams[i].length; ++j) {
                createProposalParams[proposalId][uint16(i)][j] = _proposalParams[i][j];
            }
        }

        _createBodyProposals(
            proposalId,
            0,
            proposal.lastStageTransition,
            _proposalParams.length > 0 ? _proposalParams[0] : new bytes[](0)
        );

        emit ProposalCreated({
            proposalId: proposalId,
            creator: _msgSender(),
            startDate: proposal.lastStageTransition,
            endDate: 0,
            metadata: _metadata,
            actions: _actions,
            allowFailureMap: _allowFailureMap
        });
    }

    /// @inheritdoc IProposal
    /// @dev Calls a public function that requires the `CREATE_PERMISSION_ID` permission.
    function createProposal(
        bytes memory _metadata,
        Action[] memory _actions,
        uint64 _startDate,
        uint64 /** */,
        bytes memory _data
    ) public virtual override returns (uint256 proposalId) {
        proposalId = createProposal(
            _metadata,
            _actions,
            0,
            _startDate,
            abi.decode(_data, (bytes[][]))
        );
    }

    /// @notice Retrieves the address of the trusted forwarder.
    /// @return The address of the trusted forwarder.
    function getTrustedForwarder() public view virtual returns (address) {
        return trustedForwarder;
    }

    /// @notice Retrieves all information associated with a proposal by its ID.
    /// @param _proposalId The ID of the proposal.
    /// @return The proposal struct
    function getProposal(uint256 _proposalId) public view returns (Proposal memory) {
        return proposals[_proposalId];
    }

    /// @notice Retrieves the result type submitted by a body for a specific proposal and stage.
    /// @param _proposalId The ID of the proposal.
    /// @param _stageId The ID of the stage.
    /// @param _body The address of the sub-body.
    /// @return Returns what resultType the body reported the result with.
    ///     Returns `None (0)` if no result has been provided yet.
    function getBodyResult(
        uint256 _proposalId,
        uint16 _stageId,
        address _body
    ) public view virtual returns (ResultType) {
        return bodyResults[_proposalId][_stageId][_body];
    }

    /// @notice Retrieves the sub proposal id.
    /// @param _proposalId The ID of the proposal.
    /// @param _stageId The ID of the stage.
    /// @param _body The address of the sub-body.
    /// @return Returns TODO: what resultType the body reported the result with.
    ///     Returns `None (0)` if no result has been provided yet.
    function getBodyProposalId(
        uint256 _proposalId,
        uint16 _stageId,
        address _body
    ) public view virtual returns (uint256) {
        return bodyProposalIds[_proposalId][_stageId][_body];
    }

    /// @notice Retrieves the current configuration index at which the current configurations of stages are stored.
    /// @return The index of the current configuration in the `stages` mapping.
    function getCurrentConfigIndex() public view returns (uint16) {
        return currentConfigIndex;
    }

    /// @notice Retrieves the stages stored on the `_index` in the `stages` configuration.
    /// @param _index The index from which to get the stages configuration.
    /// @return The array of `Stage` structs.
    function getStages(uint256 _index) public view virtual returns (Stage[] memory) {
        if (_index > getCurrentConfigIndex() || _index == 0) {
            revert Errors.StageCountZero();
        }

        return stages[_index];
    }

    /// @notice Retrieves the `data` parameter encoded for a sub-body's `createProposal` function in a specific stage.
    ///         Excludes sub-bodies from the first stage, as their parameters are not stored for efficiency.
    /// @param _proposalId The ID of the proposal.
    /// @param _stageId The ID of the stage.
    /// @param _index The index of the body within the stage.
    /// @return The encoded `data` parameter for the specified sub-body's `createProposal` function.
    function getCreateProposalParams(
        uint256 _proposalId,
        uint16 _stageId,
        uint256 _index
    ) public view returns (bytes memory) {
        return createProposalParams[_proposalId][_stageId][_index];
    }

    /// @notice Current state of a proposal.
    /// @param _proposalId The proposal id.
    /// @return The current state of the proposal.
    function state(uint256 _proposalId) public view virtual returns (ProposalState) {
        Proposal storage proposal = proposals[_proposalId];

        if (proposal.executed) {
            return ProposalState.Executed;
        }

        if (proposal.canceled) {
            return ProposalState.Canceled;
        }

        if (!_proposalExists(proposal)) {
            revert Errors.NonexistentProposal(_proposalId);
        }

        Stage storage stage = stages[proposal.stageConfigIndex][proposal.currentStage];

        if (block.timestamp > proposal.lastStageTransition + stage.maxAdvance) {
            return ProposalState.Expired;
        }

        if (proposal.lastStageTransition + stage.minAdvance > block.timestamp) {
            return ProposalState.Active;
        }

        if (stage.vetoThreshold > 0) {
            if (proposal.lastStageTransition + stage.voteDuration > block.timestamp) {
                return ProposalState.Active;
            }
        }

        bool thresholdMet = _thresholdsMet(
            _proposalId,
            proposal.currentStage,
            stage.approvalThreshold,
            stage.vetoThreshold
        );

        if (thresholdMet) {
            return ProposalState.Advanceable;
        }

        return ProposalState.Active;
    }

    /// @notice Advances the specified proposal to the next stage if allowed.
    /// @dev This function checks whether the proposal exists and can advance based on its current state.
    ///      If the proposal is in the final stage, the caller must have the
    ///      `EXECUTE_PERMISSION_ID` permission to execute it.
    /// @param _proposalId The ID of the proposal.
    function advanceProposal(uint256 _proposalId) public virtual {
        Proposal storage proposal = proposals[_proposalId];

        // Reverts if proposal is not Advanceable or is non-existent.
        _validateStateBitmap(_proposalId, _encodeStateBitmap(ProposalState.Advanceable));

        address sender = _msgSender();

        // If the last stage, caller must have `EXECUTE_PERMISSION_ID`, otherwise `ADVANCE_PERMISSION_ID`.
        bool hasPermission = isAtLastStage(proposal)
            ? hasExecutePermission(sender)
            : hasAdvancePermission(sender);

        if (!hasPermission) {
            revert Errors.ProposalExecutionForbidden(_proposalId);
        }

        _advanceProposal(_proposalId);
    }

    /// @notice Cancels the proposal.
    /// @dev The proposal can be canceled only if it's allowed in the stage configuration.
    ///      The caller must have the `CANCEL_PERMISSION_ID` permission to cancel it.
    /// @param _proposalId The id of the proposal.
    function cancel(uint256 _proposalId) public virtual auth(Permissions.CANCEL_PERMISSION_ID) {
        Proposal storage proposal = proposals[_proposalId];

        // Reverts if proposal is not Active, Advanceable or doesn't exist.
        _validateStateBitmap(
            _proposalId,
            _encodeStateBitmap(ProposalState.Active) | _encodeStateBitmap(ProposalState.Advanceable)
        );

        uint16 currentStage = proposal.currentStage;
        Stage storage stage = stages[proposal.stageConfigIndex][currentStage];

        if (!stage.cancelable) {
            revert Errors.ProposalCanNotBeCancelled(currentStage);
        }

        proposal.canceled = true;

        emit ProposalCanceled(_proposalId, currentStage, _msgSender());
    }

    /// @notice Edits the proposal.
    /// @dev The proposal can be editable only if it's allowed in the stage configuration.
    ///      The caller must have the `EDIT_PERMISSION_ID` permission to cancel it
    ///      and stage must be advanceable.
    /// @param _proposalId The id of the proposal.
    /// @param _metadata The metadata of the proposal.
    /// @param _actions The actions that will be executed after the proposal passes.
    function edit(
        uint256 _proposalId,
        bytes calldata _metadata,
        Action[] calldata _actions
    ) public virtual auth(Permissions.EDIT_PERMISSION_ID) {
        Proposal storage proposal = proposals[_proposalId];

        // Reverts if proposal is not Advanceable or is non-existent.
        _validateStateBitmap(_proposalId, _encodeStateBitmap(ProposalState.Advanceable));

        uint16 currentStage = proposal.currentStage;
        Stage storage stage = stages[proposal.stageConfigIndex][currentStage];

        if (!stage.editable) {
            revert Errors.ProposalCanNotBeEditted(_proposalId);
        }

        delete proposal.actions;

        for (uint256 i = 0; i < _actions.length; ++i) {
            proposal.actions.push(_actions[i]);
        }

        emit ProposalEdited(_proposalId, currentStage, _msgSender(), _metadata, _actions);
    }

    /// @inheritdoc IProposal
    /// @dev Requires the `EXECUTE_PERMISSION_ID` permission.
    function execute(uint256 _proposalId) public virtual auth(Permissions.EXECUTE_PERMISSION_ID) {
        Proposal storage proposal = proposals[_proposalId];

        if (!canExecute(_proposalId)) {
            revert Errors.ProposalExecutionForbidden(_proposalId);
        }

        _executeProposal(_proposalId);
    }

    /// @notice Determines whether the specified proposal can be advanced to the next stage.
    /// @dev Reverts if the proposal with the given `_proposalId` does not exist.
    /// @param _proposalId The unique identifier of the proposal to check.
    /// @return Returns `true` if the proposal can be advanced to the next stage, otherwise `false`.
    function canProposalAdvance(uint256 _proposalId) public view virtual returns (bool) {
        Proposal storage proposal = proposals[_proposalId];

        // `state` reverts if proposal is non existent.
        return state(_proposalId) == ProposalState.Advanceable;
    }

    /// @inheritdoc IProposal
    function canExecute(uint256 _proposalId) public view virtual returns (bool) {
        Proposal storage proposal = proposals[_proposalId];

        // 1. `state` reverts if proposal is non existent.
        // 2. Proposal must be on the last stage and advanceable.
        return isAtLastStage(proposal) && state(_proposalId) == ProposalState.Advanceable;
    }

    /// @notice Calculates and retrieves the number of approvals and vetoes for a proposal.
    /// @param _proposalId The proposal ID.
    /// @param _stageId The stage index.
    /// @return approvals The total number of approvals for the proposal.
    /// @return vetoes The total number of vetoes for the proposal.
    function getProposalTally(
        uint256 _proposalId,
        uint16 _stageId
    ) public view virtual returns (uint256 approvals, uint256 vetoes) {
        Proposal storage proposal = proposals[_proposalId];

        if (!_proposalExists(proposal)) {
            revert Errors.NonexistentProposal(_proposalId);
        }

        return _getProposalTally(_proposalId, _stageId);
    }

    /// @inheritdoc IProposal
    function hasSucceeded(uint256 _proposalId) public view virtual override returns (bool) {
        Proposal storage proposal = proposals[_proposalId];

        // 1. `state` reverts if proposal is non existent.
        // 2.  Proposal must be on the last stage and either advanceable or executed.
        return
            isAtLastStage(proposal) &&
            (state(_proposalId) == ProposalState.Advanceable ||
                state(_proposalId) == ProposalState.Executed);
    }

    /// @notice Checks whether the caller has the required permission to execute a proposal at the last stage.
    /// @param _account The address on which the `EXECUTE_PERMISSION_ID` is checked.
    /// @return Returns `true` if the caller has the `EXECUTE_PERMISSION_ID` permission, otherwise `false`.
    function hasExecutePermission(address _account) public view virtual returns (bool) {
        return
            dao().hasPermission(
                address(this),
                _account,
                Permissions.EXECUTE_PERMISSION_ID,
                msg.data
            );
    }

    /// @notice Checks whether the caller has the required permission to advance a proposal.
    /// @param _account The address on which the `ADVANCE_PERMISSION_ID` is checked.
    /// @return Returns `true` if the caller has the `ADVANCE_PERMISSION_ID` permission, otherwise `false`.
    function hasAdvancePermission(address _account) public view virtual returns (bool) {
        return
            dao().hasPermission(
                address(this),
                _account,
                Permissions.ADVANCE_PERMISSION_ID,
                msg.data
            );
    }

    // =========================== INTERNAL/PRIVATE FUNCTIONS =============================

    /// @notice Internal function to update stage configuration.
    /// @dev It's a caller's responsibility not to call this in case `_stages` are empty.
    ///      This function can not be overridden as it's crucial to not allow duplicating bodies
    ///      in the same stage, because proposal creation and report functions depend on this assumption.
    /// @param _stages The stages configuration.
    function _updateStages(Stage[] memory _stages) internal {
        Stage[] storage storedStages = stages[++currentConfigIndex];

        for (uint256 i = 0; i < _stages.length; ++i) {
            Stage storage stage = storedStages.push();
            Body[] memory bodies = _stages[i].bodies;

            uint64 maxAdvance = _stages[i].maxAdvance;
            uint64 minAdvance = _stages[i].minAdvance;
            uint64 voteDuration = _stages[i].voteDuration;
            uint16 approvalThreshold = _stages[i].approvalThreshold;
            uint16 vetoThreshold = _stages[i].vetoThreshold;

            if (minAdvance >= maxAdvance || voteDuration >= maxAdvance) {
                revert Errors.StageDurationsInvalid();
            }

            if (approvalThreshold > bodies.length || vetoThreshold > bodies.length) {
                revert Errors.StageThresholdsInvalid();
            }

            for (uint256 j = 0; j < bodies.length; ++j) {
                // Ensure that body addresses are not duplicated in the same stage.
                for (uint256 k = j + 1; k < bodies.length; ++k) {
                    if (bodies[j].addr == bodies[k].addr) {
                        revert Errors.DuplicateBodyAddress(i, bodies[j].addr);
                    }
                }

                // If the sub-body accepts an automatic creation by SPP,
                // then it must obey `IProposal` interface.
                if (
                    !bodies[j].isManual &&
                    !bodies[j].addr.supportsInterface(type(IProposal).interfaceId)
                ) {
                    revert Errors.InterfaceNotSupported();
                }

                // If not copied manually, requires via-ir compilation
                // pipeline which is still slow.
                stage.bodies.push(bodies[j]);
            }

            stage.maxAdvance = maxAdvance;
            stage.minAdvance = minAdvance;
            stage.voteDuration = voteDuration;
            stage.approvalThreshold = approvalThreshold;
            stage.vetoThreshold = vetoThreshold;
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
            uint256(proposal.allowFailureMap),
            proposal.targetConfig.operation
        );

        emit ProposalExecuted(_proposalId);
    }

    /// @notice Records the result by the caller.
    /// @dev Assumes that bodies are not duplicated in the same stage. See `_updateStages` function.
    /// @param _proposalId The ID of the proposal.
    /// @param _stageId The ID of the stage.
    /// @param _resultType The result type being reported (`Approval` or `Veto`).
    function _processProposalResult(
        uint256 _proposalId,
        uint16 _stageId,
        ResultType _resultType
    ) internal virtual {
        address sender = _msgSender();

        bodyResults[_proposalId][_stageId][sender] = _resultType;
        emit ProposalResultReported(_proposalId, _stageId, sender);
    }

    /// @notice Creates proposals on the non-manual bodies of the `stageId`.
    /// @dev Assumes that bodies are not duplicated in the same stage. See `_updateStages` function.
    /// @param _proposalId The ID of the proposal.
    /// @param _stageId The ID of the stage.
    /// @param _startDate The start date that proposals on sub-bodies will be created with.
    /// @param _stageProposalParams The custom params required for each sub-body to create a proposal.
    function _createBodyProposals(
        uint256 _proposalId,
        uint16 _stageId,
        uint64 _startDate,
        bytes[] memory _stageProposalParams
    ) internal virtual {
        Stage storage stage;

        // avoid stack too deep.
        {
            Proposal storage proposal = proposals[_proposalId];
            stage = stages[proposal.stageConfigIndex][_stageId];
        }

        for (uint256 i = 0; i < stage.bodies.length; ++i) {
            Body storage body = stage.bodies[i];

            // If body proposal creation should be manual, skip it.
            if (body.isManual) continue;

            Action[] memory actions = new Action[](1);

            actions[0] = Action({
                to: address(this),
                value: 0,
                data: abi.encodeCall(
                    this.reportProposalResult,
                    (_proposalId, _stageId, body.resultType, body.tryAdvance)
                )
            });

            // Make sure that the `createProposal` call did not fail because
            // 63/64 of `gasleft()` was insufficient to execute the external call.
            // In specific scenarios, the sender could force-fail `createProposal`
            // where 63/64 is insufficient causing it to fail, but where
            // the remaining 1/64 gas are sufficient to successfully finish the call.
            // See `InsufficientGas` revert below.
            uint256 gasBefore = gasleft();
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, bytes memory data) = body.addr.call(
                abi.encodeCall(
                    IProposal.createProposal,
                    (
                        abi.encode(address(this), _proposalId, _stageId),
                        actions,
                        _startDate,
                        _startDate + stage.voteDuration,
                        _stageProposalParams.length > i ? _stageProposalParams[i] : new bytes(0)
                    )
                )
            );

            uint256 gasAfter = gasleft();

            // NOTE: Handles the edge case where:
            // on success: it could return 0.
            // on failure: default 0 would be used.
            // In order to differentiate, we store `PROPOSAL_WITHOUT_ID` on failure.

            if (!success) {
                if (gasAfter < gasBefore / 64) {
                    revert Errors.InsufficientGas();
                }
            }

            if (success && data.length == 32) {
                uint256 subProposalId = abi.decode(data, (uint256));
                bodyProposalIds[_proposalId][_stageId][body.addr] = subProposalId;

                emit SubProposalCreated(_proposalId, _stageId, body.addr, subProposalId);
            } else {
                // sub-proposal was not created on sub-body, emit
                // the event and try the next sub-body without failing
                // the main(outer) tx.
                bodyProposalIds[_proposalId][_stageId][body.addr] = PROPOSAL_WITHOUT_ID;

                emit SubProposalNotCreated(_proposalId, _stageId, body.addr, data);
            }
        }
    }

    /// @notice Internal function to calculate and retrieve the number of approvals and
    ///         vetoes for a proposal in the `_stageId`.
    /// @dev Assumes that bodies are not duplicated in the same stage. See `_updateStages` function.
    ///      This function ensures that only records from addresses in the stage configuration are used.
    /// @param _proposalId The proposal Id.
    /// @param _stageId The stage id.
    /// @return approvals The number of approvals for the proposal.
    /// @return vetoes The number of vetoes for the proposal.
    function _getProposalTally(
        uint256 _proposalId,
        uint16 _stageId
    ) internal view virtual returns (uint256 approvals, uint256 vetoes) {
        // Cheaper to do 2nd sload than to pass Proposal memory.
        Proposal storage proposal = proposals[_proposalId];
        Stage storage stage = stages[proposal.stageConfigIndex][_stageId];

        uint256 length = stage.bodies.length;

        for (uint256 i = 0; i < length; ++i) {
            Body storage body = stage.bodies[i];

            uint256 bodyProposalId = getBodyProposalId(_proposalId, _stageId, body.addr);
            ResultType resultType = getBodyResult(_proposalId, _stageId, body.addr);

            if (resultType != ResultType.None) {
                // result was already reported
                resultType == ResultType.Approval ? ++approvals : ++vetoes;
            } else if (bodyProposalId != PROPOSAL_WITHOUT_ID && !body.isManual) {
                // result was not reported yet
                // Use low-level call to ensure that outer tx doesn't revert
                // which would cause proposal to never be able to advance.
                (bool success, bytes memory data) = body.addr.staticcall(
                    abi.encodeCall(IProposal.hasSucceeded, (bodyProposalId))
                );

                if (success && data.length == 32) {
                    bool succeeded = abi.decode(data, (bool));
                    if (succeeded) {
                        body.resultType == ResultType.Approval ? ++approvals : ++vetoes;
                    }
                }
            }
        }
    }

    /// @notice Advances a proposal to the next stage or executes it if it is in the final stage.
    /// @dev Assumes the proposal is eligible to advance. If the proposal is not in the final stage,
    ///      it creates proposals for the sub-bodies in the next stage.
    ///      If the proposal is in the final stage, it triggers execution.
    /// @param _proposalId The ID of the proposal.
    function _advanceProposal(uint256 _proposalId) internal virtual {
        Proposal storage _proposal = proposals[_proposalId];
        Stage[] storage _stages = stages[_proposal.stageConfigIndex];

        if (_proposal.currentStage < _stages.length - 1) {
            // is not last stage
            uint16 newStage = ++_proposal.currentStage;
            _proposal.lastStageTransition = uint64(block.timestamp);

            // Grab the next stage's bodies' custom params of `createProposal`.
            bytes[] memory customParams = new bytes[](_stages[newStage].bodies.length);
            for (uint256 i = 0; i < _stages[newStage].bodies.length; i++) {
                customParams[i] = createProposalParams[_proposalId][newStage][i];
            }

            _createBodyProposals(_proposalId, newStage, uint64(block.timestamp), customParams);

            emit ProposalAdvanced(_proposalId, newStage);
        } else {
            _executeProposal(_proposalId);
        }
    }

    /// @notice Sets a new trusted forwarder address and emits the event.
    /// @param _forwarder The trusted forwarder.
    function _setTrustedForwarder(address _forwarder) internal virtual {
        trustedForwarder = _forwarder;

        emit TrustedForwarderUpdated(_forwarder);
    }

    /// @notice Retrieves the original sender address, considering if the call was made through a trusted forwarder.
    /// @dev If the `msg.sender` is the trusted forwarder, extracts the original sender from the calldata.
    /// @return sender The address of the original caller
    ///     or the `msg.sender` if not called through the trusted forwarder.
    function _msgSender() internal view override returns (address) {
        // If sender is a trusted Forwarder, that means
        // it would have appended the original sender in the calldata.
        if (msg.sender == trustedForwarder) {
            address sender;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                // get the last 20 bytes as an address which was appended
                // by the trustedForwarder before calling this function.
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
            return sender;
        } else {
            return msg.sender;
        }
    }

    /// @notice Encodes a `ProposalState` into a `bytes32` representation where each bit enabled
    ///         corresponds the underlying position in the `ProposalState` enum.
    /// @param _proposalState The state of the proposal.
    /// @return The bytes32 bitmap representation of the proposal state.
    function _encodeStateBitmap(ProposalState _proposalState) internal pure returns (bytes32) {
        return bytes32(1 << uint8(_proposalState));
    }

    /// @notice Internal helper function that decides if the stage's thresholds are satisfied.
    /// @param _proposalId The proposal id.
    /// @param _stageId The stage Id.
    /// @param _approvalThreshold The approval threshold of the `_stageId`.
    /// @param _vetoThreshold The veto threshold of the `_stageId`.
    /// @return Returns true if the thresholds are met, otherwise false.
    function _thresholdsMet(
        uint256 _proposalId,
        uint16 _stageId,
        uint256 _approvalThreshold,
        uint256 _vetoThreshold
    ) internal view returns (bool) {
        (uint256 approvals, uint256 vetoes) = _getProposalTally(_proposalId, _stageId);

        if (_vetoThreshold > 0 && vetoes >= _vetoThreshold) {
            return false;
        }

        if (approvals < _approvalThreshold) {
            return false;
        }

        return true;
    }

    /// @notice Checks if proposal is at the last stage or not.
    /// @param _proposal The proposal struct.
    /// @return Returns `true` if proposal is at the last stage, otherwise false.
    function isAtLastStage(Proposal storage _proposal) private view returns (bool) {
        return _proposal.currentStage == stages[_proposal.stageConfigIndex].length - 1;
    }

    /// @notice Checks if proposal exists or not.
    /// @param _proposal The proposal struct.
    /// @return Returns `true` if proposal exists, otherwise false.
    function _proposalExists(Proposal storage _proposal) private view returns (bool) {
        return _proposal.lastStageTransition != 0;
    }

    /// @notice Check that the current state of a proposal matches the requirements described by the
    ///         `allowedStates` bitmap. This bitmap should be built using `_encodeStateBitmap`.
    /// @param _proposalId The proposal id.
    /// @param _allowedStates The allowed states that proposal can be in.
    /// @return Returns the current state of the proposal.
    function _validateStateBitmap(
        uint256 _proposalId,
        bytes32 _allowedStates
    ) private view returns (ProposalState) {
        ProposalState currentState = state(_proposalId);
        if (_encodeStateBitmap(currentState) & _allowedStates == bytes32(0)) {
            revert Errors.UnexpectedProposalState(_proposalId, uint8(currentState), _allowedStates);
        }
        return currentState;
    }

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[44] private __gap;
}
