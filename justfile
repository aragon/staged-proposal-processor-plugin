default: help

import 'lib/just-foundry/justfile'

# Generate Solidity documentation (requires bun)
[group('docs')]
docs:
    cd docs-gen && bun install && bash prepare-docs.sh && bun prepare-docs.js

DEPLOY_SCRIPT := "script/Deploy.s.sol:Deploy"
NEW_VERSION_SCRIPT := "script/NewVersion.s.sol:NewVersion"

# Dry-run the new-version script (no broadcast) — eyeball the printed multisig calldata
[group('upgrade')]
pre-new-version:
    just dry-run {{ NEW_VERSION_SCRIPT }}

# Publish a new SPP plugin version (deploys setup, prints DAO proposal calldata)
[group('upgrade')]
new-version *args:
    #!/usr/bin/env bash
    set -euo pipefail
    source {{ JUST_LIB }} && env_load_network
    mkdir -p logs
    LOG_FILE="logs/new-version-$NETWORK_NAME-$(date +"%y-%m-%d-%H-%M").log"
    just test 2>&1 | tee -a "$LOG_FILE"
    just run {{ NEW_VERSION_SCRIPT }} {{ args }} 2>&1 | tee -a "$LOG_FILE"
    echo "Logs saved in $LOG_FILE"

