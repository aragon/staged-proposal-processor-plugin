## Stage Proposal Processor [![Foundry][foundry-badge]][foundry]

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## Project

The root folder of the repo includes `src` subfolder with the plugin contracts.

The root-level `package.json` file contains global `dev-dependencies` for formatting and linting.

If you desire to deploy or run tests against zksync network, make sure to install foundry-zksync as below:

* First, you need a stable foundry-zksync. We recommend downloading zip extention from foundry zksync's official [release](https://github.com/matter-labs/foundry-zksync/releases/tag/nightly-420660c5243e06af1f12febb1765a9abc9c77461)
* Next, you need to build the binary by running: `foundryup-zksync --path path-to-foundryup-zksync`
* Run `foundryup-zksync --version nightly-420660c5243e06af1f12febb1765a9abc9c77461` to install this specific version.

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