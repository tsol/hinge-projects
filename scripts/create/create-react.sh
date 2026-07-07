#!/bin/bash
# Create a React + TypeScript Vite project with Hinge wired in.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

_create_common_init

name="${1:-}"
do_start="false"
[[ "${2:-}" == "--start" || "${3:-}" == "--start" ]] && do_start="true"

if ! _create_validate_name "$name"; then
    exit 1
fi

if ! _create_ensure_hinge_built; then
    exit 1
fi

if ! _create_scaffold_vite "react-ts" "$name"; then
    exit 1
fi

project_dir="$CREATE_PROJECTS_ROOT/$name"
template_dir="$CREATE_TEMPLATES_DIR/react-hinge"

_create_apply_template_file "$template_dir/vite.config.ts" "$project_dir/vite.config.ts"
_create_apply_template_file "$template_dir/App.tsx" "$project_dir/src/App.tsx"
_create_apply_template_file "$template_dir/main.tsx" "$project_dir/src/main.tsx"

_create_add_hinge_dep "$project_dir"
_create_patch_workspace_yaml "$name"

_create_log "Installing dependencies..."
if ! _create_pnpm_install "$project_dir"; then
    echo "ERROR: pnpm install failed."
    exit 1
fi

_create_log "Created React project: $name"
echo "project=$name"
echo "framework=react"
echo "path=$project_dir"
echo "hinge=file:../hinge"
echo ""
echo "Next: ./project.sh $name start"

_create_optional_start "$name" "$do_start"
