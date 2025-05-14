# Staged Proposal Processor plugin artifacts

This package contains the ABI of the Staged Proposal Processor plugin for OSx, as well as the address of its plugin repository on each supported network. Install it with:

```sh
yarn add @aragon/staged-proposal-processor-plugin-artifacts
```

## Usage

```typescript
// ABI definitions
import {
    StagedProposalProcessor,
    StagedProposalProcessorSetup,
    StagedProposalProcessorSetupZkSync
} from "@aragon/staged-proposal-processor-plugin-artifacts";

// Plugin Repository addresses per-network
import { addresses } from "@aragon/staged-proposal-processor-plugin-artifacts";
```

You can also open [addresses.json](https://github.com/aragon/staged-proposal-processor-plugin/blob/main/npm-artifacts/src/addresses.json) directly.

## Development

### Building the package

Install the dependencies and generate the local ABI definitions.

```sh
yarn --ignore-scripts
yarn build
```

The `build` script will:
1. Move to `src`.
2. Install its dependencies.
3. Compile the contracts using Hardhat.
4. Generate their ABI.
5. Extract their ABI and embed it into on `npm/src/abi.ts`.

### Syncing the deployment addresses

Clone [OSx Commons](https://github.com/aragon/osx-commons) in a folder next to this repo.

```sh
# cd npm-artifacts
yarn sync-from-commons
```

### Publishing

- Access the repo's GitHub Actions panel
- Click on "Publish Artifacts"
- Select the corresponding `release-v*` branch as the source

This action will:
- Create a git tag like `v1.2`, following [package.json](./package.json)'s version field
- Publish the package to NPM

## Documentation

You can find all documentation regarding how to use this plugin in [Aragon's documentation here](https://docs.aragon.org/spp/1.x/index.html).

## Contributing

If you like what we're doing and would love to support, please review our `CONTRIBUTING_GUIDE.md` [here](https://github.com/aragon/staged-proposal-processor-plugin/blob/main/CONTRIBUTIONS.md). We'd love to build with you.

## Security

If you believe you've found a security issue, we encourage you to notify us. We welcome working with you to resolve the issue promptly.

Security Contact Email: sirt@aragon.org

Please do not use the issue tracker for security issues.
