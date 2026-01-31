---
name: logs
description: View llama-server logs
arguments: "[lines]"
allowed-tools:
  - Bash
  - Read
---

# /llama:logs

View the llama-server log file.

## Usage

```
/llama:logs [lines]
```

## Arguments

- `lines` - Number of lines to show (default: 50)

## Instructions

1. Find the log file from the state file
2. Tail the specified number of lines
3. If no active log, show the most recent log file

## Execution

```bash
STATE_FILE="$HOME/.llama-server-state.json"
LINES="${1:-50}"
LOG_DIR="$HOME/.local/log/llama-server"

if [[ -f "$STATE_FILE" ]]; then
    LOG_FILE=$(jq -r '.log_file' "$STATE_FILE")
    if [[ -f "$LOG_FILE" ]]; then
        echo "=== Log: $LOG_FILE ==="
        tail -n "$LINES" "$LOG_FILE"
    else
        echo "Log file not found: $LOG_FILE"
    fi
else
    # Find most recent log
    LATEST=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
    if [[ -n "$LATEST" ]]; then
        echo "=== Most recent log: $LATEST ==="
        tail -n "$LINES" "$LATEST"
    else
        echo "No log files found in $LOG_DIR"
    fi
fi
```
