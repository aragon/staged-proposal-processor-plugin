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
just check-upgrade SPPStorageV1 StagedProposalProcessor    # storage layout compatibility check
```

## Deploy

```shell
just deploy                # initial deployment (creates plugin repo, publishes v1)
just new-version           # deploy new setup + print management DAO multisig proposal calldata
```

Set `SPP_ENS_SUBDOMAIN=spp` in `.env` for production deployments. Omitting it generates a unique name (`spp-<timestamp>`), which is useful for testing.

### Publishing a new build

1. Bump `VERSION_BUILD` in `src/utils/PluginSettings.sol`.
2. Edit `src/build-metadata.json` and `script/new-version-proposal-metadata.json` for this build (and `src/release-metadata.json` if shipping a new release).
3. Pin and update the matching constants in `PluginSettings.sol`:
   ```shell
   just ipfs-pin src/build-metadata.json                   # → BUILD_METADATA
   just ipfs-pin script/new-version-proposal-metadata.json # → PROPOSAL_METADATA
   just ipfs-pin src/release-metadata.json                 # → RELEASE_METADATA (only on a new release)
   ```
4. Run `just new-version`. The script deploys the new `SPPSetup` and prints two calldata blobs:
   - the inner `createVersion` action (`to = SPP_PLUGIN_REPO_ADDRESS`), and
   - the outer management DAO multisig `createProposal` call (`to = MANAGEMENT_DAO_MULTISIG_ADDRESS`) including the pinned `PROPOSAL_METADATA` URI — submit it from any listed multisig member to publish the version.

On a brand-new network, `just deploy` automatically publishes `PlaceholderSetup` builds for any build numbers below `VERSION_BUILD` before publishing the real one, so build numbers stay aligned with networks where prior builds shipped.

### Upgrading existing installations

Publishing a new build does not upgrade installed plugins. Each DAO running an older build needs a proposal that calls `psp.applyUpdate(...)`. 

Version 1.2 is published with the same `IMPLEMENTATION` as 1.1 (bytecode is identical), so `applyUpdate` skips the proxy upgrade — no `UPGRADE_PLUGIN_PERMISSION` grant/revoke bracket is required.

### Deployment Checklist

- [ ] I have cloned the official repository on my computer and I have checked out the `main` branch
- [ ] I am using the latest official docker engine, running a Debian Linux (stable) image
  - [ ] I have run `docker run --rm -it -v .:/deployment --env-file  <(vars resolve --partial --dotenv 2>/dev/null) debian:trixie-slim`
  - [ ] I have run `apt update && apt install -y just curl git vim neovim bc jq`
  - [ ] I have run `curl -L https://foundry.paradigm.xyz | bash && source /root/.bashrc && foundryup`
  - [ ] I have run `cd /deployment`
  - [ ] I have run `just init <network>`
- [ ] I am opening an editor on the `/deployment` folder, within the Docker container
- [ ] I have run `just env` and verified that all parameters are correct
  - [ ] `DEPLOYER_KEY` is set (via `vars set DEPLOYER_KEY` or in root `.env`)
  - [ ] `ETHERSCAN_API_KEY` is set (via `vars set ETHERSCAN_API_KEY` or in root `.env`)
  - [ ] I have set the deployment parameters in the root `.env` file:
    - [ ] `MANAGEMENT_DAO_MIN_APPROVALS` has the right value
    - [ ] `MANAGEMENT_DAO_MEMBERS_FILE_NAME` points to a file containing the correct multisig addresses
    - [ ] `MANAGEMENT_DAO_METADATA_URI` is set to the correct IPFS URI
    - [ ] Plugin metadata URIs are set (if overriding the defaults)
  - [ ] I have created a new burner wallet with `cast wallet new` and used its private key as `DEPLOYER_KEY`
  - [ ] I am the only person of the ceremony that will operate the deployment wallet
- [ ] All the tests run clean (`just test`)
- [ ] `just check-upgrade OldContract NewContract` reports the storage layout check passed
- My computer:
  - [ ] Is running in a safe location and using a trusted network
  - [ ] It exposes no services or ports
    - MacOS: `sudo lsof -iTCP -sTCP:LISTEN -nP`
    - Linux: `netstat -tulpn`
    - Windows: `netstat -nao -p tcp`
  - [ ] The wifi or wired network in use does not expose any ports to a WAN
- [ ] I have run `just predeploy` and the simulation completes with no errors
- [ ] I have run `just balance` and the deployment wallet has sufficient funds
  - At least, 15% more than the amount estimated during the simulation
- [ ] `just test` still runs clean
- [ ] I have run `git status` and it reports no local changes
- [ ] The current local git branch (`main`) corresponds to its counterpart on `origin`
  - [ ] I confirm that the rest of members of the ceremony pulled the last git commit on `main` and reported the same commit hash as my output for `git log -n 1`
- [ ] I have initiated the production deployment with `just deploy`

### Post deployment checklist

- [ ] The deployment process completed with no errors
- [ ] The factory contract was deployed by the deployment address
- [ ] All the project's smart contracts are correctly verified on the reference block explorer of the target network.
- [ ] The output of the latest `logs/deployment-<network>-<date>.log` file corresponds to the console output
- [ ] A file called `artifacts/addresses-<network>-<timestamp>.json` has been created, and the addresses match those logged to the screen
- [ ] I have uploaded the following files to a shared location:
  - `logs/deployment-<network>.log` (the last one)
  - `artifacts/addresses-<network>-<timestamp>.json`  (the last one)
  - `broadcast/Deploy.s.sol/<chain-id>/run-<timestamp>.json` (the last one)
- [ ] The rest of members confirm that the values are correct
- [ ] I have transferred the remaining funds of the deployment wallet to the address that originally funded it
  - `just refund`
- [ ] I have cloned https://github.com/aragon/diffyscan-workspace/
  - [ ] I have copied the deployed addresses to a new config file for the network
  - [ ] I have run the source code verification and the code matches the [audited commits](https://github.com/aragon/osx/tree/main/audits)

This concludes the deployment ceremony.

### Post deployment (external packages)

This is optional if you are deploying to a custom network.

- [ ] I have followed [these instructions](https://github.com/aragon/osx-commons/tree/main/configs#generating-the-json-files) to generate the JSON file with the addresses for the new network
  - [ ] If needed, I have added the new network settings
- [ ] I have followed [these instructions](https://github.com/aragon/osx/tree/main/packages/artifacts#syncing-the-deployment-addresses) for OSx
- [ ] For each plugin, I have followed the equivalent instructions
  - https://github.com/aragon/admin-plugin/tree/main/packages/artifacts#syncing-the-deployment-addresses
  - https://github.com/aragon/multisig-plugin/tree/main/packages/artifacts#syncing-the-deployment-addresses
  - https://github.com/aragon/token-voting-plugin/tree/main/packages/artifacts#syncing-the-deployment-addresses
  - https://github.com/aragon/staged-proposal-processor-plugin/tree/main/packages/artifacts#syncing-the-deployment-addresses
- [ ] I have created a pull request with the updated addresses files on every repository

## Other

ZkSync networks are also supported:

```shell
just setup-zksync          # installs forge-zksync alongside standard Foundry
just switch zksync-sepolia
```
