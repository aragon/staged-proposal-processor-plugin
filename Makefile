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

define append_common_args
	command="$$command --rpc-url $(NETWORK_RPC_URL)"; \
	[ "$(broadcast)" = "true" ] && command="$$command --broadcast"; \
	if [ "$(NETWORK_NAME)" != "local" ] && [ "$(broadcast)" = "true" ]; then \
		command="$$command --chain $(CHAIN) --verify --etherscan-api-key $(ETHERSCAN_API_KEY) --verifier $(VERIFIER)"; \
		if [ -n "$(VERIFIER_URL)" ]; then \
			command="$$command --verifier-url $(VERIFIER_URL)"; \
		fi; \
	fi; \
	command="$$command --slow -vvvv"; \
	echo "Running: $$command";
endef

### Deployment short codes for EVM based networks
deploy:
	@command="forge script Deploy"; \
	$(call append_common_args) \
	$$command

new-version:
	@command="forge script NewVersion"; \
	$(call append_common_args) \
	$$command

upgrade-repo:
	@command="forge script UpgradeRepo"; \
	$(call append_common_args) \
	$$command

### Deployment short codes for zksync network
deploy-zksync:
	forge script Deploy --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) --verify --verifier zksync --verifier-url $(VERIFIER_URL) --broadcast --zksync

new-version-zksync:
	forge script NewVersion --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) --verify --verifier zksync --verifier-url $(VERIFIER_URL) --broadcast --zksync

upgrade-repo-zksync:
	forge script UpgradeRepo --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) --verify --verifier zksync --verifier-url $(VERIFIER_URL) --broadcast --zksync

