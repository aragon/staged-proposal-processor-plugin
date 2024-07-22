// // SPDX-License-Identifier: AGPL-3.0-or-later

// pragma solidity 0.8.17;

// import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// import {Vm} from "forge-std/Vm.sol";

// error LogNotFound(bytes32 topic);

// // HELPERS
// function findLog(Vm.Log[] memory logs, bytes32 topic) pure returns (Vm.Log memory) {
//     for (uint256 i = 0; i < logs.length; i++) {
//         if (logs[i].topics[0] == topic) {
//             return logs[i];
//         }
//     }
//     revert LogNotFound(topic);
// }

// function createProxyAndCall(address _logic, bytes memory _data) returns (address) {
//     return address(new ERC1967Proxy(_logic, _data));
// }

// // function createStages(
// //     uint256 stagesCount,
// //     address plugin,
// //     bool isManual,
// //     bool isOptimistic,
// //     uint64 maxDuration,
// //     uint64 minDuration,
// //     uint64 stageDuration
// // ) pure returns (MultiBody.Stage[] memory stages) {
// //     MultiBody.Plugin[] memory plugins = new MultiBody.Plugin[](1);
// //     plugins[0] = MultiBody.Plugin(plugin, isManual, plugin);

// //     stages = new MultiBody.Stage[](stagesCount);
// //     for (uint256 i; i < stagesCount; ++i) {
// //         stages[i] = MultiBody.Stage(
// //             plugins,
// //             maxDuration,
// //             minDuration,
// //             stageDuration,
// //             1,
// //             isOptimistic
// //         );
// //     }
// // }
