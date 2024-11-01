// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

import {Errors} from "./libraries/Errors.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {
    PluginUUPSUpgradeable
} from "@aragon/osx-commons-contracts/src/plugin/PluginUUPSUpgradeable.sol";
import {
    IProposal
} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {
    MetadataExtensionUpgradeable
} from "@aragon/osx-commons-contracts/src/utils/metadata/MetadataExtensionUpgradeable.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {
    ProposalUpgradeable
} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/ProposalUpgradeable.sol";

contract StagedProposalProcessor is
    ProposalUpgradeable,
    MetadataExtensionUpgradeable,
    PluginUUPSUpgradeable
{
    using ERC165Checker for address;

    /// @notice The ID of the permission required to call the `createProposal` function.
    bytes32 public constant CREATE_PROPOSAL_PERMISSION_ID = keccak256("CREATE_PROPOSAL_PERMISSION");

    /// @notice The ID of the permission required to call the `setTrustedForwarder` function.
    bytes32 public constant SET_TRUSTED_FORWARDER_PERMISSION_ID =
        keccak256("SET_TRUSTED_FORWARDER_PERMISSION");

    /// @notice The ID of the permission required to call the `updateStages` function.
    bytes32 public constant UPDATE_STAGES_PERMISSION_ID = keccak256("UPDATE_STAGES_PERMISSION");

    /// @notice The ID of the permission required to call the `execute` function.
    bytes32 public constant EXECUTE_PROPOSAL_PERMISSION_ID =
        keccak256("EXECUTE_PROPOSAL_PERMISSION");

    /// @notice Used to distinguish proposals where the SPP was not able to create a proposal on a sub-body.
    uint256 private constant PROPOSAL_WITHOUT_ID = type(uint256).max;

    /// @notice The different types that bodies can are registered with.
    /// @param None Used to check if the body reported the result or not.
    /// @param Approval Used to allow a body to report approval result.
    /// @param Veto Used to allow a body to report veto result.
    enum ResultType {
        None,
        Approval,
        Veto
    }

    /// @notice A container for Body-related information.
    /// @param addr The address responsible for reporting results. For automatic bodies, it is also where the SPP creates proposals.
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
    /// @param voteDuration The time to give vetoing bodies to make decisions in optimistic stage. Note that this also is used as an endDate time for bodies, see `_createBodyProposals`.
    /// @param approvalThreshold The number of bodies that are required to pass to advance the proposal.
    /// @param vetoThreshold If this number of bodies veto, the proposal can never advance even if `approvalThreshold` is satisfied.
    struct Stage {
        Body[] bodies;
        uint64 maxAdvance;
        uint64 minAdvance;
        uint64 voteDuration;
        uint16 approvalThreshold;
        uint16 vetoThreshold;
    }

    /// @notice A container for proposal-related information.
    /// @param allowFailureMap A bitmap allowing the proposal to succeed, even if individual actions might revert.
    /// @param lastStageTransition The timestamp at which proposal's current stage has started.
    /// @param currentStage Which stage the proposal is at.
    /// @param stageConfigIndex The stage configuration that this proposal uses.
    /// @param executed Whether the proposal is executed or not.
    /// @param actions The actions to be executed when the proposal passes.
    /// @param targetConfig The target to which this contract will pass actions with an operation type.
    struct Proposal {
        uint128 allowFailureMap;
        uint64 lastStageTransition;
        uint16 currentStage;
        uint16 stageConfigIndex;
        bool executed;
        Action[] actions;
        TargetConfig targetConfig;
    }

    // proposalId => stageId => body => subProposalId
    mapping(uint256 => mapping(uint256 => mapping(address => uint256))) public bodyProposalIds;

    // proposalId => stageId => body => resultType
    mapping(uint256 => mapping(uint16 => mapping(address => ResultType))) private bodyResults;

    // proposalId => stageId => body index => custom proposal params data.
    mapping(uint256 => mapping(uint16 => mapping(uint256 => bytes))) private createProposalParams;

    /// @notice A mapping between proposal IDs and proposal information.
    mapping(uint256 => Proposal) private proposals;

    /// @notice A mapping between stage config index and actual stage configuration on that index.
    mapping(uint256 => Stage[]) private stages;

    uint16 private currentConfigIndex; // Index from `stages` storage mapping
    address private trustedForwarder;

    /// @notice Emitted when the proposal is advanced to the next stage.
    /// @param proposalId The proposal id.
    /// @param stageId The stage id.
    event ProposalAdvanced(uint256 indexed proposalId, uint256 indexed stageId);

    /// @notice Emitted when a body reports results by calling `reportProposalResult`.
    /// @param proposalId The proposal id.
    /// @param stageId The stage id.
    /// @param body The sender that reported the result.
    event ProposalResultReported(
        uint256 indexed proposalId,
        uint16 indexed stageId,
        address indexed body
    );

    /// @notice Emitted when the stage configuration is updated.
    /// @param stages The stage configuration.
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
    function setTrustedForwarder(
        address _forwarder
    ) public virtual auth(SET_TRUSTED_FORWARDER_PERMISSION_ID) {
        _setTrustedForwarder(_forwarder);
    }

    /// @return Returns the address of the trusted forwarder.
    function getTrustedForwarder() public view virtual returns (address) {
        return trustedForwarder;
    }

    /// @notice Creates a proposal only on non-manual bodies of the first stage.
    /// @param _metadata The metadata of the proposal.
    /// @param _actions The actions that will be executed after the proposal passes.
    /// @param _allowFailureMap Allows proposal to succeed even if an action reverts.
    /// Uses bitmap representation.
    /// If the bit at index `x` is 1, the tx succeeds even if the action at `x` failed.
    /// Passing 0 will be treated as atomic execution.
    /// @param _startDate The date at which first stage's bodies' proposals must be started at.
    /// @param _proposalParams The extra abi encoded parameters for each sub-body's createProposal function.
    /// @return proposalId The ID of the proposal.
    function createProposal(
        bytes memory _metadata,
        Action[] memory _actions,
        uint128 _allowFailureMap,
        uint64 _startDate,
        bytes[][] memory _proposalParams
    ) public virtual auth(CREATE_PROPOSAL_PERMISSION_ID) returns (uint256 proposalId) {
        // If `currentConfigIndex` is 0, this means the plugin was installed
        // with empty configurations and still hasn't updated stages
        // in which case we should revert.
        uint16 index = getCurrentConfigIndex();
        if (index == 0) {
            revert Errors.StageCountZero();
        }

        proposalId = _createProposalId(keccak256(abi.encode(_actions, _metadata)));

        Proposal storage proposal = proposals[proposalId];

        if (proposal.lastStageTransition != 0) {
            revert Errors.ProposalAlreadyExists(proposalId);
        }

        proposal.allowFailureMap = _allowFailureMap;
        proposal.targetConfig = getTargetConfig();

        // store stage configuration per proposal to avoid
        // changing it while proposal is still open
        proposal.stageConfigIndex = index;

        // If the start date is in the past, revert.
        if (_startDate < uint64(block.timestamp)) {
            revert Errors.StartDateInvalid(_startDate);
        }

        proposal.lastStageTransition = _startDate == 0 ? uint64(block.timestamp) : _startDate;

        for (uint256 i = 0; i < _actions.length; ) {
            proposal.actions.push(_actions[i]);

            unchecked {
                ++i;
            }
        }

        // To reduce the gas costs significantly, don't store the very
        // first stage's params in storage as they only get used in this
        // current tx and will not be needed later on for advancing.
        for (uint256 i = 1; i < _proposalParams.length; i++) {
            for (uint256 j = 0; j < _proposalParams[i].length; j++)
                createProposalParams[proposalId][uint16(i)][j] = _proposalParams[i][j];
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

    /// @inheritdoc IProposal
    /// @dev Since SPP is also IProposal, it's required to override.
    function customProposalParamsABI() external pure virtual override returns (string memory) {
        return "(bytes[][] subBodiesCustomProposalParamsABI)";
    }

    /// @notice Returns all information for a proposal by its ID.
    /// @param _proposalId The ID of the proposal.
    /// @return Proposal The proposal struct
    function getProposal(uint256 _proposalId) public view returns (Proposal memory) {
        return proposals[_proposalId];
    }

    /// @notice Returns whether the body has submitted its result or not.
    /// @param _proposalId The ID of the proposal.
    /// @param _stageId Stage number in the stages array.
    /// @return ResultType Returns what resultType the body reported the result with. 0 if no result provided yet.
    function getBodyResult(
        uint256 _proposalId,
        uint16 _stageId,
        address _body
    ) public view virtual returns (ResultType) {
        return bodyResults[_proposalId][_stageId][_body];
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
    /// @param _stageId The ID of the stage. It must not be more than current stage.
    /// @param _resultType Whether to include report as a veto or approval.
    /// @param _tryAdvance If true, tries to advance the proposal if it can be advanced.
    function reportProposalResult(
        uint256 _proposalId,
        uint16 _stageId,
        ResultType _resultType,
        bool _tryAdvance
    ) external virtual {
        Proposal storage proposal = proposals[_proposalId];

        if (proposal.lastStageTransition == 0) {
            revert Errors.ProposalNotExists(_proposalId);
        }

        uint16 currentStage = proposal.currentStage;

        // Ensure that result can not be submitted
        // for the stage that has not yet become active.
        if (_stageId > currentStage) {
            revert Errors.StageIdInvalid(currentStage, _stageId);
        }

        _processProposalResult(_proposalId, _stageId, _resultType);

        if (_tryAdvance && _canProposalAdvance(_proposalId)) {
            // If it's the last stage, only advance(i.e execute) if 
            // caller has permission. Note that we don't revert in 
            // this case to still allow the records being reported.
            if (
                proposal.currentStage == stages[proposal.stageConfigIndex].length - 1 &&
                hasExecutePermission()
            ) {
                _advanceProposal(_proposalId);
            }
        }
    }

    /// @notice Advances the proposal to the next stage in case it's allowed.
    /// @param _proposalId The ID of the proposal.
    function advanceProposal(uint256 _proposalId) public virtual {
        Proposal storage proposal = proposals[_proposalId];

        if (proposal.lastStageTransition == 0) {
            revert Errors.ProposalNotExists(_proposalId);
        }

        if (!_canProposalAdvance(_proposalId)) {
            revert Errors.ProposalCannotAdvance(_proposalId);
        }

        // If it's last stage, make sure that caller 
        // has permission to execute, otherwise revert.
        if (
            proposal.currentStage == stages[proposal.stageConfigIndex].length - 1 &&
            !hasExecutePermission()
        ) {
            revert Errors.ProposalExecutionForbidden(_proposalId);
        }

        _advanceProposal(_proposalId);
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

    /// @notice Checks if caller has a permission to execute a proposal if it's on the last stage.
    /// @return Returns true if the caller has permission to execute.
    function hasExecutePermission() public view returns (bool) {
        return
            dao().hasPermission(
                address(this),
                _msgSender(),
                EXECUTE_PROPOSAL_PERMISSION_ID,
                msg.data
            );
    }

    /// @notice Useful function for UI to get any sub-bodies'(not including first stage's sub-bodies) `createProposal`'s `data` param.
    /// @param _proposalId The ID of the proposal.
    /// @param _proposalId The ID of the stage.
    /// @param _index The index of a body in an array.
    /// @return The sub-body's createProposal's `data` parameter encoded.
    function getCreateProposalParams(
        uint256 _proposalId,
        uint16 _stageId,
        uint256 _index
    ) public view returns (bytes memory) {
        return createProposalParams[_proposalId][_stageId][_index];
    }

    // =========================== INTERNAL/PRIVATE FUNCTIONS =============================

    /// @notice Internal function to update stage configuration.
    /// @dev It's a caller's responsibility not to call this in case `_stages` are empty.
    /// This function can not be overridden as it's crucial to not allow duplicating bodies
    //  in the same stage, because proposal creation and report functions depend on this assumption.
    /// @param _stages The stages configuration.
    function _updateStages(Stage[] memory _stages) internal {
        Stage[] storage storedStages = stages[++currentConfigIndex];

        for (uint256 i = 0; i < _stages.length; ) {
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

            for (uint256 j = 0; j < bodies.length; ) {
                // Ensure that body addresses are not duplicated in the same stage.
                for (uint256 k = j + 1; k < bodies.length; ) {
                    if (bodies[j].addr == bodies[k].addr) {
                        revert Errors.DuplicateBodyAddress(i, bodies[j].addr);
                    }

                    unchecked {
                        ++k;
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

                unchecked {
                    ++j;
                }
            }

            stage.maxAdvance = maxAdvance;
            stage.minAdvance = minAdvance;
            stage.voteDuration = voteDuration;
            stage.approvalThreshold = approvalThreshold;
            stage.vetoThreshold = vetoThreshold;

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
            uint128(proposal.allowFailureMap),
            proposal.targetConfig.operation
        );

        emit ProposalExecuted(_proposalId);
    }

    /// @notice Records the result by the caller.
    /// @dev Assumes that bodies are not duplicated in the same stage. See `_updateStages` function.
    /// @dev Results can be recorded at any time, but only once per body.
    /// @param _proposalId The ID of the proposal.
    /// @param _proposalId The ID of the stage.
    /// @param _resultType which method to use when reporting(veto or approval)
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
    /// @param _stageId stage number of the stages configuration array.
    /// @param _startDate The start date that proposals on sub-bodies will be created with.
    /// @param _stageProposalParams The custom params required for each sub-body.
    function _createBodyProposals(
        uint256 _proposalId,
        uint16 _stageId,
        uint64 _startDate,
        bytes[] memory _stageProposalParams
    ) internal virtual {
        Proposal storage proposal = proposals[_proposalId];

        Stage storage stage = stages[proposal.stageConfigIndex][_stageId];

        for (uint256 i = 0; i < stage.bodies.length; i++) {
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
            uint256 gasBefore = gasleft();

            try
                IProposal(stage.bodies[i].addr).createProposal(
                    abi.encode(address(this), _proposalId, _stageId),
                    actions,
                    _startDate,
                    _startDate + stage.voteDuration,
                    _stageProposalParams.length > i ? _stageProposalParams[i] : new bytes(0)
                )
            returns (uint256 bodyProposalId) {
                bodyProposalIds[_proposalId][_stageId][stage.bodies[i].addr] = bodyProposalId;
            } catch {
                // Handles the edge case where:
                // on success: it could return 0.
                // on failure: default 0 would be used.
                // In order to differentiate, we store `uint256.max` on failure.

                uint256 gasAfter = gasleft();

                if (gasAfter < gasBefore / 64) {
                    revert Errors.InsufficientGas();
                }

                bodyProposalIds[_proposalId][_stageId][stage.bodies[i].addr] = PROPOSAL_WITHOUT_ID;
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

        // Allow `voteDuration` to pass for bodies to have veto possibility.
        if (stage.vetoThreshold > 0) {
            if (proposal.lastStageTransition + stage.voteDuration > block.timestamp) {
                return false;
            }
        }

        (uint256 approvals, uint256 vetoes) = _getProposalTally(_proposalId);

        if (stage.vetoThreshold > 0 && vetoes >= stage.vetoThreshold) {
            return false;
        }

        if (approvals < stage.approvalThreshold) {
            return false;
        }

        return true;
    }

    /// @notice Internal function to calculate the votes and vetoes for a proposal.
    /// @dev Assumes that bodies are not duplicated in the same stage. See `_updateStages` function.
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

        for (uint256 i = 0; i < stage.bodies.length; ) {
            Body storage body = stage.bodies[i];

            uint256 bodyProposalId = bodyProposalIds[_proposalId][currentStage][body.addr];

            ResultType resultType = bodyResults[_proposalId][currentStage][body.addr];

            if (resultType != ResultType.None) {
                // result was already reported
                resultType == ResultType.Approval ? ++votes : ++vetoes;
            } else if (bodyProposalId != PROPOSAL_WITHOUT_ID && !body.isManual) {
                // result was not reported yet
                if (IProposal(stage.bodies[i].addr).canExecute(bodyProposalId)) {
                    body.resultType == ResultType.Approval ? ++votes : ++vetoes;
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Internal function to advance the proposal. It executes if it's the last stage.
    /// @dev Note that it assumes the proposal can advance. 
    /// @param _proposalId The proposal Id.
    function _advanceProposal(uint256 _proposalId) internal virtual {
        Proposal storage _proposal = proposals[_proposalId];
        Stage[] storage _stages = stages[_proposal.stageConfigIndex];

        _proposal.lastStageTransition = uint64(block.timestamp);

        if (_proposal.currentStage < _stages.length - 1) {
            // is not last stage
            uint16 newStage = ++_proposal.currentStage;

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

    function _msgSender() internal view override returns (address) {
        // If sender is a trusted Forwarder, that means
        // it would have appended the original sender in the calldata.
        if (msg.sender == trustedForwarder) {
            address sender;
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

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps

    /// TODO: adjust the reserved gap size
    uint256[43] private __gap;
}
