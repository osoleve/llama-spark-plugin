---
name: stop
description: Stop the running llama-server
arguments: "[--force]"
allowed-tools:
  - Bash
  - Read
---

# /llama:stop

Stop the currently running llama-server.

## Usage

```
/llama:stop [--force]
```

## Options

- `--force` - Send SIGKILL instead of SIGTERM (use if graceful shutdown fails)

## Instructions

Run the stop script:

```bash
~/llama-spark-plugin/scripts/llama-stop.sh $ARGUMENTS
```

Report the result to the user.
