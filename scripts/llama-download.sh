#!/usr/bin/env bash
# Download a model from HuggingFace and register it
# Usage: llama-download.sh <repo> [--file PATTERN] [--name NAME] [--description DESC]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

usage() {
    echo "Usage: $(basename "$0") <repo> [options]"
    echo ""
    echo "Download a GGUF model from HuggingFace Hub."
    echo ""
    echo "Arguments:"
    echo "  repo              HuggingFace repo (e.g., TheBloke/Llama-2-7B-GGUF)"
    echo ""
    echo "Options:"
    echo "  --file PATTERN    File pattern to download (e.g., '*Q4_K_M*')"
    echo "  --name NAME       Registry name (default: derived from repo)"
    echo "  --description D   Model description"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF --file '*Q4_K_M*'"
    echo "  $(basename "$0") bartowski/Qwen2.5-14B-Instruct-GGUF --name qwen-14b"
    exit 1
}

# Check for huggingface-cli
if ! command -v huggingface-cli &>/dev/null; then
    echo "Error: huggingface-cli not found"
    echo "Install with: pip install huggingface_hub"
    exit 1
fi

# Parse arguments
REPO=""
FILE_PATTERN=""
MODEL_NAME=""
DESCRIPTION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)
            FILE_PATTERN="$2"
            shift 2
            ;;
        --name)
            MODEL_NAME="$2"
            shift 2
            ;;
        --description)
            DESCRIPTION="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            if [[ -z "$REPO" ]]; then
                REPO="$1"
            else
                echo "Unexpected argument: $1"
                usage
            fi
            shift
            ;;
    esac
done

if [[ -z "$REPO" ]]; then
    echo "Error: Repository name required"
    usage
fi

# Derive model name from repo if not specified
if [[ -z "$MODEL_NAME" ]]; then
    # Extract name from repo (user/name -> name, strip -GGUF suffix)
    MODEL_NAME=$(echo "$REPO" | sed 's|.*/||; s/-GGUF$//i; s/-gguf$//i' | tr '[:upper:]' '[:lower:]')
fi

MODELS_DIR=$(config_get '.models_dir')
DOWNLOAD_DIR="$MODELS_DIR/$(echo "$REPO" | tr '/' '-')"

echo "Downloading from HuggingFace..."
echo "  Repository: $REPO"
echo "  Destination: $DOWNLOAD_DIR"
if [[ -n "$FILE_PATTERN" ]]; then
    echo "  File pattern: $FILE_PATTERN"
fi
echo ""

# Build download command
HF_ARGS=(huggingface-cli download "$REPO" --local-dir "$DOWNLOAD_DIR")

if [[ -n "$FILE_PATTERN" ]]; then
    HF_ARGS+=(--include "$FILE_PATTERN")
fi

# Run download
"${HF_ARGS[@]}"

# Find the downloaded GGUF file(s)
mapfile -t GGUF_FILES < <(find "$DOWNLOAD_DIR" -name "*.gguf" -type f)

if [[ ${#GGUF_FILES[@]} -eq 0 ]]; then
    echo ""
    echo "Warning: No .gguf file found in download"
    echo "Downloaded files:"
    ls -la "$DOWNLOAD_DIR"
    exit 1
fi

if [[ ${#GGUF_FILES[@]} -gt 1 ]]; then
    echo ""
    echo "Multiple GGUF files found. Please use --file to specify which one:"
    for f in "${GGUF_FILES[@]}"; do
        size=$(du -h "$f" | cut -f1)
        echo "  $size  $(basename "$f")"
    done
    echo ""
    echo "Example: $0 $REPO --file '*Q8_0*'"
    exit 1
fi

GGUF_FILE="${GGUF_FILES[0]}"

# Make path relative to models_dir for registry
REL_PATH="${GGUF_FILE#$MODELS_DIR/}"

echo ""
echo "Download complete!"
echo "  File: $GGUF_FILE"
echo ""

# Register the model
echo "Registering model as '$MODEL_NAME'..."

REG_ARGS=(python3 "$SCRIPT_DIR/registry.py" add "$MODEL_NAME" "$REL_PATH")

if [[ -n "$DESCRIPTION" ]]; then
    REG_ARGS+=(--description "$DESCRIPTION")
else
    REG_ARGS+=(--description "Downloaded from $REPO")
fi

"${REG_ARGS[@]}"

echo ""
echo "Model ready to use: /llama:serve $MODEL_NAME"
