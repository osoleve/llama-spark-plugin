#!/usr/bin/env bash
# Convert a model to GGUF format and optionally quantize
# Usage: llama-convert.sh <input> [--quant TYPE] [--name NAME] [--output PATH]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$HOME/llama.cpp}"
CONVERT_SCRIPT="$LLAMA_CPP_DIR/convert_hf_to_gguf.py"
QUANTIZE_BIN="$LLAMA_CPP_DIR/build/bin/llama-quantize"
VENV_DIR="$LLAMA_CPP_DIR/.venv"

usage() {
    echo "Usage: $(basename "$0") <input> [options]"
    echo ""
    echo "Convert a HuggingFace model to GGUF format."
    echo ""
    echo "Arguments:"
    echo "  input             Path to HF model directory or safetensors"
    echo ""
    echo "Options:"
    echo "  --quant TYPE      Quantization type (e.g., Q8_0, Q4_K_M)"
    echo "  --name NAME       Registry name (default: derived from input)"
    echo "  --output PATH     Output path (default: models_dir/<name>.gguf)"
    echo ""
    echo "Common quantization types:"
    echo "  Q8_0    - 8-bit, highest quality"
    echo "  Q6_K    - 6-bit k-quant"
    echo "  Q5_K_M  - 5-bit k-quant medium"
    echo "  Q4_K_M  - 4-bit k-quant medium (good balance)"
    echo "  Q4_0    - 4-bit, smaller but lower quality"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") ./Llama-2-7B --quant Q8_0"
    echo "  $(basename "$0") ./model-dir --quant Q4_K_M --name my-model"
    exit 1
}

# Check dependencies
if [[ ! -f "$CONVERT_SCRIPT" ]]; then
    echo "Error: convert_hf_to_gguf.py not found at $CONVERT_SCRIPT"
    echo "Make sure llama.cpp is installed at $LLAMA_CPP_DIR"
    exit 1
fi

if [[ ! -d "$VENV_DIR" ]]; then
    echo "Error: Python venv not found at $VENV_DIR"
    echo "Create it with: python3 -m venv $VENV_DIR && $VENV_DIR/bin/pip install -r $LLAMA_CPP_DIR/requirements.txt"
    exit 1
fi

# Parse arguments
INPUT=""
QUANT_TYPE=""
MODEL_NAME=""
OUTPUT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quant)
            QUANT_TYPE="$2"
            shift 2
            ;;
        --name)
            MODEL_NAME="$2"
            shift 2
            ;;
        --output)
            OUTPUT_PATH="$2"
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
            if [[ -z "$INPUT" ]]; then
                INPUT="$1"
            else
                echo "Unexpected argument: $1"
                usage
            fi
            shift
            ;;
    esac
done

if [[ -z "$INPUT" ]]; then
    echo "Error: Input path required"
    usage
fi

if [[ ! -e "$INPUT" ]]; then
    echo "Error: Input not found: $INPUT"
    exit 1
fi

# Derive model name from input if not specified
if [[ -z "$MODEL_NAME" ]]; then
    MODEL_NAME=$(basename "$INPUT" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')
fi

MODELS_DIR=$(config_get '.models_dir')

# Determine output paths
if [[ -z "$OUTPUT_PATH" ]]; then
    if [[ -n "$QUANT_TYPE" ]]; then
        OUTPUT_PATH="$MODELS_DIR/${MODEL_NAME}-${QUANT_TYPE}.gguf"
    else
        OUTPUT_PATH="$MODELS_DIR/${MODEL_NAME}-f16.gguf"
    fi
fi

# Create temp file for f16 if quantizing
if [[ -n "$QUANT_TYPE" ]]; then
    F16_PATH="$MODELS_DIR/${MODEL_NAME}-f16-temp.gguf"
    # Cleanup temp file on exit (handles interrupts, errors, etc.)
    trap 'rm -f "$F16_PATH"' EXIT
else
    F16_PATH="$OUTPUT_PATH"
fi

echo "Converting model to GGUF..."
echo "  Input: $INPUT"
echo "  Output: $OUTPUT_PATH"
if [[ -n "$QUANT_TYPE" ]]; then
    echo "  Quantization: $QUANT_TYPE"
fi
echo ""

# Activate venv and convert
echo "Step 1: Converting to GGUF (f16)..."
"$VENV_DIR/bin/python" "$CONVERT_SCRIPT" "$INPUT" --outfile "$F16_PATH"

# Quantize if requested
if [[ -n "$QUANT_TYPE" ]]; then
    if [[ ! -f "$QUANTIZE_BIN" ]]; then
        echo "Error: llama-quantize not found at $QUANTIZE_BIN"
        exit 1
    fi

    echo ""
    echo "Step 2: Quantizing to $QUANT_TYPE..."
    "$QUANTIZE_BIN" "$F16_PATH" "$OUTPUT_PATH" "$QUANT_TYPE"

    # Temp file cleanup handled by trap
fi

echo ""
echo "Conversion complete!"
echo "  Output: $OUTPUT_PATH"
echo ""

# Register the model
REL_PATH="${OUTPUT_PATH#$MODELS_DIR/}"

echo "Registering model as '$MODEL_NAME'..."
python3 "$SCRIPT_DIR/registry.py" add "$MODEL_NAME" "$REL_PATH" \
    --description "Converted from $(basename "$INPUT")"

echo ""
echo "Model ready to use: /llama:serve $MODEL_NAME"
