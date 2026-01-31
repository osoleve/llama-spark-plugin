# llama-spark Plugin for Claude Code

A comprehensive llama.cpp management plugin optimized for NVIDIA DGX Spark.

## Features

- **Server Management**: Start, stop, and monitor llama-server
- **Model Registry**: Track models with aliases and per-model settings
- **HuggingFace Integration**: Download models directly from the Hub
- **GGUF Conversion**: Convert and quantize models
- **DGX Spark Optimized**: Defaults tuned for Grace-Blackwell architecture

## Installation

**Option 1: Load directly (development/testing)**
```bash
claude --plugin-dir ~/llama-spark-plugin
```
Plugin loads for that session only. Restart Claude Code to pick up changes.

**Option 2: Install from GitHub**
```bash
# In Claude Code:
/plugin marketplace add https://github.com/osoleve/llama-spark-plugin
/plugin install llama-spark
```

**Option 3: Install from local clone**
```bash
git clone https://github.com/osoleve/llama-spark-plugin ~/llama-spark-plugin

# In Claude Code:
/plugin marketplace add ~/llama-spark-plugin
/plugin install llama-spark
```

## Commands

| Command | Description |
|---------|-------------|
| `/llama:serve [model]` | Start llama-server with a model |
| `/llama:stop` | Stop the running server |
| `/llama:status` | Show server status |
| `/llama:logs [n]` | View server logs |
| `/llama:models` | List registered models |
| `/llama:download <repo>` | Download from HuggingFace |
| `/llama:convert <path>` | Convert to GGUF |
| `/llama:setup` | Installation guide |

## Quick Start

```bash
# List available models
/llama:models

# Start a model
/llama:serve nemotron

# Check status
/llama:status

# Stop when done
/llama:stop
```

## Model Registry

Models are registered in `config/models.json`:

```json
{
  "models": {
    "nemotron": {
      "path": "nemotron3-gguf/model.gguf",
      "description": "Nemotron 3 Nano 30B",
      "aliases": ["nem", "nemotron3"]
    }
  }
}
```

### Adding Models

Models are auto-registered when using `/llama:download` or `/llama:convert`.

Manual registration:
```bash
python3 ~/llama-spark-plugin/scripts/registry.py add mymodel path/to/model.gguf --alias m
```

## Server Options

Override defaults with CLI flags:

```
/llama:serve nemotron --host 0.0.0.0 --port 8080 --ctx-size 16384
```

### Parameter Precedence

1. CLI flags (highest priority)
2. Model-specific config in registry
3. Global defaults

### Defaults (DGX Spark optimized)

- Host: `127.0.0.1` (safe default; use `--host 0.0.0.0` for network)
- Port: `30000`
- Threads: `8` (optimal for Grace CPU)
- GPU Layers: `99` (full offload)
- Context: `8192`
- Flash Attention: enabled

## State Management

Server state is tracked in `~/.llama-server-state.json`:

```json
{
  "pid": 12345,
  "port": 30000,
  "model": "nemotron",
  "log_file": "~/.local/log/llama-server/...",
  "started_at": "2024-01-15T10:30:00-05:00"
}
```

The plugin validates that the PID actually corresponds to a running llama-server before trusting state.

## Security

- **Safe network default**: Binds to `127.0.0.1` by default
- **Command injection protection**: All user inputs properly quoted
- **Silent hooks**: No output when server isn't running

## Dependencies

- `jq` - JSON processing in bash
- `python3` - Registry mutations
- `huggingface-cli` - Model downloads (from huggingface_hub)
- llama.cpp - Built at `~/llama.cpp/build/bin/`

## File Structure

```
llama-spark-plugin/
├── .claude-plugin/plugin.json  # Plugin manifest
├── commands/                    # Slash commands
├── skills/dgx-spark-llm/       # Optimization guidance
├── hooks/                       # Session start hook
├── agents/model-advisor.md     # Model selection help
├── scripts/                     # Shell/Python scripts
├── config/models.json          # Model registry
└── README.md
```
