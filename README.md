## Stage Proposal Processor [![Foundry][foundry-badge]][foundry]

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## Project

The root folder of the repo includes `src` subfolder with the plugin contracts.

The root-level `package.json` file contains global `dev-dependencies` for formatting and linting. After installing the dependencies with

```sh
yarn install
```

## Documentation

The repo uses [Foundry](https://book.getfoundry.sh/)

## Usage

### Build

```shell
yarn
yarn build
```

### Test

To run the tests, run `yarn test`.

In case you want to run the tests against zksync network:

* First, you need a stable foundry-zksync. We recommend downloading zip extention from foundry zksync's official [release](https://github.com/matter-labs/foundry-zksync/releases/tag/nightly-420660c5243e06af1f12febb1765a9abc9c77461)
* Next, you need to build the binary by running: `foundryup-zksync --path path-to-foundryup-zksync`
* Run `foundryup-zksync --version nightly-420660c5243e06af1f12febb1765a9abc9c77461` to install this specific version.
* `yarn test:zksync`

If the tests fail with `The application panicked` error, remove `cache` folder and run `yarn test:zksync` again. Due to some limitations, fork tests will not be able to run on zksync network.
