#!/bin/bash
# project.sh — Vite project lifecycle manager
# Delegates to pnpm dev:start|stop|status in each project.
# Keeps create/delete for scaffolding.
#
# Usage: project.sh -h | project.sh <name> start|stop|restart|status

set -o pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${PROJECT_WORKSPACE:-$SCRIPT_DIR}"

# ─── Bootstrap: ensure tools ────────────────────────────────────────────────
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

_ensure_pnpm() {
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    if command -v pnpm &>/dev/null && pnpm --version &>/dev/null; then return 0; fi
    if ! command -v corepack &>/dev/null; then echo "WARNING: corepack not found."; return 1; fi
    corepack enable pnpm &>/dev/null || true
    corepack prepare pnpm@latest --activate &>/dev/null || corepack prepare pnpm@9 --activate &>/dev/null || return 1
    pnpm --version &>/dev/null
}

_bootstrap_tools() {
    _ensure_pnpm || true
    if ! command -v cloudflared &>/dev/null; then
        local cf_deb="/tmp/cloudflared.deb"
        curl -sL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb" -o "$cf_deb" 2>/dev/null
        sudo dpkg -i "$cf_deb" &>/dev/null || true
        rm -f "$cf_deb"
    fi
}
_bootstrap_tools

# ─── Utilities ──────────────────────────────────────────────────────────────

log() { echo "[$(date '+%H:%M:%S')] $*"; }

_pname() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-'; }

_project_dir() { echo "$WORKSPACE/$1"; }

_is_vite_project() {
    local dir="$1"
    [[ -d "$dir" ]] || return 1
    [[ -f "$dir/package.json" ]] || return 1
    ls "$dir"/vite.config.* &>/dev/null && return 0
    if grep -qi '"vite"' "$dir/package.json" 2>/dev/null; then return 0; fi
    if grep -qi '"dev".*vite' "$dir/package.json" 2>/dev/null; then return 0; fi
    return 1
}

_INFRA_DIRS=(node_modules skills scripts templates)

_is_infra_dir() {
    local name="$1"
    [[ "$name" == .* ]] && return 0
    local d; for d in "${_INFRA_DIRS[@]}"; do [[ "$name" == "$d" ]] && return 0; done
    return 1
}

_find_projects() {
    local results=()
    for dir in "$WORKSPACE"/*/; do
        local bname; bname=$(basename "${dir%/}")
        _is_infra_dir "$bname" && continue
        if _is_vite_project "$dir"; then results+=("$bname"); fi
    done
    printf '%s\n' "${results[@]}"
}

_project_name_from_dir() {
    local dir="$1"
    local name; name=$(basename "$dir")
    local json_name; json_name=$(grep -m1 '"name"' "$dir/package.json" 2>/dev/null | sed 's/.*"name": *"\([^"]*\)".*/\1/')
    echo "${json_name:-$name}"
}

# ─── Help ───────────────────────────────────────────────────────────────────

cmd_help() {
    local topic="${1:-}"
    if [[ -z "$topic" ]]; then
        cat <<EOF
project.sh — Vite dev server + tunnel manager

Usage:
  project.sh                              List projects
  project.sh -h | --help | help           Show this help
  project.sh <project>                    Detailed status (default)
  project.sh <project> -h                 Help for a project

  project.sh <project> start              Start dev server + tunnel
  project.sh <project> stop               Stop everything
  project.sh <project> restart            Stop + start
  project.sh <project> status             Detailed status

  project.sh create list                  List scaffold frameworks
  project.sh create vue <name> [--start]  New Vue 3 + TS + Hinge project
  project.sh create react <name> [--start] New React + TS + Hinge project
  project.sh delete <name> [--force]      Stop and remove project directory

Examples:
  project.sh hinge
  project.sh hinge start
  project.sh hinge stop
  project.sh hinge restart
  project.sh create vue my-app --start
  project.sh delete my-app --force

Workspace:  $WORKSPACE  (override: PROJECT_WORKSPACE=/path)
Tunnel:     cloudflared → *.trycloudflare.com

Projects delegate lifecycle to each project's own pnpm dev:* scripts.
EOF
    else
        local dir; dir="$(_project_dir "$topic")"
        if [[ -d "$dir" ]]; then
            grep -A2 '"dev:' "$dir/package.json" 2>/dev/null | sed 's/^/  /'
        fi
    fi
}

