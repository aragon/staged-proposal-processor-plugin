// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.8;
import "forge-std/console.sol";

contract Target {
    uint public val;
    address public ctrAddress;

    function setValue(uint256 _val) public {
        val = _val;
    }

    function setAddress(address _ctrAddress) public {
        ctrAddress = _ctrAddress;
    }
}
