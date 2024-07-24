## Stage Proposal Processor [![Foundry][foundry-badge]][foundry]

[foundry]: https://getfoundry.sh/

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
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

<!-- todo ```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
``` -->

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
