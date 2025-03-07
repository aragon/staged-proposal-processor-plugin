.DEFAULT_TARGET: help
SHELL:=/bin/bash

# Import the .env files and export their values
include .env

# TARGETS

##

.PHONY: help
help: ## Display the current message
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

### When running the tests on zksync, we copy SPPSetupZksync into SPPSetup to avoid
### changing imports in the tests. This requires to temporarily store SPPSetup's code
### in a temp file, so that after tests are done, we can restore the original codebase.
### Without removing zkout/temp.sol, compiler fails as it can't find temp.sol in the
### src directory, but it still finds it in the compilation output.

##

### Deployment targets for EVM based networks

test: clean ## Run the test suite (standard EVM)
	forge test -vvv

predeploy: clean  ## Simulate a clean SPP deployment (standard EVM)
	forge script Deploy --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL)

deploy: clean  ## Deploy a clean SPP (standard EVM)
	forge script Deploy --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) \
	   --etherscan-api-key $(ETHERSCAN_API_KEY) --verifier $(VERIFIER) --verify --broadcast \
		| tee -a $(@).log

new-version: clean  ## Publish a new SPP version (standard EVM)
	forge script NewVersion --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) \
	   --etherscan-api-key $(ETHERSCAN_API_KEY) --verifier $(VERIFIER) --verify --broadcast \
		| tee -a $(@).log

upgrade-repo: clean  ## Deploy and upgrade the SPP plugin repo (standard EVM)
	forge script UpgradeRepo --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) \
	   --etherscan-api-key $(ETHERSCAN_API_KEY) --verifier $(VERIFIER) --verify --broadcast \
		| tee -a $(@).log

##

### Deployment targets for zksync network

test-zksync: clean ## Run the test suite (ZkSync)
	@echo "Temporarily using the ZkSync version of StagedProposalProcessorSetup"
	cp src/StagedProposalProcessorSetup.sol src/StagedProposalProcessorSetup.sol.bak
	cp src/StagedProposalProcessorSetupZkSync.sol src/StagedProposalProcessorSetup.sol

	forge-zksync test -vvv --zksync ; \
	if [ "$$?" = "0" ]; then \
	   mv src/StagedProposalProcessorSetup.sol.bak src/StagedProposalProcessorSetup.sol ; \
	else \
		mv src/StagedProposalProcessorSetup.sol.bak src/StagedProposalProcessorSetup.sol ; \
		exit 1 ; \
	fi

predeploy-zksync: clean  ## Simulate a clean SPP deployment (ZkSync)
	forge-zksync script Deploy --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) --zksync

deploy-zksync: clean  ## Deploy a clean SPP (ZkSync)
	forge-zksync script Deploy --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) \
	   --verify --verifier zksync --verifier-url $(VERIFIER_URL) --broadcast --zksync \
		| tee -a $(@).log

new-version-zksync: clean  ## Publish a new SPP version (ZkSync)
	forge-zksync script NewVersion --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) \
	   --verify --verifier zksync --verifier-url $(VERIFIER_URL) --broadcast --zksync \
		| tee -a $(@).log

upgrade-repo-zksync: clean  ## Deploy and upgrade the SPP plugin repo (ZkSync)
	forge-zksync script UpgradeRepo --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) \
	   --verify --verifier zksync --verifier-url $(VERIFIER_URL) --broadcast --zksync \
		| tee -a $(@).log

verify-zksync-implementation:  ## Verify the plugin implementation (if not automatically done)
	@if [ -z "$(address)" ]; then \
		echo "Please, invoke with the address:" ; \
		echo "$$ make $(@) address=0x1234..." ; \
		echo ; \
		exit 1 ; \
	fi
	forge-zksync verify-contract \
        --zksync \
        --chain $(CHAIN) \
        --num-of-optimizations 200 \
        --watch \
        --verifier zksync  \
        --verifier-url $(VERIFIER_URL) \
        $(address) \
        src/StagedProposalProcessor.sol:StagedProposalProcessor
