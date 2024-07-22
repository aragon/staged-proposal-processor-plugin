#!/bin/bash

include .env

tt:
	forge script Deploy --rpc-url $(NETWORK_RPC_URL) --verify --etherscan-api-key ${ETHERSCAN_API_KEY} -vvvv
	
