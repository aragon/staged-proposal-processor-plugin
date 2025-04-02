## Stage Proposal Processor [![Foundry][foundry-badge]][foundry]

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## Audit

### v1.1.0

**Halborn**: [audit report](https://github.com/aragon/osx/tree/main/audits/Halborn_AragonOSx_v1_4_Smart_Contract_Security_Assessment_Report_2025_01_03.pdf)

- Commit ID: [dca24e2db5625d9898c29c9d579873442879dcf3](https://github.com/aragon/staged-proposal-processor-plugin/commit/dca24e2db5625d9898c29c9d579873442879dcf3)
- Started: 2024-11-18
- Finished: 2025-02-13

## ABI and artifacts

Check out the [npm-artifacts folder](./npm-artifacts/README.md) to get the deployed addresses and the contract ABI's.

## Project

The root folder of the repo includes `src` subfolder with the plugin contracts.

The root-level `package.json` file contains global `dev-dependencies` for formatting and linting.

### Targetting ZkSync

If you desire to deploy or run tests against zksync network, make sure to install `foundry-zksync`:

* First, you need a stable foundry-zksync. We recommend the zip extention from foundry zksync's official [release](https://github.com/matter-labs/foundry-zksync/releases/tag/nightly-420660c5243e06af1f12febb1765a9abc9c77461)
* Build the binary by running: `foundryup-zksync --path path-to-foundryup-zksync`
* Run `foundryup-zksync --version nightly-420660c5243e06af1f12febb1765a9abc9c77461` to install this specific version.

### Targetting Peaq and Agung testnet

Edit `foundry.toml` and uncomment the `evm_version` setting:

```toml
evm_version = "london"
```

### Build

```shell
yarn --ignore-scripts
forge build or forge build --zksync
```

### Test

To run the tests against evm based network, run `yarn test`. For zksync, run `yarn test:zksync`. See above how to install foundry zksync toolchain.

If the tests fail with `The application panicked` error on zksync, remove `cache` folder and run `yarn test:zksync` again.

Due to some limitations, fork tests will not be able to run on zksync network.


### Deploy

To deploy the plugin with new plugin repo, you can run: `make deploy` on EVM based networks and `make deploy-zksync` on zksync.

To upgrade the repo with a new version, run `make upgrade-repo` on EVM based networks and `make upgrade-repo-zksync` on zksync.
