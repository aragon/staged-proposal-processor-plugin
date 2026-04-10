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

