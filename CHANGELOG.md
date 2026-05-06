# Staged Proposal Plugin

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.2

### Changed

- Recompiled against an amended `osx-commons` `RuledCondition._evalLogic`. The IF_ELSE starting rule now evaluates with `_where`/`_who` in the same order as the surrounding `_evalRule` call. No setup interface change.

### Added

- SPP-level regression tests for `SPPRuleCondition.isGranted` covering an asymmetric IF_ELSE predicate (success/failure routing and a swapped-args caller path).
- Unit and fork tests for `prepareUpdate`.
- `script/NewVersion.s.sol` now also prints the management DAO multisig `createProposal` calldata wrapping the `createVersion` action — including the pinned `PROPOSAL_METADATA` URI as the proposal metadata — so a multisig member can submit it directly.
- `script/Deploy.s.sol` now publishes `PlaceholderSetup` builds for builds 1..VERSION_BUILD-1 on a fresh repo before publishing the real `SPPSetup` build, keeping on-chain build numbers aligned across networks.
- `PROPOSAL_METADATA` and `PLACEHOLDER_BUILD_METADATA` constants in `PluginSettings.sol`, and `script/new-version-proposal-metadata.json` as the v1.2 proposal metadata source.

## v1.1

### Added

- First version of the plugin.
