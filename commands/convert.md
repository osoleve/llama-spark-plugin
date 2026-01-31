---
name: convert
description: Convert a model to GGUF format
arguments: "<input> [--quant TYPE] [--name NAME] [--output PATH]"
allowed-tools:
  - Bash
  - Read
---

# /llama:convert

Convert a HuggingFace model to GGUF format and optionally quantize it.

## Usage

```
/llama:convert <input> [options]
```

## Arguments

- `input` - Path to HuggingFace model directory

## Options

- `--quant TYPE` - Quantization type (e.g., Q8_0, Q4_K_M)
- `--name NAME` - Name to register the model under
- `--output PATH` - Output file path (default: ~/models/<name>.gguf)

## Quantization Types

| Type | Size | Quality | Notes |
|------|------|---------|-------|
| Q8_0 | Large | Highest | Recommended for DGX Spark (119GB VRAM) |
| Q6_K | Medium | Very High | Good balance |
| Q5_K_M | Medium | High | K-quant medium |
| Q4_K_M | Small | Good | Popular choice for smaller systems |
| Q4_0 | Smallest | Lower | Maximum compression |

## DGX Spark Recommendation

With 119GB unified memory, prefer Q8_0 quantization for best quality.

## Instructions

Run the convert script:

```bash
~/llama-spark-plugin/scripts/llama-convert.sh $ARGUMENTS
```

The script will:
1. Convert the model to GGUF (f16) using llama.cpp's convert script
2. Quantize if `--quant` specified
3. Register the model automatically
