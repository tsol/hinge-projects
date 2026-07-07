#!/bin/bash
# project.sh - Generic Vite project lifecycle manager
# Manages dev servers + tunnels for Vite projects in the script's workspace directory
# Usage: project.sh -h | project.sh <name> start|stop|restart|status

set -o pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${PROJECT_WORKSPACE:-$SCRIPT_DIR}"
STATE_DIR="/tmp/project-state"
mkdir -p "$STATE_DIR"

# ─── Bootstrap: ensure tools ────────────────────────────────────────────────
# Corepack's "[Y/n] download pnpm?" prompt kills background dev — pre-install silently.
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

_ensure_pnpm() {
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    if command -v pnpm &>/dev/null && pnpm --version &>/dev/null; then
        return 0
    fi
    if ! command -v corepack &>/dev/null; then
        log "WARNING: corepack not found — install Node with corepack or pnpm globally."
        return 1
    fi
    log "Preparing pnpm via corepack (non-interactive)..."
    corepack enable pnpm &>/dev/null || true
    corepack prepare pnpm@latest --activate &>/dev/null \
        || corepack prepare pnpm@9 --activate &>/dev/null \
        || return 1
    pnpm --version &>/dev/null
}

_bootstrap_tools() {
    _ensure_pnpm || true
    # cloudflared via dpkg
    if ! command -v cloudflared &>/dev/null; then
        local cf_deb="/tmp/cloudflared.deb"
        curl -sL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb" -o "$cf_deb" 2>/dev/null
        sudo dpkg -i "$cf_deb" &>/dev/null || true
        rm -f "$cf_deb"
    fi
}
_bootstrap_tools

# ─── Config ──────────────────────────────────────────────────────────────────
TUNNEL_BACKEND="cloudflared"
# If unset, tries project-<name> then falls back to random
SUBDOMAIN="${SUBDOMAIN:-}"

# ─── Utilities ──────────────────────────────────────────────────────────────

log() { echo "[$(date '+%H:%M:%S')] $*"; }

_pname() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-'; }

_project_dir() { echo "$WORKSPACE/$1"; }

_state_dir() { echo "$STATE_DIR/$(_pname "$1")"; }

_pid_file() { echo "$(_state_dir "$1")/vite.pid"; }

_tpid_file() { echo "$(_state_dir "$1")/tunnel.pid"; }

_tbackend_file() { echo "$(_state_dir "$1")/tunnel.backend"; }

_port_file() { echo "$(_state_dir "$1")/port"; }

_url_file() { echo "$(_state_dir "$1")/tunnel.url"; }

_log_dir() { echo "$(_state_dir "$1")/log"; }

# ─── Port Management ────────────────────────────────────────────────────────

_find_port() {
    local name="$1" base=5174 max_attempts=50
    # Reuse previously assigned port when free OR reclaim after orphan kill
    if [[ -f "$(_port_file "$name")" ]]; then
        local stored; stored=$(cat "$(_port_file "$name")")
        if ! _port_listening "$stored"; then
            echo "$stored"
            return 0
        fi
        if ! _pid_running "$(_pid_file "$name")"; then
            log "Port $stored busy but vite pid stale — reclaiming for $name"
            _kill_port "$stored"
            sleep 1
            if ! _port_listening "$stored"; then
                echo "$stored"
                return 0
            fi
        fi
    fi
    # Scan for a free port
    for ((i=0; i<max_attempts; i++)); do
        local candidate=$((base + i))
        if ! _port_listening "$candidate"; then
            mkdir -p "$(_state_dir "$name")"
            echo "$candidate" > "$(_port_file "$name")"
            echo "$candidate"
            return 0
        fi
    done
    echo ""
    return 1
}

_port_listening() {
    local port="$1"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 1 "http://localhost:$port" 2>/dev/null)
    # "000" means connection refused / no server
    [[ "$code" =~ ^[0-9]{3}$ ]] && [ "$code" != "000" ]
}

# Kill whatever holds a TCP port (orphan vite after failed restart)
_kill_port() {
    local port="$1"
    [[ -z "$port" ]] && return 0
    if command -v fuser &>/dev/null; then
        fuser -k "${port}/tcp" 2>/dev/null || true
    fi
    if command -v lsof &>/dev/null; then
        local pids
        pids=$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            kill $pids 2>/dev/null || true
            sleep 0.5
            kill -9 $pids 2>/dev/null || true
        fi
    fi
}

