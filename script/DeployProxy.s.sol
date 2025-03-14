// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {console} from "forge-std/console.sol";
import {BaseScript} from "./Base.sol";

import {SPPRuleCondition} from "../src/utils/SPPRuleCondition.sol";
import {
    RuledCondition
} from "@aragon/osx-commons-contracts/src/permission/condition/extensions/RuledCondition.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployProxy is BaseScript {
    function run() external {
        _printAragonArt();

        vm.startBroadcast(deployerPrivateKey);

        RuledCondition.Rule[] memory rules = new RuledCondition.Rule[](0);
        SPPRuleCondition impl = new SPPRuleCondition(address(0), rules);
        address proxy = createProxyAndCall(
            address(impl),
            abi.encodeCall(SPPRuleCondition.initialize, (address(0), rules))
        );

        console.log("- Implementation:", address(impl));
        console.log("- Proxy:", proxy);

        vm.stopBroadcast();
    }

    function createProxyAndCall(address _logic, bytes memory _data) private returns (address) {
        return address(new ERC1967Proxy(_logic, _data));
    }
}

contract DeployEmptyProxy is BaseScript {
    function run() external {
        _printAragonArt();

        vm.startBroadcast(deployerPrivateKey);

        EmptyContract impl = new EmptyContract();
        address proxy = createProxyAndCall(
            address(impl),
            abi.encodeCall(EmptyContract.dummyFunc, ())
        );

        console.log("- Implementation:", address(impl));
        console.log("- Proxy:", proxy);

        vm.stopBroadcast();
    }

    function createProxyAndCall(address _logic, bytes memory _data) private returns (address) {
        return address(new ERC1967Proxy(_logic, _data));
    }
}

contract EmptyContract {
    uint value;

    function dummyFunc() public {
        value = 1;
    }
}
