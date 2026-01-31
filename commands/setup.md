---
name: setup
description: Set up llama.cpp on DGX Spark
allowed-tools:
  - Bash
  - Read
  - Write
---

# /llama:setup

Guide for setting up llama.cpp on NVIDIA DGX Spark.

## Prerequisites

- NVIDIA DGX Spark with Grace-Blackwell architecture
- CUDA toolkit installed
- CMake 3.14+
- Git

## Instructions

Check if llama.cpp is already installed:

```bash
if [[ -f ~/llama.cpp/build/bin/llama-server ]]; then
    echo "llama.cpp is already installed at ~/llama.cpp"
    ~/llama.cpp/build/bin/llama-server --version
else
    echo "llama.cpp not found. Installation steps:"
fi
```

### Installation Steps

If not installed, guide the user through:

1. **Clone llama.cpp**:
```bash
cd ~
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp
```

2. **Build with CUDA support** (optimized for Blackwell):
```bash
mkdir build && cd build
cmake .. -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=100
cmake --build . --config Release -j$(nproc)
```

Note: Architecture `100` is for Blackwell GPUs. Adjust if needed.

3. **Set up Python venv** (for model conversion):
```bash
cd ~/llama.cpp
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

4. **Create models directory**:
```bash
mkdir -p ~/models
```

5. **Verify installation**:
```bash
~/llama.cpp/build/bin/llama-server --version
```

## Post-Installation

After setup, run `/llama:models` to see available models, or `/llama:download` to get a model from HuggingFace.
