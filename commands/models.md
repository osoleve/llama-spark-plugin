---
name: models
description: List available models in the registry
allowed-tools:
  - Bash
  - Read
---

# /llama:models

List all models registered in the llama-spark plugin.

## Instructions

Run the registry script to list models:

```bash
python3 ~/llama-spark-plugin/scripts/registry.py list
```

This will show:
- Model names and their aliases
- Descriptions
- File paths
- Whether files exist on disk
