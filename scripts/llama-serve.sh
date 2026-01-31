#!/usr/bin/env bash
# Start llama-server with the specified model
# Usage: llama-serve.sh <model> [--host HOST] [--port PORT] [--ctx-size N] [--gpu-layers N] [--threads N] [--no-flash-attn]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

usage() {
    echo "Usage: $(basename "$0") <model> [options]"
    echo ""
    echo "Options:"
    echo "  --host HOST       Bind address (default: 127.0.0.1)"
    echo "  --port PORT       Listen port (default: 30000)"
    echo "  --ctx-size N      Context size (default: 8192)"
    echo "  --gpu-layers N    GPU layers to offload (default: 99)"
    echo "  --threads N       CPU threads (default: 8)"
    echo "  --no-flash-attn   Disable flash attention"
    echo ""
    echo "Available models:"
    python3 "$SCRIPT_DIR/registry.py" list 2>/dev/null || echo "  (run /llama:models to see list)"
    exit 1
}

# Check if server already running (call directly to preserve globals)
get_server_status >/dev/null
if [[ -n "$SERVER_PID" ]]; then
    echo "Error: Server already running (PID $SERVER_PID, model: $SERVER_MODEL, port: $SERVER_PORT)"
    echo "Run /llama:stop first, or use /llama:status for details"
    exit 1
fi

# Parse arguments
MODEL_INPUT=""
HOST=""
PORT=""
CTX_SIZE=""
GPU_LAYERS=""
THREADS=""
FLASH_ATTN=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            HOST="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --ctx-size)
            CTX_SIZE="$2"
            shift 2
            ;;
        --gpu-layers)
            GPU_LAYERS="$2"
            shift 2
            ;;
        --threads)
            THREADS="$2"
            shift 2
            ;;
        --no-flash-attn)
            FLASH_ATTN="off"
            shift
            ;;
        --help|-h)
            usage
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            if [[ -z "$MODEL_INPUT" ]]; then
                MODEL_INPUT="$1"
            else
                echo "Unexpected argument: $1"
                usage
            fi
            shift
            ;;
    esac
done

if [[ -z "$MODEL_INPUT" ]]; then
    echo "Error: Model name required"
    usage
fi

# Resolve model name (handles aliases)
MODEL=$(resolve_model "$MODEL_INPUT") || {
    echo "Error: Unknown model '$MODEL_INPUT'"
    echo ""
    echo "Available models:"
    python3 "$SCRIPT_DIR/registry.py" list 2>/dev/null || true
    exit 1
}

# Get model path
MODEL_PATH=$(get_model_path "$MODEL") || {
    echo "Error: Could not find path for model '$MODEL'"
    exit 1
}

if [[ ! -f "$MODEL_PATH" ]]; then
    echo "Error: Model file not found: $MODEL_PATH"
    exit 1
fi

# Build parameters with precedence: CLI > model-specific > defaults
# Get model-specific settings (using jq --arg for safe interpolation)
MODEL_CTX=$(jq -r --arg name "$MODEL" '.models[$name].context_size // empty' "$CONFIG_FILE")
MODEL_GPU=$(jq -r --arg name "$MODEL" '.models[$name].gpu_layers // empty' "$CONFIG_FILE")

# Get defaults
DEFAULT_HOST=$(config_get '.defaults.host')
DEFAULT_PORT=$(config_get '.defaults.port')
DEFAULT_CTX=$(config_get '.defaults.context_size')
DEFAULT_GPU=$(config_get '.defaults.gpu_layers')
DEFAULT_THREADS=$(config_get '.defaults.threads')
DEFAULT_FLASH=$(config_get '.defaults.flash_attn')

# Apply precedence
FINAL_HOST="${HOST:-$DEFAULT_HOST}"
FINAL_PORT="${PORT:-$DEFAULT_PORT}"
FINAL_CTX="${CTX_SIZE:-${MODEL_CTX:-$DEFAULT_CTX}}"
FINAL_GPU="${GPU_LAYERS:-${MODEL_GPU:-$DEFAULT_GPU}}"
FINAL_THREADS="${THREADS:-$DEFAULT_THREADS}"

# Flash attention (default on unless explicitly disabled)
FLASH_ARGS=""
if [[ "$FLASH_ATTN" != "off" && "$DEFAULT_FLASH" == "true" ]]; then
    FLASH_ARGS="--flash-attn on"
fi

# Set up logging
LOG_FILE="$LOG_DIR/llama-server-$(date +%Y%m%d-%H%M%S).log"

# Build command
CMD_ARGS=(
    "$LLAMA_SERVER"
    --model "$MODEL_PATH"
    --host "$FINAL_HOST"
    --port "$FINAL_PORT"
    --ctx-size "$FINAL_CTX"
    --n-gpu-layers "$FINAL_GPU"
    --threads "$FINAL_THREADS"
)

if [[ -n "$FLASH_ARGS" ]]; then
    CMD_ARGS+=($FLASH_ARGS)
fi

# Store command as string for state file
CMD_STRING="${CMD_ARGS[*]}"

echo "Starting llama-server..."
echo "  Model: $MODEL ($MODEL_PATH)"
echo "  Host: $FINAL_HOST"
echo "  Port: $FINAL_PORT"
echo "  Context: $FINAL_CTX"
echo "  GPU layers: $FINAL_GPU"
echo "  Threads: $FINAL_THREADS"
echo "  Flash attention: ${FLASH_ATTN:-on}"
echo "  Log: $LOG_FILE"
echo ""

# Start server in background
"${CMD_ARGS[@]}" >> "$LOG_FILE" 2>&1 &
PID=$!

# Wait for server startup with polling (large models can take 30+ seconds to load)
echo "Waiting for server to start..."
STARTUP_TIMEOUT=60
POLL_INTERVAL=2
elapsed=0

while [[ $elapsed -lt $STARTUP_TIMEOUT ]]; do
    # Check if process died
    if ! kill -0 "$PID" 2>/dev/null; then
        echo "Error: Server process exited unexpectedly. Check log: $LOG_FILE"
        echo ""
        echo "Last 30 lines of log:"
        tail -30 "$LOG_FILE" 2>/dev/null || true
        exit 1
    fi

    # Check if port is bound (server is ready)
    if ss -tlnp 2>/dev/null | grep -q ":${FINAL_PORT}"; then
        break
    fi

    sleep $POLL_INTERVAL
    elapsed=$((elapsed + POLL_INTERVAL))
    echo "  ... still loading ($elapsed/${STARTUP_TIMEOUT}s)"
done

# Final validation
if ! validate_server_pid "$PID" "$FINAL_PORT"; then
    echo "Error: Server failed to start within ${STARTUP_TIMEOUT}s. Check log: $LOG_FILE"
    echo ""
    echo "Last 30 lines of log:"
    tail -30 "$LOG_FILE" 2>/dev/null || true
    # Kill the potentially hung process
    kill "$PID" 2>/dev/null || true
    exit 1
fi

# Write state
write_state "$PID" "$FINAL_PORT" "$MODEL" "$LOG_FILE" "$CMD_STRING"

echo "Server started successfully (PID: $PID)"
echo ""
echo "API endpoint: http://$FINAL_HOST:$FINAL_PORT"
echo "Health check: curl http://$FINAL_HOST:$FINAL_PORT/health"
