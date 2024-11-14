// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.8;

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

contract DummySPP is ProposalUpgradeable, MetadataExtensionUpgradeable, PluginUUPSUpgradeable {
    function supportsInterface(
        bytes4 _interfaceId
    )
        public
        view
        virtual
        override(MetadataExtensionUpgradeable, PluginUUPSUpgradeable, ProposalUpgradeable)
        returns (bool)
    {}

    /// @dev inherits from IProposal
    function hasSucceeded(uint256) public pure override returns (bool) {}

    /// @dev inherits from IProposal
    function createProposal(
        bytes memory _metadata,
        Action[] memory _actions,
        uint64 _startDate,
        uint64 /** */,
        bytes memory _data
    ) public virtual override returns (uint256 proposalId) {}

    /// @dev inherits from IProposal
    function customProposalParamsABI() external pure virtual override returns (string memory) {
        return "(bytes[][] subBodiesCustomProposalParamsABI)";
    }

    uint256[50] private __gap;
}
