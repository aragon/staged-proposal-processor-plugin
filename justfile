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
[group('upgrade')]
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
[group('upgrade')]
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

# Check storage layout upgrade compatibility between two contracts (requires jq)
# Run before deploying any upgrade to detect storage collisions
# Example: just validate-upgrade SPPStorageV1 StagedProposalProcessor
[group('upgrade')]
validate-upgrade from to:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v jq &>/dev/null || { echo "Error: jq is required (sudo apt install jq / brew install jq)"; exit 1; }
    forge build --quiet
    REF=$(forge inspect {{from}} storage-layout --json)
    NEW=$(forge inspect {{to}} storage-layout --json)
    ERRORS=0
    while IFS=$'\t' read -r slot offset label; do
        match=$(echo "$NEW" | jq -r --arg s "$slot" --argjson o "$offset" --arg l "$label" \
            '.storage[] | select(.slot==$s and .offset==$o and .label==$l) | .label')
        if [ -z "$match" ]; then
            echo "  INCOMPATIBLE: '$label' at slot $slot offset $offset — missing or moved in {{to}}"
            ERRORS=$((ERRORS + 1))
        fi
    done < <(echo "$REF" | jq -r '.storage[] | select(.label != "__gap") | [.slot, .offset, .label] | @tsv')
    if [ "$ERRORS" -gt 0 ]; then
        echo "Storage layout check FAILED ($ERRORS incompatible slot(s)): {{from}} → {{to}}"
        exit 1
    fi
    echo "Storage layout check passed: {{from}} → {{to}} is safe to upgrade"

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
