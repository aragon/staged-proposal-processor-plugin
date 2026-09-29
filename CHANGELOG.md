# Staged Proposal Plugin

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.3

### Fixed

- Sub-proposal creation now reverts the outer tx when any automatic sub-body's `createProposal` fails. Failure is rethrown as `Errors.SubProposalCreationFailed(body, reason)` so the failing body is named in the revert.
- This version also hardens the stage tally against same-transaction flows where a trusted sub-body could reenter. The sub-body's slot in `bodyProposalIds` is now written with a `PROPOSAL_IN_PROGRESS` sentinel before the external `createProposal` call and replaced with the real id after it returns, so a body reentering SPP during its own creation can no longer observe a stale zero and confuse it with a real id. `_getProposalTally` returns a threshold-failing tally (`0` approvals, `type(uint256).max` vetoes) while the marker is set, and rejects the marker as a returned id.

- `reportProposalResult` reverts with `Errors.ResultTypeNotAllowed` when a body of that stage reports a result type other than its configured one or `None` (retracting), so approving bodies can no longer veto and vetoing bodies can no longer approve.
- `script/NewVersion.s.sol` deploys a fresh `StagedProposalProcessor` implementation for the new setup instead of reusing the previous build's (which was correct for v1.2, whose bytecode matched v1.1's).

### Removed

- `Errors.InsufficientGas` and the `gasleft` / 63-64 guard around the sub-body call. The high-level Solidity call now bubbles up any callee revert (including out-of-gas) as a normal revert, and the wrapping `SubProposalCreationFailed` names the failing body — so the manual gas guard no longer adds signal.
- `PROPOSAL_WITHOUT_ID` sentinel and `SubProposalNotCreated` event. There is no partial-creation state to represent anymore.

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
