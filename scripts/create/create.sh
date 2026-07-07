#!/bin/bash
# Dispatcher: create vue|react projects (extensible via registry.txt + create-<framework>.sh)

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="$SCRIPT_DIR/registry.txt"

usage() {
    cat <<EOF
Usage:
  create.sh list
  create.sh <framework> <name> [--start]

Frameworks:
EOF
    if [[ -f "$REGISTRY" ]]; then
        sed 's/^/  - /' "$REGISTRY"
    else
        echo "  - vue"
        echo "  - react"
    fi
}

cmd_list() {
    echo "Registered frameworks:"
    if [[ -f "$REGISTRY" ]]; then
        while read -r fw; do
            [[ -z "$fw" || "$fw" =~ ^# ]] && continue
            local script="$SCRIPT_DIR/create-${fw}.sh"
            if [[ -x "$script" ]]; then
                echo "  $fw  ($script)"
            else
                echo "  $fw  (missing create-${fw}.sh)"
            fi
        done < "$REGISTRY"
    else
        for script in "$SCRIPT_DIR"/create-*.sh; do
            [[ "$script" == *"_common.sh" ]] && continue
            local base; base=$(basename "$script" .sh)
            echo "  ${base#create-}"
        done
    fi
}

framework="${1:-}"
name="${2:-}"
extra="${3:-}"

case "$framework" in
    ""|-h|--help|help)
        usage
        exit 0
        ;;
    list)
        cmd_list
        exit 0
        ;;
esac

script="$SCRIPT_DIR/create-${framework}.sh"
if [[ ! -x "$script" ]]; then
    echo "ERROR: unknown framework '$framework' (no $script)"
    echo ""
    usage
    exit 1
fi

exec "$script" "$name" "$extra"
