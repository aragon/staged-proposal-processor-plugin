// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

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
