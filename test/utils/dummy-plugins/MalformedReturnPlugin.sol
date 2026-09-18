// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract MalformedReturnPlugin is IERC165 {
    /// @dev The number of bytes `createProposal` returns. Anything other than 32 is malformed.
    uint256 public returnDataLength;

    constructor(uint256 _returnDataLength) {
        returnDataLength = _returnDataLength;
    }

    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return _interfaceId == type(IProposal).interfaceId || _interfaceId == type(IERC165).interfaceId;
    }

    // solhint-disable-next-line no-complex-fallback
    fallback() external {
        uint256 length = returnDataLength;
        assembly {
            return(0, length)
        }
    }

    function hasSucceeded(uint256) public pure returns (bool) {
        return true;
    }

    function proposalCount() external pure returns (uint256) {
        return 0;
    }
}