_is_help_flag() { [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; }

# ─── Scan (no args) ──────────────────────────────────────────────────────────

scan_and_print() {
    local projects
    projects=$(_find_projects)
    if [[ -z "$projects" ]]; then
        echo "No Vite projects found in $WORKSPACE"
        echo "Create one: project.sh create vue <name>"
        return
    fi
    echo "$projects"
}

# ─── Status ──────────────────────────────────────────────────────────────────

cmd_status() {
    local name="$1"
    local dir; dir="$(_project_dir "$name")"
    cd "$dir" && pnpm dev:status 2>/dev/null || echo "status=stopped"
}

# ─── Start ───────────────────────────────────────────────────────────────────

cmd_start() {
    local name="$1"
    local dir; dir="$(_project_dir "$name")"

    if [[ ! -d "$dir" ]]; then echo "ERROR: Project directory $dir not found."; exit 1; fi
    if ! _is_vite_project "$dir"; then echo "ERROR: '$name' is not a Vite project."; exit 1; fi

    # Check if already running
    local status_out
    status_out=$(cd "$dir" && pnpm dev:status 2>/dev/null || true)
    local vite_alive; vite_alive=$(echo "$status_out" | grep '^vite=' | cut -d= -f2)
    if [[ "$vite_alive" == "yes" ]]; then
        log "$name already running."
        local url; url=$(echo "$status_out" | grep '^url=' | cut -d= -f2-)
        local port; port=$(echo "$status_out" | grep '^port=' | cut -d= -f2)
        echo "  Port: ${port:--}"
        [[ -n "$url" && "$url" != "-" ]] && echo "  URL:  $url"
        echo "────────────────────────────"
        return 0
    fi

    # Start dev:start in background
    log "Starting $name..."
    cd "$dir" && mkdir -p "$dir/.dev" && nohup pnpm dev:start > "$dir/.dev/start.log" 2>&1 &
    local bg_pid=$!

    # Wait for .dev/pids.json (up to 20s)
    local url="" port="" waited=0
    while [[ $waited -lt 20 ]]; do
        if [[ -f "$dir/.dev/pids.json" ]]; then
            local state; state=$(cat "$dir/.dev/pids.json" 2>/dev/null || echo "")
            if [[ -n "$state" ]]; then
                url=$(echo "$state" | python3 -c "import sys,json; print(json.load(sys.stdin).get('url','-'))" 2>/dev/null || echo "")
                port=$(echo "$state" | python3 -c "import sys,json; print(json.load(sys.stdin).get('port','-'))" 2>/dev/null || echo "")
                break
            fi
        fi
        sleep 1
        waited=$((waited + 1))
    done

    if [[ -n "$url" && "$url" != "-" ]]; then
        log "Ready: $url"
        echo "  Port: $port"
        echo "  URL:  $url"
    elif kill -0 "$bg_pid" 2>/dev/null; then
        log "Vite starting... (timeout waiting for .dev/pids.json)"
        echo "  PID: $bg_pid"
    else
        log "ERROR: dev:start exited prematurely."
        [[ -f "$dir/.dev/start.log" ]] && tail -5 "$dir/.dev/start.log" | sed 's/^/  | /'
        exit 1
    fi
    echo "────────────────────────────"
}

# ─── Stop ────────────────────────────────────────────────────────────────────

cmd_stop() {
    local name="$1"
    local dir; dir="$(_project_dir "$name")"

    if [[ ! -d "$dir" ]]; then echo "ERROR: Project directory $dir not found."; exit 1; fi

    log "Stopping $name..."
    cd "$dir" && pnpm dev:stop
    log "$name stopped."
}

# ─── Restart (preserve tunnel) ───────────────────────────────────────────────

cmd_restart() {
    local name="$1"
    local dir; dir="$(_project_dir "$name")"

    if [[ ! -d "$dir" ]]; then echo "ERROR: Project directory $dir not found."; exit 1; fi

    local pids_json="$dir/.dev/pids.json"
    if [[ ! -f "$pids_json" ]]; then
        # Not running — just start
        echo ""
        cmd_start "$name"
        return
    fi

    # Read current state
    local state; state=$(cat "$pids_json" 2>/dev/null || echo "{}")
    local vite_pid tunnel_pid bot_pid url port
    vite_pid=$(echo "$state" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pid',{}).get('vite',''))" 2>/dev/null || echo "")
    tunnel_pid=$(echo "$state" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pid',{}).get('cloudflared',''))" 2>/dev/null || echo "")
    bot_pid=$(echo "$state" | python3 -c "import sys,json; print(json.load(sys.stdin).get('pid',{}).get('bot',''))" 2>/dev/null || echo "")
    url=$(echo "$state" | python3 -c "import sys,json; print(json.load(sys.stdin).get('url',''))" 2>/dev/null || echo "")
    port=$(echo "$state" | python3 -c "import sys,json; print(json.load(sys.stdin).get('port',''))" 2>/dev/null || echo "")

    # Kill bot + vite, keep tunnel
    log "Restarting $name (preserving tunnel)..."
    [[ -n "$bot_pid" ]] && kill "$bot_pid" 2>/dev/null && log "Killed bot (pid $bot_pid)" || true
    [[ -n "$vite_pid" ]] && kill "$vite_pid" 2>/dev/null && log "Killed vite (pid $vite_pid)" || true

    # Start vite + bot (no tunnel)
    cd "$dir" && mkdir -p "$dir/.dev" && nohup pnpm dev:start --no-tunnel > "$dir/.dev/start.log" 2>&1 &
    local bg_pid=$!

    # Wait for new pids.json (up to 20s)
    local waited=0 new_url=""
    while [[ $waited -lt 20 ]]; do
        if [[ -f "$pids_json" ]]; then
            local new_state; new_state=$(cat "$pids_json" 2>/dev/null || echo "")
            if [[ -n "$new_state" ]]; then
                new_url=$(echo "$new_state" | python3 -c "import sys,json; print(json.load(sys.stdin).get('url','-'))" 2>/dev/null || echo "")
                break
            fi
        fi
        sleep 1
        waited=$((waited + 1))
    done

    # Restore the original tunnel URL (dev-start may have created a new one)
    local final_url
    if [[ -n "$new_url" && "$new_url" != "-" ]]; then
        final_url="$new_url"
    elif [[ -n "$url" ]]; then
        final_url="$url"
    fi

    if [[ -n "$final_url" ]]; then
        log "Ready: $final_url"
        echo "  Port: ${port:--}"
        echo "  URL:  $final_url"
    elif kill -0 "$bg_pid" 2>/dev/null; then
        log "Starting... (timeout waiting for .dev/pids.json)"
        echo "  PID: $bg_pid"
    else
        log "ERROR: dev:start exited prematurely."
        [[ -f "$dir/.dev/start.log" ]] && tail -5 "$dir/.dev/start.log" | sed 's/^/  | /'
        exit 1
    fi
    echo "────────────────────────────"
}

# ─── Create ──────────────────────────────────────────────────────────────────

cmd_create() {
    local framework="${1:-}" name="${2:-}" extra="${3:-}"
    local create_sh="$WORKSPACE/scripts/create/create.sh"

    if [[ ! -x "$create_sh" ]]; then echo "ERROR: create dispatcher not found: $create_sh"; exit 1; fi

    if [[ -z "$framework" || "$framework" == "list" ]]; then "$create_sh" list; exit 0; fi

    if [[ -z "$name" ]]; then echo "ERROR: project name required."; exit 1; fi

    # Call create, then inject dev:* scripts into the new project
    "$create_sh" "$framework" "$name" "$extra"

    # Copy dev-start/stop/status scripts from template
    local project_dir="$WORKSPACE/$name"
    if [[ -d "$project_dir" ]]; then
        mkdir -p "$project_dir/scripts"
        for f in dev-start.mjs dev-stop.mjs dev-status.mjs; do
            local template_script="$WORKSPACE/templates/$framework-hinge/scripts/$f"
            local shared_script="$WORKSPACE/scripts/$f"
            if [[ -f "$template_script" ]]; then
                cp "$template_script" "$project_dir/scripts/$f"
            elif [[ -f "$shared_script" ]]; then
                # Use shared template as fallback
                cp "$shared_script" "$project_dir/scripts/$f"
            fi
        done
        chmod +x "$project_dir/scripts/"*.mjs 2>/dev/null

        # Add dev:* scripts to package.json
        node -e "
const fs = require('fs');
const p = '$project_dir/package.json';
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
pkg.scripts = pkg.scripts || {};
pkg.scripts['dev:start'] = 'node scripts/dev-start.mjs';
pkg.scripts['dev:stop'] = 'node scripts/dev-stop.mjs';
pkg.scripts['dev:status'] = 'node scripts/dev-status.mjs';
fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
"
    fi
}

# ─── Delete ──────────────────────────────────────────────────────────────────

cmd_delete() {
    local name="${1:-}" force="${2:-}"
    local dir; dir="$(_project_dir "$name")"

    if [[ -z "$name" ]]; then echo "ERROR: project name required."; exit 1; fi

    case "$name" in
        hinge|node_modules|skills|scripts|templates)
            echo "ERROR: cannot delete reserved name '$name'."; exit 1 ;;
    esac

    if [[ ! -d "$dir" ]]; then echo "ERROR: project '$name' not found."; exit 1; fi

    # Stop first
    if _is_vite_project "$dir"; then
        cmd_stop "$name" 2>/dev/null || true
    fi

    if [[ "$force" != "--force" ]]; then
        echo "WARNING: This will permanently delete '$name' and all its files."
        echo "  Path: $dir"
        read -rp "Type 'yes' to confirm: " confirm
        if [[ "$confirm" != "yes" ]]; then echo "Cancelled."; exit 0; fi
    fi

    # Remove from pnpm-workspace.yaml
    local ws_yaml="$WORKSPACE/pnpm-workspace.yaml"
    if [[ -f "$ws_yaml" ]]; then
        sed -i "/^[[:space:]]*-[[:space:]]*'${name}'[[:space:]]*$/d" "$ws_yaml" 2>/dev/null || true
        sed -i "/^[[:space:]]*-[[:space:]]*\"${name}\"[[:space:]]*$/d" "$ws_yaml" 2>/dev/null || true
    fi

    rm -rf "$dir"
    echo "Deleted '$name'."
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    local cmd="${1:-}"

    _is_help_flag "$cmd" && { cmd_help "${2:-}"; return 0; }
    shift 2>/dev/null || true

    # No args → scan
    if [[ -z "$cmd" ]]; then scan_and_print; return; fi

    # Global commands
    case "$cmd" in
        create) cmd_create "${1:-}" "${2:-}" "${3:-}"; return ;;
        delete) cmd_delete "${1:-}" "${2:-}"; return ;;
    esac

    # Project commands
    local project="$cmd"
    local action="${1:-status}"

    _is_help_flag "$action" && { cmd_help "$project"; return 0; }

    local dir; dir="$(_project_dir "$project")"
    if [[ ! -d "$dir" ]]; then
        echo "ERROR: Project '$project' not found in $WORKSPACE."
        echo "Available projects:"
        _find_projects | sed 's/^/  - /'
        echo ""; echo "Run: $(basename "$0") -h"; exit 1
    fi
    if ! _is_vite_project "$dir"; then
        echo "ERROR: '$project' is not a Vite project."
        exit 1
    fi

    case "$action" in
        start)
            cmd_start "$project"
            ;;
        stop)
            cmd_stop "$project"
            ;;
        restart)
            cmd_restart "$project"
            ;;
        status|stat)
            echo "── $project ──────────────────────────"
            local out; out=$(cmd_status "$project")
            local status port url vite tunnel hinge_api
            while IFS='=' read -r key val; do
                case "$key" in
                    status)      status="$val" ;;
                    vite)        vite="$val" ;;
                    tunnel)      tunnel="$val" ;;
                    port)        port="$val" ;;
                    url)         url="$val" ;;
                    health)      echo "  Health:      $val" ;;
                    hinge_api)   [[ "$val" != "n/a" ]] && echo "  Hinge API:   $val" ;;
                    started_at)  ;;
                esac
            done <<< "$out"
            echo "  Name:        $(_project_name_from_dir "$dir")"
            echo "  Dev Server:  $([ "$vite" == "yes" ] && echo "running" || echo "stopped")"
            echo "  Port:        ${port:--}"
            echo "  Tunnel:      $([ "$tunnel" == "yes" ] && echo "active" || echo "inactive")"
            [[ -n "$url" && "$url" != "-" ]] && echo "  URL:         $url"
            echo "────────────────────────────"
            ;;
        *)
            echo "Unknown action: $action"
            echo ""; cmd_help "$project"; exit 1
            ;;
    esac
}

main "$@"
