// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";

/// @dev Apps encode `prepareInstallation` params from `src/build-metadata.json`, while the setup
///      decodes them as `(bytes, SPP.Stage[], RuledCondition.Rule[], IPlugin.TargetConfig)`.
///      Each input must match, field by field, the compiler ABI of the parameter it ends up in,
///      plus a non-empty `description` on every node (Aragon's extension to the ABI JSON).
contract BuildMetadata_SPPSetup_UnitTest is Test {
    string constant INPUTS = ".pluginSetup.prepareInstallation.inputs";

    function test_InstallationInputsMatchTheCompilerAbi() external view {
        string memory metadata = vm.readFile("src/build-metadata.json");
        string memory sppAbi = vm.readFile(
            "out/StagedProposalProcessor.sol/StagedProposalProcessor.json"
        );
        string memory conditionAbi = vm.readFile("out/SPPRuleCondition.sol/SPPRuleCondition.json");

        assertEq(_count(metadata, INPUTS), 4, "input count");
        _assertMatches(metadata, 0, sppAbi, "_pluginMetadata");
        _assertMatches(metadata, 1, sppAbi, "_stages");
        _assertMatches(metadata, 2, conditionAbi, "_rules");
        _assertMatches(metadata, 3, sppAbi, "_targetConfig");
    }

    function test_MismatchCatchesMissingField() external view {
        string memory expected = '{"p":{"name":"s","type":"tuple","internalType":"struct S",'
            '"components":[{"name":"a","type":"bool","internalType":"bool"},'
            '{"name":"b","type":"bool","internalType":"bool"}]}}';
        string memory actual = '{"p":{"name":"s","type":"tuple","internalType":"struct S",'
            '"description":"d",'
            '"components":[{"name":"a","type":"bool","internalType":"bool","description":"d"}]}}';

        assertEq(_mismatch(actual, ".p", expected, ".p", false), ".p.components: count");
    }

    function test_MismatchCatchesWrappedArrayElement() external view {
        // The shape builds 1 to 3 were published with: each `tuple[]` element wrapped in one more tuple.
        string memory expected = '{"p":{"name":"s","type":"tuple[]","internalType":"struct S[]",'
            '"components":[{"name":"a","type":"bool","internalType":"bool"}]}}';
        string memory actual = '{"p":{"name":"s","type":"tuple[]","internalType":"struct S[]",'
            '"description":"d","components":[{"name":"item","type":"tuple","internalType":"struct S",'
            '"description":"d",'
            '"components":[{"name":"a","type":"bool","internalType":"bool","description":"d"}]}]}}';

        assertEq(_mismatch(actual, ".p", expected, ".p", false), ".p.components[0].name");
    }

    function test_MismatchCatchesWrongInternalType() external view {
        string memory expected = '{"p":{"name":"a","type":"uint8","internalType":"enum E"}}';
        string memory actual = '{"p":{"name":"a","type":"uint8","internalType":"uint8",'
            '"description":"d"}}';

        assertEq(_mismatch(actual, ".p", expected, ".p", false), ".p.internalType");
    }

    function test_MismatchCatchesMissingOrEmptyDescription() external view {
        string memory expected = '{"p":{"name":"a","type":"uint8","internalType":"uint8"}}';

        assertEq(
            _mismatch('{"p":{"name":"a","type":"uint8","internalType":"uint8"}}', ".p", expected, ".p", false),
            ".p.description"
        );
        assertEq(
            _mismatch(
                '{"p":{"name":"a","type":"uint8","internalType":"uint8","description":""}}',
                ".p",
                expected,
                ".p",
                false
            ),
            ".p.description"
        );
    }

    function test_MismatchAcceptsAMatch() external view {
        string memory expected = '{"p":{"name":"a","type":"uint8","internalType":"uint8"}}';
        string memory actual = '{"p":{"name":"b","type":"uint8","internalType":"uint8",'
            '"description":"d"}}';

        // Top-level names are free: they don't take part in the encoding.
        assertEq(_mismatch(actual, ".p", expected, ".p", false), "");
        assertEq(_mismatch(actual, ".p", expected, ".p", true), ".p.name");
    }

    function _assertMatches(
        string memory _metadata,
        uint256 _index,
        string memory _abi,
        string memory _paramName
    ) private view {
        string memory metaPath = _at(INPUTS, _index);
        string memory abiPath = _param(_abi, _initializeInputs(_abi), _paramName);
        assertEq(_mismatch(_metadata, metaPath, _abi, abiPath, false), "", _paramName);
    }

    /// @dev Returns the path of the first difference, or "" when `_actual` matches `_expected`.
    ///      Top-level names are only compared when `_compareName` is set; nested names always are.
    function _mismatch(
        string memory _actual,
        string memory _actualPath,
        string memory _expected,
        string memory _expectedPath,
        bool _compareName
    ) private view returns (string memory) {
        string[3] memory keys = [".name", ".type", ".internalType"];
        for (uint256 i = _compareName ? 0 : 1; i < keys.length; i++) {
            if (
                keccak256(bytes(_str(_actual, string.concat(_actualPath, keys[i])))) !=
                keccak256(bytes(_str(_expected, string.concat(_expectedPath, keys[i]))))
            ) {
                return string.concat(_actualPath, keys[i]);
            }
        }

        if (bytes(_str(_actual, string.concat(_actualPath, ".description"))).length == 0) {
            return string.concat(_actualPath, ".description");
        }

        string memory actualComponents = string.concat(_actualPath, ".components");
        string memory expectedComponents = string.concat(_expectedPath, ".components");
        uint256 count = _count(_expected, expectedComponents);
        if (_count(_actual, actualComponents) != count) {
            return string.concat(actualComponents, ": count");
        }
        for (uint256 i; i < count; i++) {
            string memory diff = _mismatch(
                _actual,
                _at(actualComponents, i),
                _expected,
                _at(expectedComponents, i),
                true
            );
            if (bytes(diff).length != 0) return diff;
        }
        return "";
    }

    function _initializeInputs(string memory _abi) private view returns (string memory) {
        uint256 count = _count(_abi, ".abi");
        for (uint256 i; i < count; i++) {
            if (keccak256(bytes(_str(_abi, string.concat(_at(".abi", i), ".name")))) == keccak256("initialize")) {
                return string.concat(_at(".abi", i), ".inputs");
            }
        }
        revert("no initialize in the ABI");
    }

    function _param(
        string memory _abi,
        string memory _inputs,
        string memory _name
    ) private view returns (string memory) {
        uint256 count = _count(_abi, _inputs);
        for (uint256 i; i < count; i++) {
            if (keccak256(bytes(_str(_abi, string.concat(_at(_inputs, i), ".name")))) == keccak256(bytes(_name))) {
                return _at(_inputs, i);
            }
        }
        revert(string.concat("no ", _name, " in initialize"));
    }

    function _str(string memory _json, string memory _key) private view returns (string memory) {
        return vm.keyExistsJson(_json, _key) ? vm.parseJsonString(_json, _key) : "";
    }

    function _count(string memory _json, string memory _path) private view returns (uint256 count) {
        while (vm.keyExistsJson(_json, _at(_path, count))) count++;
    }

    function _at(string memory _path, uint256 _index) private pure returns (string memory) {
        return string.concat(_path, "[", vm.toString(_index), "]");
    }
}
