# Staged Proposal Processor plugin artifacts

This package contains the ABI definitions of the Staged Proposal Processor (SPP) plugin, as well as the address of its `PluginRepo` deployed on each network.

Install it with:

```sh
bun add @aragon/staged-proposal-processor-plugin-artifacts
# or: pnpm add @aragon/staged-proposal-processor-plugin-artifacts
```

## Usage

```typescript
// ABI definitions
import {
    StagedProposalProcessorABI,
    StagedProposalProcessorSetupABI,
    SPPRuleConditionABI
} from "@aragon/staged-proposal-processor-plugin-artifacts";

console.log("SPP ABI", StagedProposalProcessorABI);

// Plugin Repository addresses per-network
import { addresses } from "@aragon/staged-proposal-processor-plugin-artifacts";

console.log(addresses.pluginRepo.mainnet);
```

You can also open [addresses.json](./src/addresses.json) directly.

## Development

This package is built with [`just`](https://github.com/casey/just) and [`bun`](https://bun.sh).

### Refresh ABIs

```sh
just abi   # regenerate src/abi.ts from forge build artifacts at the repo root
```

`src/abi.ts` is populated by `bash prepare-abi.sh`, which runs `forge build` at the repo root and emits one `export const <Contract>ABI = [...] as const` per `src/` contract with a non-empty ABI. Bytecode is not emitted — use the ABI const + the address from `addresses.json` directly.

### Sync addresses

`src/addresses.json` is the source of truth for the SPP `PluginRepo` address on each chain. The sync recipe overlays the latest deployment artifacts from a peer-directory clone of `aragon/protocol-factory` onto the existing JSON without dropping any networks already listed:

```sh
just sync-addresses   # ../../protocol-factory/artifacts/addresses-<network>-<ts>.json → src/addresses.json
```

If a network has multiple `addresses-<network>-<ts>.json` files, the highest timestamp wins. Networks not present in `protocol-factory/artifacts/` are preserved. Same-network entries are overwritten with the freshest address. Output keys are sorted alphabetically.

If you don't have `protocol-factory` checked out, edit `src/addresses.json` directly in your PR.

### Build

```sh
just build
```

Regenerates `src/abi.ts`, installs dependencies via `bun`, then runs `tsc` to produce `dist/`.

### Releasing

Releases are PR-driven. Tag creation and NPM publishing are handled exclusively by CI — there is no manual release flow.

1. Open a PR that bumps `version` in [`package.json`](./package.json).
2. Update [`CHANGELOG.md`](./CHANGELOG.md) in the same PR if relevant. If addresses changed, patch [`src/addresses.json`](./src/addresses.json). If contracts changed, regenerate `src/abi.ts` (`just abi`).
3. After review and merge to `main` or any `release-v*` branch, [`.github/workflows/release.yml`](../.github/workflows/release.yml) detects the new version, creates the `vX.Y.Z` tag, and runs `bun publish`.

If the merged version already has a tag (e.g. an unrelated edit to `package.json`), the workflow exits cleanly without releasing.

## Documentation

[Aragon's developer portal](https://docs.aragon.org).

## Contributing

See [`CONTRIBUTIONS.md`](../CONTRIBUTIONS.md) in the main repository.

## Security

If you believe you've found a security issue, please email **sirt@aragon.org**. Don't use the public issue tracker.
