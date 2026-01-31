#!/usr/bin/env bash
# Common functions for llama-spark plugin scripts
# Sourced by other scripts - do not execute directly

set -euo pipefail

# Paths
LLAMA_SERVER="${LLAMA_SERVER:-$HOME/llama.cpp/build/bin/llama-server}"
CONFIG_FILE="${LLAMA_CONFIG:-$HOME/llama-spark-plugin/config/models.json}"
STATE_FILE="$HOME/.llama-server-state.json"
LOG_DIR="$HOME/.local/log/llama-server"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Read a value from the models config
# Usage: config_get '.defaults.port'
config_get() {
    local query="$1"
    jq -r "$query // empty" "$CONFIG_FILE"
}

# Read from state file
# Usage: state_get '.pid'
state_get() {
    local query="$1"
    if [[ -f "$STATE_FILE" ]]; then
        jq -r "$query // empty" "$STATE_FILE"
    fi
}

# Resolve model name (including aliases) to config key
# Usage: resolve_model "nem" -> "nemotron"
resolve_model() {
    local input="$1"

    # Check direct match first (using --arg for safe interpolation)
    if jq -e --arg name "$input" '.models[$name]' "$CONFIG_FILE" >/dev/null 2>&1; then
        echo "$input"
        return 0
    fi

    # Search aliases
    local found
    found=$(jq -r --arg alias "$input" '
        .models | to_entries[] |
        select(.value.aliases // [] | index($alias)) |
        .key
    ' "$CONFIG_FILE")

    if [[ -n "$found" ]]; then
        echo "$found"
        return 0
    fi

    return 1
}

# Get full path to model file
# Usage: get_model_path "nemotron"
get_model_path() {
    local model="$1"
    local models_dir rel_path

    models_dir=$(config_get '.models_dir')
    # Use --arg for safe interpolation
    rel_path=$(jq -r --arg name "$model" '.models[$name].path // empty' "$CONFIG_FILE")

    if [[ -z "$rel_path" ]]; then
        return 1
    fi

    # Handle absolute vs relative paths
    if [[ "$rel_path" == /* ]]; then
        echo "$rel_path"
    else
        echo "$models_dir/$rel_path"
    fi
}

# Validate that a PID is actually our llama-server
# Returns 0 if valid, 1 if stale/invalid
validate_server_pid() {
    local pid="$1"
    local expected_port="${2:-}"

    # Check PID exists
    if ! kill -0 "$pid" 2>/dev/null; then
        return 1
    fi

    # Check it's actually llama-server
    local cmd
    cmd=$(ps -o cmd= -p "$pid" 2>/dev/null || true)
    if [[ "$cmd" != *llama-server* ]]; then
        return 1
    fi

    # If port specified, verify it's bound
    if [[ -n "$expected_port" ]]; then
        if ! ss -tlnp 2>/dev/null | grep -q ":${expected_port}.*pid=$pid"; then
            # Alternative check - port might be bound but ss format varies
            if ! ss -tlnp 2>/dev/null | grep -q ":${expected_port}"; then
                return 1
            fi
        fi
    fi

    return 0
}

# Get current server status
# Outputs: running|stopped
# Sets globals: SERVER_PID, SERVER_PORT, SERVER_MODEL
get_server_status() {
    SERVER_PID=""
    SERVER_PORT=""
    SERVER_MODEL=""

    if [[ ! -f "$STATE_FILE" ]]; then
        echo "stopped"
        return
    fi

    local pid port
    pid=$(state_get '.pid')
    port=$(state_get '.port')

    if [[ -z "$pid" ]]; then
        echo "stopped"
        return
    fi

    if validate_server_pid "$pid" "$port"; then
        SERVER_PID="$pid"
        SERVER_PORT="$port"
        SERVER_MODEL=$(state_get '.model')
        echo "running"
    else
        # State file is stale - clean it up
        rm -f "$STATE_FILE"
        echo "stopped"
    fi
}

# Write state file (using jq for safe JSON generation)
# Usage: write_state pid port model log_file command
write_state() {
    local pid="$1"
    local port="$2"
    local model="$3"
    local log_file="$4"
    local cmd="$5"
    local started_at
    started_at="$(date -Iseconds)"

    jq -n \
        --argjson pid "$pid" \
        --argjson port "$port" \
        --arg model "$model" \
        --arg log_file "$log_file" \
        --arg command "$cmd" \
        --arg started_at "$started_at" \
        '{pid: $pid, port: $port, model: $model, log_file: $log_file, command: $command, started_at: $started_at}' \
        > "$STATE_FILE"
}

# Clean up state file
cleanup_state() {
    rm -f "$STATE_FILE"
}
