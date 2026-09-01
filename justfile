default: help

import 'lib/just-foundry/justfile'

# Generate Solidity documentation (requires bun)
[group('docs')]
docs:
    cd docs-gen && bun install && bash prepare-docs.sh && bun prepare-docs.js

NEW_VERSION_SCRIPT := "script/NewVersion.s.sol:NewVersion"

# Dry-run the new-version script (no broadcast) — eyeball the printed multisig calldata
[group('upgrade')]
pre-new-version:
    just dry-run {{ NEW_VERSION_SCRIPT }}

# Publish a new SPP plugin version (deploys setup, prints DAO proposal calldata)
[group('upgrade')]
new-version:
    just run {{ NEW_VERSION_SCRIPT }}
