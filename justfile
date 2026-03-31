default: help
import 'lib/just-foundry/justfile'

DEPLOY_SCRIPT := "script/Deploy.s.sol:Deploy"

# Run the ZkSync test suite (swaps SPPSetup with the ZkSync variant for the duration)
[group('test')]
test-zksync:
    #!/usr/bin/env bash
    set -euo pipefail
    forge-zksync cache clean all || true
    rm -rf zkout
    echo "Temporarily using the ZkSync version of StagedProposalProcessorSetup"
    cp src/StagedProposalProcessorSetup.sol src/StagedProposalProcessorSetup.sol.bak
    cp src/StagedProposalProcessorSetupZkSync.sol src/StagedProposalProcessorSetup.sol
    forge-zksync test -vvvv --zksync; STATUS=$?
    mv src/StagedProposalProcessorSetup.sol.bak src/StagedProposalProcessorSetup.sol
    exit $STATUS

# Simulate a clean SPP deployment (ZkSync)
[group('script')]
predeploy-zksync:
    #!/usr/bin/env bash
    set -euo pipefail
    source {{ENV_RESOLVE_LIB}} && env_load
    forge-zksync script {{DEPLOY_SCRIPT}} --chain "$CHAIN_ID" --rpc-url "$RPC_URL" --zksync -vvvv

# Deploy a clean SPP (ZkSync)
[group('script')]
deploy-zksync:
    #!/usr/bin/env bash
    set -euo pipefail
    source {{ENV_RESOLVE_LIB}} && env_load
    VERIFIER_PARAMS=$(just resolve-verifier-params) || exit 1
    mkdir -p logs
    LOG_FILE="logs/deployment-$NETWORK_NAME-$(date +"%y-%m-%d-%H-%M").log"
    forge-zksync script {{DEPLOY_SCRIPT}} --chain "$CHAIN_ID" --rpc-url "$RPC_URL" \
        --broadcast --zksync $VERIFIER_PARAMS \
        2>&1 | tee -a "$LOG_FILE"

# Publish a new SPP version (ZkSync)
[group('script')]
new-version-zksync:
    #!/usr/bin/env bash
    set -euo pipefail
    source {{ENV_RESOLVE_LIB}} && env_load
    VERIFIER_PARAMS=$(just resolve-verifier-params) || exit 1
    mkdir -p logs
    LOG_FILE="logs/new-version-$NETWORK_NAME-$(date +"%y-%m-%d-%H-%M").log"
    forge-zksync script script/NewVersion.s.sol:NewVersion --chain "$CHAIN_ID" --rpc-url "$RPC_URL" \
        --broadcast --zksync $VERIFIER_PARAMS \
        2>&1 | tee -a "$LOG_FILE"

# Deploy and upgrade the SPP plugin repo (ZkSync)
[group('script')]
upgrade-repo-zksync:
    #!/usr/bin/env bash
    set -euo pipefail
    source {{ENV_RESOLVE_LIB}} && env_load
    VERIFIER_PARAMS=$(just resolve-verifier-params) || exit 1
    mkdir -p logs
    LOG_FILE="logs/upgrade-repo-$NETWORK_NAME-$(date +"%y-%m-%d-%H-%M").log"
    forge-zksync script script/UpgradeRepo.s.sol:UpgradeRepo --chain "$CHAIN_ID" --rpc-url "$RPC_URL" \
        --broadcast --zksync $VERIFIER_PARAMS \
        2>&1 | tee -a "$LOG_FILE"

# Verify the plugin implementation on ZkSync (usage: just verify-zksync address=0x1234...)
[group('verification')]
verify-zksync address:
    #!/usr/bin/env bash
    set -euo pipefail
    source {{ENV_RESOLVE_LIB}} && env_load
    VERIFIER_PARAMS=$(just resolve-verifier-params) || exit 1
    forge-zksync verify-contract \
        --zksync \
        --chain "$CHAIN_ID" \
        --num-of-optimizations 200 \
        --watch \
        $VERIFIER_PARAMS \
        {{address}} \
        src/StagedProposalProcessor.sol:StagedProposalProcessor