# Hinge dev: API must return JSON on same port as Vite (middleware, not separate port)
_hinge_api_ok() {
    local port="$1"
    local body
    body=$(curl -s --connect-timeout 2 "http://127.0.0.1:$port/hinge-api/status" 2>/dev/null || true)
    [[ "${body:0:1}" == "{" ]]
}

_kill_vite_for_project() {
    local name="$1" dir="$2"
    _clean_stale_pid "$(_pid_file "$name")"
    pkill -f "vite.*$dir" 2>/dev/null || true
    pkill -f "vite --config.*$dir" 2>/dev/null || true
    pkill -f "node.*$dir.*vite" 2>/dev/null || true
    if [[ -f "$(_port_file "$name")" ]]; then
        local port; port=$(cat "$(_port_file "$name")" 2>/dev/null)
        _kill_port "$port"
    fi
}

# Orphan Vites on alternate bind-mount paths (docker /opt vs host /home) share .hinge
# and steal the queue — kill every hinge vite except the canonical pid we keep.
_kill_orphan_hinge_vites() {
    local keep_pid="${1:-}"
    local dir="$2"
    local base; base=$(basename "$dir")
    local alt
    for alt in "$dir" "$WORKSPACE/$base"; do
        [[ -d "$alt" ]] || continue
        pkill -f "vite.*$alt" 2>/dev/null || true
        pkill -f "vite.dev.config.*$alt" 2>/dev/null || true
        pkill -f "node.*$alt.*vite" 2>/dev/null || true
    done
    if command -v ps &>/dev/null; then
        while read -r opid; do
            [[ -z "$opid" || "$opid" == "$keep_pid" ]] && continue
            kill "$opid" 2>/dev/null || true
        done < <(ps -eo pid=,args= 2>/dev/null | grep -E '[v]ite' | grep -E 'hinge|vite\.dev\.config' | awk '{print $1}' || true)
    fi
}

# Detect package manager from the project directory only (no parent workspace coupling)
_detect_pm() {
    local dir="$1"
    if [[ -f "$dir/pnpm-lock.yaml" ]]; then
        echo "pnpm"
    elif [[ -f "$dir/yarn.lock" ]]; then
        echo "yarn"
    elif [[ -f "$dir/package-lock.json" ]]; then
        echo "npm"
    elif [[ -f "$dir/package.json" ]] && command -v pnpm &>/dev/null; then
        echo "pnpm"
    else
        echo "npm"
    fi
}

# Resolve vite entrypoint inside a single project (handles pnpm .bin shell wrappers)
_resolve_vite_launcher() {
    local dir="$1"
    local vite_js="$dir/node_modules/vite/bin/vite.js"
    if [[ -f "$vite_js" ]]; then
        printf 'node:%s\n' "$vite_js"
        return 0
    fi
    if [[ -x "$dir/node_modules/.bin/vite" ]]; then
        printf 'exec:%s\n' "$dir/node_modules/.bin/vite"
        return 0
    fi
    return 1
}

# After pnpm/npm spawn a wrapper, track the real node/vite child PID
_sync_vite_pid() {
    local dir="$1" wrapper_pid="$2" pid_file="$3"
    local child base
    base=$(basename "$dir")
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if [[ -n "$wrapper_pid" ]] && kill -0 "$wrapper_pid" 2>/dev/null; then
            child=$(pgrep -P "$wrapper_pid" 2>/dev/null | head -1)
            if [[ -n "$child" ]] && kill -0 "$child" 2>/dev/null; then
                echo "$child" > "$pid_file"
                return 0
            fi
        fi
        child=$(pgrep -f "node.*vite.*$base" 2>/dev/null | head -1)
        if [[ -n "$child" ]] && kill -0 "$child" 2>/dev/null; then
            echo "$child" > "$pid_file"
            return 0
        fi
        sleep 0.3
    done
    return 1
}

