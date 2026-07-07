#!/bin/bash
# Shared helpers for project scaffolding (sourced, not executed directly)

set -o pipefail

_create_common_init() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    CREATE_SCRIPT_DIR="$script_dir"
    CREATE_PROJECTS_ROOT="$(cd "$script_dir/../.." && pwd)"
    CREATE_TEMPLATES_DIR="$CREATE_PROJECTS_ROOT/templates"
    CREATE_HINGE_DIR="$CREATE_PROJECTS_ROOT/hinge"
    CREATE_WORKSPACE_YAML="$CREATE_PROJECTS_ROOT/pnpm-workspace.yaml"
}

_create_log() { echo "[$(date '+%H:%M:%S')] $*"; }

_create_validate_name() {
    local name="$1"
    if [[ -z "$name" ]]; then
        echo "ERROR: project name is required."
        return 1
    fi
    if [[ ! "$name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        echo "ERROR: invalid name '$name' (use letters, digits, -, _; must start with a letter)."
        return 1
    fi
    local reserved
    for reserved in hinge node_modules skills scripts templates; do
        if [[ "$name" == "$reserved" ]]; then
            echo "ERROR: '$name' is reserved."
            return 1
        fi
    done
    if [[ -e "$CREATE_PROJECTS_ROOT/$name" ]]; then
        echo "ERROR: '$CREATE_PROJECTS_ROOT/$name' already exists."
        return 1
    fi
    return 0
}

_create_ensure_pnpm() {
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    export CI=1
    if command -v pnpm &>/dev/null && pnpm --version &>/dev/null; then
        return 0
    fi
    if command -v corepack &>/dev/null; then
        corepack enable pnpm &>/dev/null || true
        corepack prepare pnpm@latest --activate &>/dev/null || true
    fi
    command -v pnpm &>/dev/null && pnpm --version &>/dev/null
}

_create_ensure_hinge_built() {
    if [[ ! -d "$CREATE_HINGE_DIR" ]]; then
        echo "ERROR: hinge package not found at $CREATE_HINGE_DIR"
        echo "       Clone tsol/hinge into projects/hinge first."
        return 1
    fi
    if [[ -f "$CREATE_HINGE_DIR/dist/plugin.js" && -f "$CREATE_HINGE_DIR/dist/component.js" ]]; then
        return 0
    fi
    _create_log "Building hinge (dist/ missing)..."
    if ! _create_ensure_pnpm; then
        echo "ERROR: pnpm required to build hinge."
        return 1
    fi
    (cd "$CREATE_HINGE_DIR" && pnpm install && pnpm build) || {
        echo "ERROR: hinge build failed."
        return 1
    }
    [[ -f "$CREATE_HINGE_DIR/dist/plugin.js" ]]
}

_create_add_hinge_dep() {
    local project_dir="$1"
    node -e "
const fs = require('fs');
const p = '$project_dir/package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
pkg.dependencies = pkg.dependencies || {};
pkg.dependencies.hinge = 'file:../hinge';
fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
"
}

_create_patch_workspace_yaml() {
    local name="$1"
    if [[ ! -f "$CREATE_WORKSPACE_YAML" ]]; then
        return 0
    fi
    if grep -qE "^[[:space:]]*-[[:space:]]*'${name}'[[:space:]]*$" "$CREATE_WORKSPACE_YAML" 2>/dev/null; then
        return 0
    fi
    if grep -qE "^[[:space:]]*-[[:space:]]*\"${name}\"[[:space:]]*$" "$CREATE_WORKSPACE_YAML" 2>/dev/null; then
        return 0
    fi
    # Insert before minimumReleaseAge or at end of packages list
    if grep -q '^packages:' "$CREATE_WORKSPACE_YAML"; then
        sed -i "/^packages:/a\\  - '${name}'" "$CREATE_WORKSPACE_YAML"
        _create_log "Added '$name' to pnpm-workspace.yaml"
    fi
}

_create_remove_workspace_yaml() {
    local name="$1"
    [[ -f "$CREATE_WORKSPACE_YAML" ]] || return 0
    sed -i "/^[[:space:]]*-[[:space:]]*'${name}'[[:space:]]*$/d" "$CREATE_WORKSPACE_YAML"
    sed -i "/^[[:space:]]*-[[:space:]]*\"${name}\"[[:space:]]*$/d" "$CREATE_WORKSPACE_YAML"
}

_create_pnpm_install() {
    local project_dir="$1"
    if [[ -f "$CREATE_WORKSPACE_YAML" ]]; then
        (cd "$CREATE_PROJECTS_ROOT" && env -u CI pnpm install --no-frozen-lockfile) || return 1
    else
        (cd "$project_dir" && env -u CI pnpm install) || return 1
    fi
}

_create_apply_template_file() {
    local src="$1" dest="$2"
    if [[ ! -f "$src" ]]; then
        echo "ERROR: template missing: $src"
        return 1
    fi
    cp "$src" "$dest"
}

_create_scaffold_vite() {
    local template="$1" name="$2"
    local project_dir="$CREATE_PROJECTS_ROOT/$name"

    _create_log "Scaffolding $name ($template)..."
    if ! _create_ensure_pnpm; then
        echo "ERROR: pnpm not available."
        return 1
    fi

    (
        cd "$CREATE_PROJECTS_ROOT"
        pnpm create vite "$name" --template "$template"
    ) || {
        echo "ERROR: pnpm create vite failed."
        return 1
    }

    [[ -d "$project_dir" && -f "$project_dir/package.json" ]]
}

_create_optional_start() {
    local name="$1" do_start="$2"
    if [[ "$do_start" != "true" ]]; then
        return 0
    fi
    local project_sh="$CREATE_PROJECTS_ROOT/project.sh"
    if [[ -x "$project_sh" ]]; then
        "$project_sh" "$name" start
    else
        _create_log "WARNING: project.sh not found — skip auto-start."
    fi
}
