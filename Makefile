#!/bin/bash

include .env

deploy:
	forge script Deploy --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) --etherscan-api-key $(ETHERSCAN_API_KEY) --verifier $(VERIFIER) --verify --broadcast

new-version:
	forge script NewVersion --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) --etherscan-api-key $(ETHERSCAN_API_KEY) --verifier $(VERIFIER) --verify --broadcast

upgrade-repo:
	forge script UpgradeRepo --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) --etherscan-api-key $(ETHERSCAN_API_KEY) --verifier $(VERIFIER) --verify --broadcast


t:
	forge script Scriptt --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) -vvvv

tt:
	forge script Scriptt --chain $(CHAIN) --rpc-url $(NETWORK_RPC_URL) --broadcast
