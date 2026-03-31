default: help
import 'lib/just-foundry/justfile'

DEPLOY_SCRIPT := "script/Deploy.s.sol:Deploy"

# Publish a new SPP plugin version (deploys setup, prints DAO proposal calldata)
[group('upgrade')]
new-version *args:
    #!/usr/bin/env bash
    set -euo pipefail
    source {{ENV_RESOLVE_LIB}} && env_load_network
    mkdir -p logs
    LOG_FILE="logs/new-version-$NETWORK_NAME-$(date +"%y-%m-%d-%H-%M").log"
    just test 2>&1 | tee -a "$LOG_FILE"
    just run script/NewVersion.s.sol:NewVersion {{args}} 2>&1 | tee -a "$LOG_FILE"
    echo "Logs saved in $LOG_FILE"

# Check storage layout upgrade compatibility between two contracts (requires jq)
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
