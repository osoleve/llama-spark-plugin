---
name: status
description: Show llama-server status
allowed-tools:
  - Bash
  - Read
---

# /llama:status

Show the current status of llama-server.

## Instructions

1. Read the state file to get current server info
2. Validate that the server is actually running (PID check + port binding)
3. If running, show health endpoint response
4. Report status to user

## Execution

First, check the state file:

```bash
cat ~/.llama-server-state.json 2>/dev/null || echo "No state file"
```

If state exists, validate the server is running:

```bash
# Check if PID exists and is llama-server
STATE_FILE="$HOME/.llama-server-state.json"
if [[ -f "$STATE_FILE" ]]; then
    PID=$(jq -r '.pid' "$STATE_FILE")
    PORT=$(jq -r '.port' "$STATE_FILE")
    MODEL=$(jq -r '.model' "$STATE_FILE")
    LOG=$(jq -r '.log_file' "$STATE_FILE")
    STARTED=$(jq -r '.started_at' "$STATE_FILE")

    # Validate PID
    if kill -0 "$PID" 2>/dev/null && ps -o cmd= -p "$PID" 2>/dev/null | grep -q llama-server; then
        echo "Status: RUNNING"
        echo "  PID: $PID"
        echo "  Model: $MODEL"
        echo "  Port: $PORT"
        echo "  Started: $STARTED"
        echo "  Log: $LOG"
        echo ""
        echo "Health check:"
        curl -s "http://127.0.0.1:$PORT/health" | jq . 2>/dev/null || echo "  (health endpoint not responding)"
    else
        echo "Status: STOPPED (stale state file)"
        rm -f "$STATE_FILE"
    fi
else
    echo "Status: STOPPED"
    echo "No llama-server is running."
fi
```
