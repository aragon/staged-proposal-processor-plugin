.DEFAULT_TARGET: help
SHELL:=/bin/bash
FORGE:=forge
FORGE_ZKSYNC:=forge-zksync

# Import the .env file and export their values
-include .env

# TARGETS

##

.PHONY: help
help: ## Display the current message
	@echo "Available targets:"
	@cat Makefile | while IFS= read -r line; do \
	   if [[ "$$line" == "##" ]]; then \
			echo "" ; \
		elif [[ "$$line" =~ ^([^:]+):(.*)##\ (.*)$$ ]]; then \
			echo -e " - make $${BASH_REMATCH[1]} \t\t$${BASH_REMATCH[3]}" ; \
		fi ; \
	done

.PHONY: init
init: ## Install foundry and foundry-zksync on your computer
	@echo "Installing Foundry ZkSync"
	curl -L https://raw.githubusercontent.com/matter-labs/foundry-zksync/main/install-foundry-zksync | bash
	foundryup-zksync
	mv ~/.foundry/bin/forge ~/.foundry/bin/$(FORGE_ZKSYNC)
	mv ~/.foundry/bin/cast ~/.foundry/bin/cast-zksync

	@echo "Installing Foundry"
	curl -L https://foundry.paradigm.xyz | bash
	foundryup -v stable

	@$(FORGE) build
	@which lcov > /dev/null || echo "Note: lcov can be installed by running 'sudo apt install lcov'"

.PHONY: clean
clean: ## Clean the generated artifacts
	$(FORGE) cache clean all || true
	$(FORGE_ZKSYNC) cache clean all || true
	rm -rf ./cache
	rm -rf ./out
	rm -rf ./zkout
	rm -Rf lcov.info* ./report/*

##

.PHONY: test
test: ## Run the test suite (standard EVM)
	$(FORGE) test -vvvv --match-path "test/unit/**"

.PHONY: test-coverage
test-coverage: report/index.html ## Generate an HTML coverage report under ./report
	@which open > /dev/null && open report/index.html || echo -n
	@which xdg-open > /dev/null && xdg-open report/index.html || echo -n

report/index.html: lcov.info
	genhtml $^ -o report --branch-coverage --ignore-errors inconsistent

lcov.info: $(TEST_COVERAGE_SRC_FILES)
	$(FORGE) coverage --match-path "test/unit/**" --report lcov \
		| grep -v "| node_modules" | grep -v "| script/" | grep -v "| test/" | grep -v "\-\-|$$"

.PHONY: test-fork
test-fork: ## Run the fork test suite (standard EVM)
	$(FORGE) test -vvvv --match-path "test/fork/*"

.PHONY: test-integration
test-integration: ## Run the integration test suite (standard EVM)
	$(FORGE) test -vvvv --match-path "test/integration/*"

##

### Deployment targets for EVM based networks

predeploy:  ## Simulate a clean SPP deployment (standard EVM)
	$(FORGE) script Deploy --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) -vvvv

deploy:  ## Deploy a clean SPP (standard EVM)
	$(FORGE) script Deploy --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) \
	   --etherscan-api-key $(ETHERSCAN_API_KEY) --verifier $(VERIFIER) --verify --broadcast \
		2>&1 | tee -a $(@).log

new-version:  ## Publish a new SPP version (standard EVM)
	$(FORGE) script NewVersion --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) \
	   --etherscan-api-key $(ETHERSCAN_API_KEY) --verifier $(VERIFIER) --verify --broadcast \
		2>&1 | tee -a $(@).log

upgrade-repo:  ## Deploy and upgrade the SPP plugin repo (standard EVM)
	$(FORGE) script UpgradeRepo --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) \
	   --etherscan-api-key $(ETHERSCAN_API_KEY) --verifier $(VERIFIER) --verify --broadcast \
		2>&1 | tee -a $(@).log

##

predeploy-proxy:  ## Simulate a proxy instance deployment
	$(FORGE) script DeployProxy --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) -vvvv

deploy-proxy:  ## Deploy a proxy instance with the current settings
	$(FORGE) script DeployProxy --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) \
	   --etherscan-api-key $(ETHERSCAN_API_KEY) --verifier $(VERIFIER) --verify --broadcast \
		2>&1 | tee -a $(@).log

##

### Deployment targets for zksync network

.PHONY: test-zksync
test-zksync: clean ## Run the test suite (ZkSync)
	@### When running the tests on zksync, we copy SPPSetupZksync into SPPSetup to avoid
	@### changing imports in the tests. This requires to temporarily store SPPSetup's code
	@### in a temp file, so that after tests are done, we can restore the original codebase.
	@### Without removing zkout/temp.sol, compiler fails as it can't find temp.sol in the
	@### src directory, but it still finds it in the compilation output.
	@echo "Temporarily using the ZkSync version of StagedProposalProcessorSetup"
	cp src/StagedProposalProcessorSetup.sol src/StagedProposalProcessorSetup.sol.bak
	cp src/StagedProposalProcessorSetupZkSync.sol src/StagedProposalProcessorSetup.sol

	$(FORGE_ZKSYNC) test -vvvv --zksync ; \
	if [ "$$?" = "0" ]; then \
	   mv src/StagedProposalProcessorSetup.sol.bak src/StagedProposalProcessorSetup.sol ; \
	else \
		mv src/StagedProposalProcessorSetup.sol.bak src/StagedProposalProcessorSetup.sol ; \
		exit 1 ; \
	fi

predeploy-zksync:  ## Simulate a clean SPP deployment (ZkSync)
	$(FORGE_ZKSYNC) script Deploy --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) --zksync -vvvv

deploy-zksync:  ## Deploy a clean SPP (ZkSync)
	$(FORGE_ZKSYNC) script Deploy --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) \
	   --verify --verifier zksync --verifier-url $(VERIFIER_URL) --broadcast --zksync \
		2>&1 | tee -a $(@).log

new-version-zksync:  ## Publish a new SPP version (ZkSync)
	$(FORGE_ZKSYNC) script NewVersion --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) \
	   --verify --verifier zksync --verifier-url $(VERIFIER_URL) --broadcast --zksync \
		2>&1 | tee -a $(@).log

upgrade-repo-zksync:  ## Deploy and upgrade the SPP plugin repo (ZkSync)
	$(FORGE_ZKSYNC) script UpgradeRepo --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) \
	   --verify --verifier zksync --verifier-url $(VERIFIER_URL) --broadcast --zksync \
		2>&1 | tee -a $(@).log

##

predeploy-proxy-zksync:  ## Simulate a proxy instance deployment (ZkSync)
	$(FORGE) script DeployProxy --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) --zksync -vvvv

deploy-proxy-zksync:  ## Deploy a proxy instance with the current settings (ZkSync)
	$(FORGE) script DeployProxy --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) \
	   --etherscan-api-key $(ETHERSCAN_API_KEY) --verifier $(VERIFIER) --verify --broadcast --zksync \
		2>&1 | tee -a $(@).log

##

verify-zksync-implementation:  ## Verify the plugin implementation (if not automatically done)
	@if [ -z "$(address)" ]; then \
		echo "Please, invoke with the address:" ; \
		echo "$$ make $(@) address=0x1234..." ; \
		echo ; \
		exit 1 ; \
	fi
	$(FORGE_ZKSYNC) verify-contract \
        --zksync \
        --chain $(CHAIN) \
        --num-of-optimizations 200 \
        --watch \
        --verifier zksync  \
        --verifier-url $(VERIFIER_URL) \
        $(address) \
        src/StagedProposalProcessor.sol:StagedProposalProcessor
