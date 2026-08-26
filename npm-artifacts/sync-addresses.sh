#!/usr/bin/env bash
# Generate src/addresses.json from protocol-factory's deployment artifacts.
#
# protocol-factory/artifacts/ contains files of the form
#   addresses-<network>-<unix_timestamp>.json
# We pick the file with the highest timestamp suffix per network and extract
# `corePlugins.stagedProposalProcessorPluginRepo` from it.

set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") <protocol_factory_artifacts_dir> <destination_file>" >&2
    echo "  e.g. $(basename "$0") ../../protocol-factory/artifacts ./src/addresses.json" >&2
}

if [[ $# -ne 2 ]]; then
    echo "Error: expected 2 arguments." >&2
    usage
    exit 1
fi

SOURCE_DIR="$1"
DEST_FILE="$2"

if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: source directory '$SOURCE_DIR' not found." >&2
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "Error: 'jq' is required (sudo apt install jq / brew install jq)." >&2
    exit 1
fi

cd "$(dirname "$0")"

# Start from whatever's currently in DEST_FILE so we don't drop networks that
# aren't represented in protocol-factory's artifacts. Overlay the freshly
# resolved entries on top — same-network keys win the latest value.
if [[ -f "$DEST_FILE" ]]; then
    BASE=$(cat "$DEST_FILE")
else
    BASE='{"pluginRepo":{}}'
fi

# Group `addresses-<network>-<ts>.json` files by network, pick the highest ts per network.
declare -A LATEST
for path in "$SOURCE_DIR"/addresses-*-*.json; do
    [[ -f "$path" ]] || continue
    fname=$(basename "$path")
    # strip `addresses-` prefix and `.json` suffix → `<network>-<ts>`
    rest=${fname#addresses-}
    rest=${rest%.json}
    network=${rest%-*}
    ts=${rest##*-}
    [[ "$ts" =~ ^[0-9]+$ ]] || { echo "Skipping malformed name: $fname" >&2; continue; }

    if [[ -z "${LATEST[$network]+x}" ]] || (( ts > ${LATEST[$network]##*|} )); then
        LATEST[$network]="$path|$ts"
    fi
done

if [[ ${#LATEST[@]} -eq 0 ]]; then
    echo "Warning: no addresses-*-*.json files in '$SOURCE_DIR'; leaving $DEST_FILE untouched." >&2
    exit 0
fi

# Build the overlay object as `{pluginRepo: {<network>: <addr>, ...}}`.
OVERLAY='{"pluginRepo":{}}'
for network in "${!LATEST[@]}"; do
    entry=${LATEST[$network]}
    file=${entry%|*}
    echo "Using $(basename "$file") for $network"

    addr=$(jq -er '.corePlugins.stagedProposalProcessorPluginRepo // empty' "$file") || {
        echo "  Warning: corePlugins.stagedProposalProcessorPluginRepo missing in $(basename "$file"); skipping." >&2
        continue
    }
    if [[ -z "$addr" || "$addr" == "null" ]]; then
        echo "  Warning: empty SPP plugin repo address in $(basename "$file"); skipping." >&2
        continue
    fi

    OVERLAY=$(jq --arg network "$network" --arg value "$addr" '.pluginRepo[$network] = $value' <<<"$OVERLAY")
done

# Merge: BASE overlaid by OVERLAY, with deterministic alphabetical key order.
jq --sort-keys -n --argjson base "$BASE" --argjson overlay "$OVERLAY" \
    '{pluginRepo: ($base.pluginRepo + $overlay.pluginRepo)}' > "$DEST_FILE"

echo "Addresses merged into '$DEST_FILE'"
