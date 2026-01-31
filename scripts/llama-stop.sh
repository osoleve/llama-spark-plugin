#!/usr/bin/env bash
# Stop the running llama-server
# Usage: llama-stop.sh [--force]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force|-f)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $(basename "$0") [--force]"
            exit 1
            ;;
    esac
done

# Get current status
status=$(get_server_status)

if [[ "$status" != "running" ]]; then
    echo "No llama-server is currently running."
    # Clean up any stale state file
    cleanup_state
    exit 0
fi

echo "Stopping llama-server..."
echo "  PID: $SERVER_PID"
echo "  Model: $SERVER_MODEL"
echo "  Port: $SERVER_PORT"

if [[ "$FORCE" == "true" ]]; then
    kill -9 "$SERVER_PID" 2>/dev/null || true
    echo "Sent SIGKILL to process"
else
    kill "$SERVER_PID" 2>/dev/null || true
    echo "Sent SIGTERM to process"

    # Wait for graceful shutdown (up to 10 seconds)
    for i in {1..10}; do
        if ! kill -0 "$SERVER_PID" 2>/dev/null; then
            break
        fi
        sleep 1
    done

    # Force kill if still running
    if kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "Process didn't terminate gracefully, sending SIGKILL..."
        kill -9 "$SERVER_PID" 2>/dev/null || true
    fi
fi

# Clean up state
cleanup_state

echo "Server stopped."