# Start Vite dev server (prefer local node_modules — avoids corepack prompts in background)
_start_vite_dev() {
    local name="$1" dir="$2" port="$3" pm="$4" vite_pid_file="$5"
    local log_file="$(_log_dir "$name")/vite.log"
    local launcher="" config_args=()

    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    export CI=1

    mkdir -p "$(_log_dir "$name")"
    : > "$log_file"

    if [[ -f "$dir/vite.dev.config.ts" ]]; then
        config_args=(--config vite.dev.config.ts)
    elif [[ -f "$dir/vite.dev.config.js" ]]; then
        config_args=(--config vite.dev.config.js)
    fi

    cd "$dir"

    launcher=$(_resolve_vite_launcher "$dir" 2>/dev/null || true)

    if [[ "$launcher" == node:* ]]; then
        local vite_js="${launcher#node:}"
        node "$vite_js" "${config_args[@]}" --port "$port" --host 0.0.0.0 >>"$log_file" 2>&1 </dev/null &
    elif [[ "$launcher" == exec:* ]]; then
        local vite_bin="${launcher#exec:}"
        "$vite_bin" "${config_args[@]}" --port "$port" --host 0.0.0.0 >>"$log_file" 2>&1 </dev/null &
    elif [[ "$pm" == "pnpm" ]]; then
        _ensure_pnpm || {
            log "ERROR: pnpm not available. Run: corepack enable pnpm && corepack prepare pnpm@latest --activate"
            return 1
        }
        pnpm run dev -- --port "$port" --host 0.0.0.0 >>"$log_file" 2>&1 </dev/null &
    else
        $pm run dev -- --port "$port" --host 0.0.0.0 >>"$log_file" 2>&1 </dev/null &
    fi

    local wrapper_pid=$!
    echo "$wrapper_pid" > "$vite_pid_file"
    disown "$wrapper_pid" 2>/dev/null

    if [[ "$launcher" != node:* && "$launcher" != exec:* ]]; then
        _sync_vite_pid "$dir" "$wrapper_pid" "$vite_pid_file" || true
    fi
    return 0
}

_is_vite_project() {
    local dir="$1"
    [[ -d "$dir" ]] || return 1
    [[ -f "$dir/package.json" ]] || return 1
    ls "$dir"/vite.config.* &>/dev/null && return 0
    if grep -qi '"vite"' "$dir/package.json" 2>/dev/null; then return 0; fi
    if grep -qi '"dev".*vite' "$dir/package.json" 2>/dev/null; then return 0; fi
    return 1
}

_project_name_from_dir() {
    local dir="$1"
    local name; name=$(basename "$dir")
    local json_name
    json_name=$(grep -m1 '"name"' "$dir/package.json" 2>/dev/null | sed 's/.*"name": *"\([^"]*\)".*/\1/')
    echo "${json_name:-$name}"
}

# Dirs that are infra, not user Vite apps (excluded from scan/create collision checks)
_INFRA_DIRS=(node_modules skills scripts templates)

_is_infra_dir() {
    local name="$1"
    [[ "$name" == .* ]] && return 0
    local d
    for d in "${_INFRA_DIRS[@]}"; do
        [[ "$name" == "$d" ]] && return 0
    done
    return 1
}

