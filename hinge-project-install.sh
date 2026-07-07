#!/bin/bash
# hinge-project-install.sh — bootstrap hinge-projects + hinge for Hermes
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/tsol/hinge-projects/main/hinge-project-install.sh | bash
#   bash hinge-project-install.sh [--workspace PATH] [--hinge-tag TAG] [--skip-start] [--skip-hermes-config]
#
set -o pipefail

HINGE_PROJECTS_REPO="${HINGE_PROJECTS_REPO:-https://github.com/tsol/hinge-projects.git}"
HINGE_REPO="${HINGE_REPO:-https://github.com/tsol/hinge.git}"
HINGE_TAG="${HINGE_TAG:-main}"
PROJECT_WORKSPACE="${PROJECT_WORKSPACE:-${HOME}/hermes/workspace/projects}"
HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
SKIP_START=0
SKIP_HIP=0
SKIP_HERMES_CONFIG=0

_log() { echo "[hinge-install] $*"; }
_die() { echo "[hinge-install] ERROR: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace) PROJECT_WORKSPACE="$2"; shift 2 ;;
        --hinge-tag) HINGE_TAG="$2"; shift 2 ;;
        --skip-start) SKIP_START=1; shift ;;
        --skip-hip) SKIP_HIP=1; shift ;;
        --skip-hermes-config) SKIP_HERMES_CONFIG=1; shift ;;
        -h|--help)
            sed -n '2,8p' "$0"
            exit 0
            ;;
        *) _die "Unknown option: $1" ;;
    esac
done

# Container default when HERMES_HOME is /opt/data
if [[ -d /opt/data ]] && [[ -w /opt/data ]]; then
  HERMES_HOME="/opt/data"
fi

_bootstrap_tools() {
    if ! command -v git &>/dev/null; then
        _die "git is required"
    fi
    if ! command -v pnpm &>/dev/null; then
        if command -v corepack &>/dev/null; then
            _log "Enabling pnpm via corepack..."
            corepack enable pnpm 2>/dev/null || sudo corepack enable pnpm 2>/dev/null || true
        fi
    fi
    if ! command -v pnpm &>/dev/null; then
        _die "pnpm is required (install corepack or pnpm)"
    fi
}

_clone_or_pull() {
    local url="$1" dest="$2" label="$3"
    if [[ -d "$dest/.git" ]]; then
        _log "Updating $label in $dest..."
        git -C "$dest" pull --ff-only || _die "git pull failed for $dest"
    elif [[ -d "$dest" ]]; then
        _die "$dest exists but is not a git repo"
    else
        _log "Cloning $label → $dest..."
        git clone "$url" "$dest" || _die "git clone failed for $label"
    fi
}

_checkout_hinge_tag() {
    local dir="$1" tag="$2"
    [[ "$tag" == "main" || "$tag" == "master" ]] && return 0
    _log "Checking out hinge tag/branch: $tag"
    git -C "$dir" fetch --tags origin 2>/dev/null || true
    git -C "$dir" checkout "$tag" 2>/dev/null || git -C "$dir" checkout "origin/$tag" 2>/dev/null || \
        _log "WARN: could not checkout $tag — using current branch"
}

_patch_hermes_bin() {
    local hinge_dir="$1"
    local bin=""
    if command -v hermes &>/dev/null; then
        bin="$(command -v hermes)"
    elif [[ -x /opt/hermes/.venv/bin/hermes ]]; then
        bin="/opt/hermes/.venv/bin/hermes"
    elif [[ -x "${HERMES_HOME}/.venv/bin/hermes" ]]; then
        bin="${HERMES_HOME}/.venv/bin/hermes"
    fi
    [[ -n "$bin" ]] || { _log "WARN: hermes not found — patch .hinge/*.sh manually"; return 0; }
    _log "HERMES_BIN=$bin"
    local script
    for script in new-session.sh continue-session.sh; do
        local path="$hinge_dir/.hinge/$script"
        [[ -f "$path" ]] || continue
        if grep -q '^HERMES_BIN=' "$path" 2>/dev/null; then
            sed -i "s|^HERMES_BIN=.*|HERMES_BIN=\"$bin\"|" "$path"
        elif grep -q 'hermes chat' "$path" 2>/dev/null; then
            sed -i "1a HERMES_BIN=\"$bin\"" "$path"
        fi
    done
}

