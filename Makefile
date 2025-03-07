.DEFAULT_TARGET: help
SHELL:=/bin/bash

# Import the .env files and export their values
include .env

# TARGETS

##

.PHONY: help
help:
	@echo "Available targets:"
	@cat Makefile | while IFS= read -r line; do \
	   if [[ "$$line" == "##" ]]; then \
			echo "" ; \
		elif [[ "$$line" =~ ^([^:]+):(.*)##\ (.*)$$ ]]; then \
			echo -e " - make $${BASH_REMATCH[1]}: \t\t$${BASH_REMATCH[3]}" ; \
		fi ; \
	done

.PHONY: init
init: ## Install foundry and foundry-zksync on your computer
	@echo "Installing Foundry ZkSync"
	curl -L https://raw.githubusercontent.com/matter-labs/foundry-zksync/main/install-foundry-zksync | bash
	foundryup-zksync
	mv ~/.foundry/bin/forge ~/.foundry/bin/forge-zksync
	mv ~/.foundry/bin/cast ~/.foundry/bin/cast-zksync

	@echo "Installing Foundry"
	curl -L https://foundry.paradigm.xyz | bash
	foundryup -v stable

.PHONY: clean
clean: ## Clean the generated artifacts
	forge cache clean all || true
	forge-zksync cache clean all || true
	rm -rf ./cache
	@make clean-zksync-test

### When running the tests on zksync, we copy SPPSetupZksync into SPPSetup to avoid
### changing imports in the tests. This requires to temporarily store SPPSetup's code
### in a temp file, so that after tests are done, we can restore the original codebase.
### Without removing zkout/temp.sol, compiler fails as it can't find temp.sol in the
### src directory, but it still finds it in the compilation output.

.PHONY: clean-zksync-test
clean-zksync-test:
	@echo "Cleaning ZkSync test replacement"
	rm -f ./zkout/temp.sol
	rm -f ./out/temp.sol

##

### Deployment targets for EVM based networks

predeploy: clean  ## Simulate a standard EVM deployment
	forge script Deploy --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL)

deploy: clean  ## Deploy a clean EVM SPP
	forge script Deploy --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) \
	   --etherscan-api-key $(ETHERSCAN_API_KEY) --verifier $(VERIFIER) --verify --broadcast

new-version: clean  ## Deploy a new EVM SPP version
	forge script NewVersion --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) \
	   --etherscan-api-key $(ETHERSCAN_API_KEY) --verifier $(VERIFIER) --verify --broadcast

upgrade-repo: clean  ## Deploy and upgrade the SPP plugin repo on a standard EVM
	forge script UpgradeRepo --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) \
	   --etherscan-api-key $(ETHERSCAN_API_KEY) --verifier $(VERIFIER) --verify --broadcast

##

### Deployment targets for zksync network

predeploy-zksync: clean  ## x
	forge-zksync script Deploy --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) --zksync

deploy-zksync: clean  ## x
	forge-zksync script Deploy --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) \
	   --verify --verifier zksync --verifier-url $(VERIFIER_URL) --broadcast --zksync

new-version-zksync: clean  ## x
	forge-zksync script NewVersion --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) \
	   --verify --verifier zksync --verifier-url $(VERIFIER_URL) --broadcast --zksync

upgrade-repo-zksync: clean  ## x
	forge-zksync script UpgradeRepo --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) \
	   --verify --verifier zksync --verifier-url $(VERIFIER_URL) --broadcast --zksync
