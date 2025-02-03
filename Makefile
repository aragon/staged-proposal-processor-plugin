#!/bin/bash

include .env

### When running the tests on zksync, we copy SPPSetupZksync into SPPSetup to avoid 
### changing imports in the tests. This requires to temporarily store SPPSetup's code 
### in a temp file, so that after tests are done, we can restore the original codebase.
### Without removing zkout/temp.sol, compiler fails as it can't find temp.sol in the 
### src directory, but it still finds it in the compilation output.

$(shell rm -rf zkout/temp.sol)
$(shell rm -rf out/temp.sol)
$(shell forge cache clean all)
$(shell rm -rf cache)

### Deployment short codes for EVM based networks
deploy:
	forge script Deploy --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) --etherscan-api-key $(ETHERSCAN_API_KEY) --verifier $(VERIFIER) --verify --broadcast

new-version:
	forge script NewVersion --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) --etherscan-api-key $(ETHERSCAN_API_KEY) --verifier $(VERIFIER) --verify --broadcast

upgrade-repo:
	forge script UpgradeRepo --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) --etherscan-api-key $(ETHERSCAN_API_KEY) --verifier $(VERIFIER) --verify --broadcast

### Deployment short codes for zksync network
deploy-zksync:
	forge script Deploy --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) --verify --verifier zksync --verifier-url $(VERIFIER_URL) --broadcast --zksync

new-version-zksync:
	forge script NewVersion --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) --verify --verifier zksync --verifier-url $(VERIFIER_URL) --broadcast --zksync

upgrade-repo-zksync:
	forge script UpgradeRepo --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) --verify --verifier zksync --verifier-url $(VERIFIER_URL) --broadcast --zksync

