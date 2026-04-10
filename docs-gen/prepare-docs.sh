#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

rm -rf "$ROOT/docs/templates"

PACKAGE_PATH=$(bun -p "require.resolve('@aragon/osx-commons-configs')")
TEMPLATES_PATH=$(dirname "$PACKAGE_PATH")/docs/templates

[ -d "$TEMPLATES_PATH" ] || { echo "Error: templates not found at $TEMPLATES_PATH" >&2; exit 1; }

mkdir -p "$ROOT/docs/templates"
cp -r "$TEMPLATES_PATH" "$ROOT/docs"
