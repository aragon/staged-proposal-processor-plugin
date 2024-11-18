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
rm -rf lib/openzeppelin-foundry-upgrades
forge install OpenZeppelin/openzeppelin-foundry-upgrades --no-commit
yarn build
```

### Test

```shell
$ yarn test
```
