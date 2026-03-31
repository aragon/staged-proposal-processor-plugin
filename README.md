## Staged Proposal Processor [![Foundry][foundry-badge]][foundry]

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## Audit

### v1.1.0

**Halborn**: [audit report](https://github.com/aragon/osx/tree/main/audits/Halborn_AragonOSx_v1_4_Smart_Contract_Security_Assessment_Report_2025_01_03.pdf)

- Commit ID: [dca24e2db5625d9898c29c9d579873442879dcf3](https://github.com/aragon/staged-proposal-processor-plugin/commit/dca24e2db5625d9898c29c9d579873442879dcf3)
- Started: 2024-11-18
- Finished: 2025-02-13

## ABI and artifacts

Check out the [npm-artifacts folder](./npm-artifacts/README.md) to get the deployed addresses and the contract ABIs.

## Setup

Requires [Foundry](https://getfoundry.sh/) and [just](https://just.systems).

```shell
just help                  # lists all commands
just init                  # installs submodules and selects mainnet
just switch sepolia        # switch to a different network
```

Copy `.env.example` to `.env` and fill in your secrets. Network configuration (RPC URLs, contract addresses) is managed automatically by `just switch`. For transparent secret management, [vars](https://github.com/vars-cli/vars) is supported out of the box (`just install-vars`).

## Build

```shell
forge build
```

## Test

```shell
just test                  # unit tests
just test-fork             # fork tests (requires RPC_URL)
just validate-upgrade SPPStorageV1 StagedProposalProcessor  # storage layout check
```

## Deploy

```shell
just deploy                # initial deployment (creates plugin repo, publishes v1)
just new-version           # deploy new setup + print DAO proposal calldata
```

Set `SPP_ENS_SUBDOMAIN=spp` in `.env` for production deployments. Omitting it generates a unique name (`spp-<timestamp>`), which is useful for testing.

ZkSync networks are also supported:

```shell
just setup-zksync          # installs forge-zksync alongside standard Foundry
just switch zksync-sepolia
```
