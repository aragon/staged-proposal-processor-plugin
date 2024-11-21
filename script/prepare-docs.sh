#!/usr/bin/env bash

set -euo pipefail

rm -rf ./docs/templates

PACKAGE_NAME="@aragon/osx-commons-configs"
PACKAGE_PATH=$(node -p "require.resolve('$PACKAGE_NAME')")
TEMPLATES_PATH=$(dirname "$PACKAGE_PATH")/docs/templates

mkdir -p ./docs/templates

cp -r "$TEMPLATES_PATH" "./docs"

if [ ! -d node_modules ]; then
  npm ci
fi
