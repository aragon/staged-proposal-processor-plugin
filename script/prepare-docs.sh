#!/usr/bin/env bash

set -euo pipefail
# shopt -s globstar

PACKAGE_NAME="@aragon/osx-commons-configs"
PACKAGE_PATH=$(node -p "require.resolve('$PACKAGE_NAME')")
TEMPLATES_PATH=$(dirname "$PACKAGE_PATH")/docs/templates

cp -r "$TEMPLATES_PATH" "./docs"

if [ ! -d node_modules ]; then
  npm ci
fi


# hardhat docgen

# node scripts/gen-nav.js "$OUTDIR" > "$OUTDIR/../nav.adoc"

# rm -rf ./docs/templates