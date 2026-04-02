#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

rm -rf "$ROOT/docs/templates"

PACKAGE_PATH=$(bun -p "require.resolve('@aragon/osx-commons-configs')")
TEMPLATES_PATH=$(dirname "$PACKAGE_PATH")/docs/templates

mkdir -p "$ROOT/docs/templates"
cp -r "$TEMPLATES_PATH" "$ROOT/docs"