_install_operational_skill() {
    [[ "$SKIP_HERMES_CONFIG" -eq 1 ]] && return 0
    local skill_file="$PROJECT_WORKSPACE/skills/hinge-projects.md"
    [[ -f "$skill_file" ]] || _die "operational skill missing: $skill_file"
    if ! command -v hermes &>/dev/null; then
        _log "WARN: hermes CLI not found — install operational skill manually:"
        _log "  hermes skills install $skill_file"
        return 0
    fi
    _log "Installing operational skill via hermes CLI..."
    hermes skills install "$skill_file" 2>&1 || {
        _log "WARN: hermes skills install failed — try manually:"
        _log "  hermes skills install https://raw.githubusercontent.com/tsol/hinge-projects/main/skills/hinge-projects.md"
        return 0
    }
    _log "Operational skill installed."
}

_install_hip() {
    local hip_src="$PROJECT_WORKSPACE/scripts/hip"
    [[ -f "$hip_src" ]] || _die "hip script missing: $hip_src"
    chmod +x "$hip_src"
    # Try ~/.local/bin first (no sudo needed), fallback to /usr/local/bin
    local hip_dest
    if mkdir -p "${HOME}/.local/bin" 2>/dev/null && [[ ":$PATH:" == *":${HOME}/.local/bin:"* ]]; then
        hip_dest="${HOME}/.local/bin/hip"
    elif [[ -d /usr/local/bin ]] && [[ -w /usr/local/bin ]]; then
        hip_dest="/usr/local/bin/hip"
    elif command -v sudo &>/dev/null; then
        hip_dest="/usr/local/bin/hip"
        sudo ln -sf "$hip_src" "$hip_dest" 2>/dev/null || { _log "WARN: could not install hip to PATH"; return 0; }
        _log "Installed hip → $hip_dest"
        return 0
    else
        _log "WARN: could not install hip to PATH — add $hip_src to your PATH manually"
        return 0
    fi
    ln -sf "$hip_src" "$hip_dest"
    _log "Installed hip → $hip_dest"
}

_main() {
    _bootstrap_tools
    mkdir -p "$(dirname "$PROJECT_WORKSPACE")"
    _clone_or_pull "$HINGE_PROJECTS_REPO" "$PROJECT_WORKSPACE" "hinge-projects"
    _clone_or_pull "$HINGE_REPO" "$PROJECT_WORKSPACE/hinge" "hinge"
    _checkout_hinge_tag "$PROJECT_WORKSPACE/hinge" "$HINGE_TAG"

    if [[ ! -f "$PROJECT_WORKSPACE/pnpm-workspace.yaml" ]] && [[ -f "$PROJECT_WORKSPACE/pnpm-workspace.yaml.example" ]]; then
        _log "Creating pnpm-workspace.yaml from example..."
        cp "$PROJECT_WORKSPACE/pnpm-workspace.yaml.example" "$PROJECT_WORKSPACE/pnpm-workspace.yaml"
    fi

    _log "Building hinge..."
    (cd "$PROJECT_WORKSPACE/hinge" && pnpm install && pnpm build) || _die "hinge build failed"

    _patch_hermes_bin "$PROJECT_WORKSPACE/hinge"
    _install_operational_skill
    [[ "$SKIP_HIP" -eq 1 ]] || _install_hip

    if [[ "$SKIP_START" -eq 1 ]]; then
        _log "Skip start (--skip-start). Run: cd $PROJECT_WORKSPACE && ./project.sh hinge start"
        exit 0
    fi

    _log "Starting hinge dev..."
    (cd "$PROJECT_WORKSPACE" && ./project.sh hinge start) || _die "project.sh hinge start failed"
    (cd "$PROJECT_WORKSPACE" && ./project.sh hinge status)
    _log "Done. Try: hip status  |  hip hinge start"
    _log "Operational skill 'hinge-projects' installed in Hermes."
    _log "Next session the agent can use: skill_view(name='hinge-projects')"
}

_main "$@"