_find_projects() {
    local results=()
    for dir in "$WORKSPACE"/*/; do
        local bname; bname=$(basename "${dir%/}")
        _is_infra_dir "$bname" && continue
        if _is_vite_project "$dir"; then
            results+=("$bname")
        fi
    done
    printf '%s\n' "${results[@]}"
}

# ─── Process Management ─────────────────────────────────────────────────────

_pid_running() {
    local pid_file="$1"
    if [[ -f "$pid_file" ]]; then
        local pid; pid=$(cat "$pid_file" 2>/dev/null)
        [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && return 0
    fi
    return 1
}

_clean_stale_pid() {
    local f="$1"
    if [[ -f "$f" ]]; then
        local pid; pid=$(cat "$f" 2>/dev/null)
        if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null || true
            sleep 1
            kill -9 "$pid" 2>/dev/null || true
        fi
        rm -f "$f"
    fi
}

# ─── Vite Config Patcher ──────────────────────────────────────────────────

# Ensure the project's vite config allows .trycloudflare.com hosts
_patch_vite_allowed_hosts() {
    local dir="$1"
    local config_file
    # Find vite config
    for f in "$dir/vite.config.js" "$dir/vite.config.ts" "$dir/vite.config.mjs" "$dir/vite.config.mts"; do
        [[ -f "$f" ]] && { config_file="$f"; break; }
    done
    [[ -z "$config_file" ]] && return 0

    # Check if already configured
    if grep -q 'trycloudflare' "$config_file" 2>/dev/null; then
        return 0  # already has tunnel wildcards
    fi
    if grep -q 'allowedHosts.*true' "$config_file" 2>/dev/null; then
        return 0  # all hosts already allowed
    fi

    # Patch: add tunnel wildcards
    if grep -q 'allowedHosts:' "$config_file" 2>/dev/null; then
        # Insert before the closing bracket
        perl -i -pe 's/(allowedHosts:\s*\[[^\]]*)\]/$1, ".trycloudflare.com"]/' "$config_file"
    else
        sed -i '/server: {/a\    allowedHosts: [".trycloudflare.com"],' "$config_file"
    fi
    log "Patched $config_file to allow tunnel hosts."
}

_start_tunnel_cloudflared() {
    local name="$1" port="$2"
    local log_file="$(_log_dir "$name")/tunnel.log"
    local url_file="$(_url_file "$name")"

    log "Starting cloudflared tunnel..."
    cloudflared tunnel --url "http://localhost:$port" > "$log_file" 2>&1 &
    local tpid=$!
    echo "$tpid" > "$(_tpid_file "$name")"
    echo "cloudflared" > "$(_tbackend_file "$name")"
    disown "$tpid" 2>/dev/null

    # Wait for URL in log
    local tunnel_url=""
    for i in {1..16}; do
        sleep 2
        tunnel_url=$(grep -oP 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$log_file" 2>/dev/null | head -1)
        if [[ -n "$tunnel_url" ]]; then
            echo "$tunnel_url" > "$url_file"
            log "Cloudflared: $tunnel_url"
            # Wait for tunnel to actually respond (up to 10s)
            for j in {1..5}; do
                local resp
                resp=$(curl -sL --max-time 2 "$tunnel_url" 2>/dev/null)
                if [[ -z "$resp" ]] || echo "$resp" | grep -qi "error 1033\|error 1034\|cloudflare.*error\|tunnel error"; then
                    sleep 2
                else
                    break
                fi
            done
            return 0
        fi
        if ! kill -0 "$tpid" 2>/dev/null; then
            log "WARNING: cloudflared exited prematurely."
            tail -5 "$log_file" | sed 's/^/  | /'
            return 1
        fi
    done
    log "WARNING: cloudflared running but URL not yet in log."
    return 0
}

_stop_tunnel() {
    local name="$1"

    _clean_stale_pid "$(_tpid_file "$name")"
    # Kill only the tunnel for this project (by PID file or port match)
    local port_file="$(_port_file "$name")"
    if [[ -f "$port_file" ]]; then
        local port; port=$(cat "$port_file" 2>/dev/null)
        if [[ -n "$port" ]]; then
            pkill -f "cloudflared tunnel --url http://localhost:${port}" 2>/dev/null || true
        fi
    fi
}

# ─── Site health check ───────────────────────────────────────────────────────

_check_site_health() {
    local url="$1"
    local name="$2"
    local cache_file="$(_state_dir "$name")/health.cache"
    local cache_meta="$(_state_dir "$name")/health.meta"
    local cache_ttl=10  # seconds

    # Use cached result if fresh
    if [[ -f "$cache_file" ]]; then
        local cached_at; cached_at=$(stat -c %Y "$cache_file" 2>/dev/null || echo 0)
        local now; now=$(date +%s)
        if (( now - cached_at < cache_ttl )); then
            local age=$((now - cached_at))
            local result; result=$(cat "$cache_file")
            echo "${result} (${age}s ago)"
            return
        fi
    fi

    local result="unknown"

    if [[ -z "$url" || "$url" == "-" ]]; then
        echo "$result"
        return
    fi

    # Fetch the page (quick, timeout 5s)
    local body
    body=$(curl -sL --max-time 5 "$url" 2>/dev/null)

    if [[ -z "$body" ]]; then
        result="error (no response)"
    elif echo "$body" | grep -qi "error 1033\|error 1034\|cloudflare.*error\|tunnel error\|bad gateway\|502\|503"; then
        result="❌ error"
    elif echo "$body" | grep -qi "error"; then
        result="⚠️  errors"
    else
        result="✅ ok"
    fi

    mkdir -p "$(_state_dir "$name")"
    echo "$result" > "$cache_file"
    echo "$(date +%s)" > "$cache_meta"
    local age=0
    echo "${result} (${age}s ago)"
}

# ─── Tunnel detection for status ────────────────────────────────────────────

_tunnel_is_running() {
    local name="$1"
    local tpid_file="$(_tpid_file "$name")"

    if _pid_running "$tpid_file"; then
        return 0
    fi

    # cloudflared cmd uses localhost:PORT — not project name
    if [[ -f "$(_port_file "$name")" ]]; then
        local port; port=$(cat "$(_port_file "$name")" 2>/dev/null)
        if [[ -n "$port" ]] && pgrep -f "cloudflared tunnel --url http://localhost:${port}" &>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# True when an existing cloudflared forwards to the given vite port
_tunnel_points_to_port() {
    local name="$1" port="$2"
    [[ -z "$port" ]] && return 1

    if _pid_running "$(_tpid_file "$name")"; then
        local pid; pid=$(cat "$(_tpid_file "$name")" 2>/dev/null)
        if [[ -n "$pid" ]] && tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q "localhost:${port}"; then
            return 0
        fi
    fi

    pgrep -f "cloudflared tunnel --url http://localhost:${port}" &>/dev/null
}

# Sync tunnel pid file from a live cloudflared on the expected port
_tunnel_sync_pid() {
    local name="$1" port="$2"
    local tpid
    tpid=$(pgrep -f "cloudflared tunnel --url http://localhost:${port}" 2>/dev/null | head -1)
    if [[ -n "$tpid" ]]; then
        echo "$tpid" > "$(_tpid_file "$name")"
        echo "cloudflared" > "$(_tbackend_file "$name")"
    fi
}

_tunnel_is_healthy() {
    local name="$1"
    local url_file="$(_url_file "$name")"
    [[ -f "$url_file" ]] || return 1
    local url; url=$(cat "$url_file" 2>/dev/null)
    [[ -z "$url" ]] && return 1
    _tunnel_is_running "$name" || return 1
    return 0
}

# Start cloudflared only when missing or pointing at wrong port
_tunnel_ensure() {
    local name="$1" port="$2"

    if _tunnel_is_healthy "$name" && _tunnel_points_to_port "$name" "$port"; then
        _tunnel_sync_pid "$name" "$port"
        log "Tunnel OK — reusing $(cat "$(_url_file "$name")" 2>/dev/null)"
        return 0
    fi

    if _tunnel_is_running "$name"; then
        log "Tunnel port mismatch or stale — restarting cloudflared for localhost:$port"
    else
        log "Starting cloudflared tunnel → localhost:$port"
    fi
    _stop_tunnel "$name"
    _start_tunnel_cloudflared "$name" "$port"
}

# ─── Actions ────────────────────────────────────────────────────────────────

cmd_status() {
    local name="$1"
    local dir; dir="$(_project_dir "$name")"
    local sdir; sdir="$(_state_dir "$name")"
    local port="-" url="-"

    # Vite running?
    local vite_pid_file="$(_pid_file "$name")"
    local vite_running="no"
    if _pid_running "$vite_pid_file"; then
        vite_running="yes"
        if [[ -f "$(_port_file "$name")" ]]; then
            port=$(cat "$(_port_file "$name")" 2>/dev/null || echo "?")
        fi
    fi

    # Tunnel running?
    local tunnel_running="no"
    if _tunnel_is_running "$name"; then
        tunnel_running="yes"
        if [[ -f "$(_url_file "$name")" ]]; then
            url=$(cat "$(_url_file "$name")" 2>/dev/null)
        fi
    fi

    # Also check by pgrep (backup)
    if [[ "$vite_running" == "no" ]] && pgrep -f "vite.*$name" &>/dev/null; then
        vite_running="yes"
        local found_port; found_port=$(ps aux | grep "[v]ite.*$name" | grep -oP '(?<=--port )\d+' | head -1)
        [[ -n "$found_port" ]] && port="$found_port"
    fi

    if [[ "$vite_running" == "yes" && "$port" == "-" ]]; then
        local found_port; found_port=$(ps aux | grep "[v]ite.*$name" | grep -oP '(?<=--port )\d+' | head -1)
        [[ -n "$found_port" ]] && port="$found_port"
    fi

    # Site health check (auto-curl tunnel URL)
    local health="unknown"
    local hinge_api="n/a"
    if [[ -n "$port" && "$port" != "-" && "$vite_running" == "yes" ]]; then
        if [[ -d "$dir/.hinge" ]]; then
            if _hinge_api_ok "$port"; then
                hinge_api="ok"
            else
                hinge_api="fail (HTML or unreachable)"
            fi
        fi
    fi
    if [[ -n "$url" && "$url" != "-" ]]; then
        health=$(_check_site_health "$url" "$name")
    fi

    echo "name=$name"
    echo "display_name=$(_project_name_from_dir "$dir")"
    echo "vite=$vite_running"
    echo "port=$port"
    echo "tunnel=$tunnel_running"
    echo "url=$url"
    echo "health=$health"
    echo "hinge_api=$hinge_api"
}

cmd_stop() {
    local name="$1"
    log "Stopping $name..."

    local project_dir="$(_project_dir "$name")"
    _kill_vite_for_project "$name" "$project_dir"
    _stop_tunnel "$name"

    # Wait for port to be freed (up to 6s)
    if [[ -f "$(_port_file "$name")" ]]; then
        local port; port=$(cat "$(_port_file "$name")" 2>/dev/null)
        if [[ -n "$port" ]]; then
            for i in {1..12}; do
                if ! _port_listening "$port"; then
                    break
                fi
                sleep 0.5
            done
            if _port_listening "$port"; then
                _kill_port "$port"
                sleep 1
            fi
        fi
    fi

    rm -f "$(_pid_file "$name")" "$(_tpid_file "$name")" 2>/dev/null
    log "$name stopped."
}

cmd_start() {
    local name="$1"
    local dir; dir="$(_project_dir "$name")"

    if [[ ! -d "$dir" ]]; then
        echo "ERROR: Project directory $dir not found."
        exit 1
    fi

    local sdir; sdir="$(_state_dir "$name")"
    mkdir -p "$sdir" "$(_log_dir "$name")"

    # Find port (reuses previously assigned port)
    local port; port=$(_find_port "$name")
    if [[ -z "$port" ]]; then
        echo "ERROR: No free port available."
        exit 1
    fi

    # Detect package manager (project-local only)
    local pm; pm=$(_detect_pm "$dir")

    # ── Check if already running ──
    local vite_pid_file="$(_pid_file "$name")"
    local vite_running=false
    if _pid_running "$vite_pid_file"; then
        vite_running=true
    fi

    # If vite + tunnel are both healthy, just show status and return
    if [[ "$vite_running" == "true" ]] && _tunnel_is_healthy "$name"; then
        local skip_ok=true
        if [[ -d "$dir/.hinge" && -f "$(_port_file "$name")" ]]; then
            local check_port; check_port=$(cat "$(_port_file "$name")" 2>/dev/null)
            if [[ -n "$check_port" ]] && ! _hinge_api_ok "$check_port"; then
                log "Vite running but /hinge-api broken — forcing restart..."
                skip_ok=false
                _kill_vite_for_project "$name" "$dir"
                vite_running=false
            fi
        fi
        if [[ "$skip_ok" == "true" ]]; then
            log "$name already running (vite + tunnel healthy)."
            echo ""
            cmd_status "$name" | grep -v '^name=' | grep -v '^display_name='
            echo "────────────────────────────"
            return 0
        fi
    fi

    # ── Start/Restart Vite ──
    if [[ "$vite_running" == "true" ]]; then
        log "Restarting vite for $name..."
        _kill_vite_for_project "$name" "$dir"
        if _port_listening "$port"; then
            sleep 1
        fi
    fi

    _kill_orphan_hinge_vites "" "$dir"

    # Patch Vite config to allow tunnel hosts
    _patch_vite_allowed_hosts "$dir"

    log "Starting $name on port $port using $pm..."

    if ! _start_vite_dev "$name" "$dir" "$port" "$pm" "$vite_pid_file"; then
        exit 1
    fi

    # Wait for Vite to be ready (require live PID — ignore stale log lines)
    local ok=false log_file="$(_log_dir "$name")/vite.log"
    for i in {1..12}; do
        sleep 2
        if ! _pid_running "$vite_pid_file"; then
            continue
        fi
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port" 2>/dev/null | grep -q "200\|302\|301"; then
            ok=true
            break
        fi
        if grep -q "ready in\|Local:" "$log_file" 2>/dev/null && _pid_running "$vite_pid_file"; then
            ok=true
            break
        fi
    done

    if [[ "$ok" == "true" ]]; then
        log "Vite ready on port $port."
        local actual_port
        actual_port=$(grep -oP 'http://localhost:\K\d+' "$(_log_dir "$name")/vite.log" 2>/dev/null | head -1)
        if [[ -n "$actual_port" ]] && [[ "$actual_port" != "$port" ]]; then
            port="$actual_port"
            echo "$port" > "$(_port_file "$name")"
            log "Vite actually listening on port $port (updated)."
        fi
        if [[ -d "$dir/.hinge" ]]; then
            if _hinge_api_ok "$port"; then
                log "Hinge API OK: http://localhost:$port/hinge-api/status"
            else
                log "WARNING: /hinge-api returns HTML or unreachable on port $port — UI queue will break."
                log "         Run: project.sh $name restart   or check $(_log_dir "$name")/vite.log"
            fi
        fi
    else
        log "WARNING: Vite might not be fully ready yet. Check logs."
        tail -15 "$(_log_dir "$name")/vite.log" | sed 's/^/  | /'
        if grep -qiE 'Do you want to continue|Corepack is about to download' "$(_log_dir "$name")/vite.log" 2>/dev/null; then
            log "ERROR: Corepack blocked pnpm (needs interactive Y/n). Fixed in project.sh — retry: ./project.sh $name restart"
        fi
        _kill_vite_for_project "$name" "$dir"
        rm -f "$vite_pid_file"
    fi

    # ── Tunnel: reuse if cloudflared still forwards to this port ──
    _tunnel_ensure "$name" "$port"

    echo ""
    cmd_status "$name" | grep -v '^name=' | grep -v '^display_name='
    echo "────────────────────────────"
}

cmd_create() {
    local framework="${1:-}" name="${2:-}" extra="${3:-}"
    local create_sh="$WORKSPACE/scripts/create/create.sh"

    if [[ ! -x "$create_sh" ]]; then
        echo "ERROR: create dispatcher not found: $create_sh"
        exit 1
    fi

    if [[ -z "$framework" || "$framework" == "list" ]]; then
        "$create_sh" list
        exit 0
    fi

    if [[ -z "$name" ]]; then
        echo "ERROR: project name required."
        echo "Usage: $(basename "$0") create $framework <name> [--start]"
        exit 1
    fi

    "$create_sh" "$framework" "$name" "$extra"
}

cmd_delete() {
    local name="${1:-}" force="${2:-}"
    local dir; dir="$(_project_dir "$name")"

    if [[ -z "$name" ]]; then
        echo "ERROR: project name required."
        echo "Usage: $(basename "$0") delete <name> [--force]"
        exit 1
    fi

    case "$name" in
        hinge|node_modules|skills|scripts|templates)
            echo "ERROR: cannot delete reserved name '$name'."
            exit 1
            ;;
    esac

    if [[ ! -d "$dir" ]]; then
        echo "ERROR: project '$name' not found at $dir"
        exit 1
    fi

    if [[ "$force" != "--force" ]]; then
        echo "This will stop dev/tunnel and permanently delete:"
        echo "  $dir"
        echo "  $(_state_dir "$name")/"
        echo ""
        echo "Re-run with --force to confirm."
        exit 1
    fi

    log "Deleting $name..."
    cmd_stop "$name" 2>/dev/null || true
    rm -rf "$(_state_dir "$name")"

    if [[ -f "$WORKSPACE/pnpm-workspace.yaml" ]]; then
        sed -i "/^[[:space:]]*-[[:space:]]*'${name}'[[:space:]]*$/d" "$WORKSPACE/pnpm-workspace.yaml"
        sed -i "/^[[:space:]]*-[[:space:]]*\"${name}\"[[:space:]]*$/d" "$WORKSPACE/pnpm-workspace.yaml"
    fi

    rm -rf "$dir"
    log "Deleted $name."
}

cmd_restart() {
    local name="$1"
    local dir; dir="$(_project_dir "$name")"

    log "Restarting $name (preserving tunnel)..."
    _kill_vite_for_project "$name" "$dir"
    local port_file="$(_port_file "$name")"
    if [[ -f "$port_file" ]]; then
        local port; port=$(cat "$port_file" 2>/dev/null)
        if [[ -n "$port" ]] && _port_listening "$port"; then
            _kill_port "$port"
            sleep 1
        fi
    fi
    sleep 1
    cmd_start "$name"
}

# ─── Help ───────────────────────────────────────────────────────────────────

cmd_help() {
    local project="${1:-}"
    local self; self=$(basename "$0")
    cat <<EOF
${self} — Vite dev server + cloudflared tunnel manager

Usage:
  ${self}                              List all Vite projects in workspace
  ${self} -h | --help | help           Show this help
  ${self} <project>                    Detailed status (default)
  ${self} <project> -h                 Help for a project

  ${self} <project> start              Start dev server + tunnel
  ${self} <project> stop               Stop dev server + tunnel
  ${self} <project> restart            Restart dev (tunnel reused if same port)
  ${self} <project> status             Detailed status

  ${self} create list                  List scaffold frameworks
  ${self} create vue <name> [--start]  New Vue 3 + TS + Hinge project
  ${self} create react <name> [--start] New React + TS + Hinge project
  ${self} delete <name> [--force]      Stop and remove project directory

Examples:
  ${self} hinge
  ${self} hinge start
  ${self} hinge restart
  ${self} hinge stop
  ${self} create vue my-app --start
  ${self} delete my-app --force

Workspace:  ${WORKSPACE}  (override: PROJECT_WORKSPACE=/path)
State:      ${STATE_DIR}/<project>/
              vite.pid  tunnel.pid  port  tunnel.url
Logs:       ${STATE_DIR}/<project>/log/vite.log
              ${STATE_DIR}/<project>/log/tunnel.log
Tunnel:     cloudflared → *.trycloudflare.com

Notes:
  - One dev server per project — do not run "pnpm dev" separately on the host.
  - restart only recycles Vite; tunnel is kept when still forwarding to the same port.
  - Hinge: /hinge-api/status must return JSON on the dev port (checked on start/status).
EOF
    if [[ -n "$project" ]]; then
        local dir; dir="$(_project_dir "$project")"
        if [[ -d "$dir" ]]; then
            echo ""
            echo "Project: ${project} → ${dir}"
            if _is_vite_project "$dir"; then
                echo "Package: $(_project_name_from_dir "$dir")"
            fi
        fi
    else
        echo ""
        echo "Available projects:"
        _find_projects | sed 's/^/  - /'
    fi
}

_is_help_flag() {
    case "${1:-}" in
        -h|--help|help) return 0 ;;
        *) return 1 ;;
    esac
}

# ─── Scan Mode ────────────────────────────────────────────────────────────

scan_and_print() {
    local projects
    mapfile -t projects < <(_find_projects)

    if [[ ${#projects[@]} -eq 0 ]]; then
        echo "No Vite projects found in $WORKSPACE."
        exit 0
    fi

    for proj in "${projects[@]}"; do
        local out
        out=$(cmd_status "$proj" 2>/dev/null) || true
        local display vite port url
        display=$(echo "$out" | sed -n 's/^display_name=//p')
        vite=$(echo "$out" | sed -n 's/^vite=//p')
        port=$(echo "$out" | sed -n 's/^port=//p')
        url=$(echo "$out" | sed -n 's/^url=//p')

        [[ -z "$display" ]] && display="$proj"

        local label="$proj"
        if [[ "$display" != "$proj" ]]; then
            label="$proj ($display)"
        fi

        local dev_label
        if [[ "$vite" == "yes" ]]; then
            dev_label="✅ running"
        else
            dev_label="stopped"
        fi

        echo "$label"
        echo "  dev: $dev_label"
        if [[ -n "$url" && "$url" != "-" ]]; then
            echo "  url: $url"
        else
            echo "  url: -"
        fi
        echo ""
    done
    printf '%d project(s) found.\n' "${#projects[@]}"
}

# ─── Main ───────────────────────────────────────────────────────────────────

main() {
    local cmd="$1"

    if _is_help_flag "$cmd"; then
        cmd_help "${2:-}"
        return 0
    fi

    shift 2>/dev/null || true

    # No args → scan mode
    if [[ -z "$cmd" ]]; then
        scan_and_print
        return
    fi

    # Global create/delete (not tied to an existing project dir)
    case "$cmd" in
        create)
            cmd_create "${1:-}" "${2:-}" "${3:-}"
            return
            ;;
        delete)
            cmd_delete "${1:-}" "${2:-}"
            return
            ;;
    esac

    local project="$cmd"
    local action="${1:-status}"

    if _is_help_flag "$action"; then
        cmd_help "$project"
        return 0
    fi

    local dir; dir="$(_project_dir "$project")"
    if [[ ! -d "$dir" ]]; then
        echo "ERROR: Project '$project' not found in $WORKSPACE."
        echo "Available projects:"
        _find_projects | sed 's/^/  - /'
        echo ""
        echo "Run: $(basename "$0") -h"
        exit 1
    fi
    if ! _is_vite_project "$dir"; then
        echo "ERROR: '$project' is not a Vite project (no vite.config.* or vite dependency)."
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
            echo "$out" | while IFS='=' read -r key val; do
                case "$key" in
                    display_name) echo "  Name:        $val" ;;
                    vite)         echo "  Dev Server:  $([ "$val" == "yes" ] && echo "running" || echo "stopped")" ;;
                    port)         echo "  Port:        ${val:--}" ;;
                    tunnel)       echo "  Tunnel:      $([ "$val" == "yes" ] && echo "active" || echo "inactive")" ;;
                    url)          [[ -n "$val" && "$val" != "-" ]] && echo "  URL:         $val" ;;
                    health)       echo "  Health:      $val" ;;
                    hinge_api)    [[ "$val" != "n/a" ]] && echo "  Hinge API:   $val" ;;
                esac
            done
            if [[ -f "$(_log_dir "$project")/vite.log" ]]; then
                echo "  Recent logs:"
                tail -3 "$(_log_dir "$project")/vite.log" | sed 's/^/    | /'
            fi
            ;;
        *)
            echo "Unknown action: $action"
            echo ""
            cmd_help "$project"
            exit 1
            ;;
    esac
}

main "$@"
