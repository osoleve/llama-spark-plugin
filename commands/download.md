---
name: download
description: Download a model from HuggingFace
arguments: "<repo> [--file PATTERN] [--name NAME] [--description DESC]"
allowed-tools:
  - Bash
  - Read
  - Write
---

# /llama:download

Download a GGUF model from HuggingFace Hub and register it.

## Usage

```
/llama:download <repo> [options]
```

## Arguments

- `repo` - HuggingFace repository (e.g., `TheBloke/Llama-2-7B-GGUF`)

## Options

- `--file PATTERN` - Glob pattern for which files to download (e.g., `*Q4_K_M*`)
- `--name NAME` - Name to register the model under (default: derived from repo)
- `--description DESC` - Description for the model

## Examples

```
/llama:download TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF --file "*Q4_K_M*"
/llama:download bartowski/Qwen2.5-14B-Instruct-GGUF --name qwen-14b --file "*Q8_0*"
```

## Instructions

Run the download script:

```bash
~/llama-spark-plugin/scripts/llama-download.sh $ARGUMENTS
```

The script will:
1. Download the model files from HuggingFace
2. Automatically register the model in the registry
3. Report the registry name for use with `/llama:serve`
