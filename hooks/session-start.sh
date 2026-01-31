#!/usr/bin/env bash
# Session start hook - silently check llama-server status
# Only outputs if server is running (to avoid noise)

set -euo pipefail

STATE_FILE="$HOME/.llama-server-state.json"

# Exit silently if no state file
[[ -f "$STATE_FILE" ]] || exit 0

# Read state
PID=$(jq -r '.pid // empty' "$STATE_FILE" 2>/dev/null) || exit 0
PORT=$(jq -r '.port // empty' "$STATE_FILE" 2>/dev/null) || exit 0
MODEL=$(jq -r '.model // empty' "$STATE_FILE" 2>/dev/null) || exit 0

# Exit silently if no PID
[[ -n "$PID" ]] || exit 0

# Validate server is actually running
if kill -0 "$PID" 2>/dev/null && ps -o cmd= -p "$PID" 2>/dev/null | grep -q llama-server; then
    # Server is running - output status
    cat << EOF
{
  "description": "llama-server running",
  "llama_server": {
    "status": "running",
    "pid": $PID,
    "model": "$MODEL",
    "port": $PORT,
    "endpoint": "http://127.0.0.1:$PORT"
  }
}
EOF
else
    # Stale state file - clean it up silently
    rm -f "$STATE_FILE"
fi
