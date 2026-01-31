---
name: dgx-spark-llm
description: DGX Spark LLM optimization guidance and best practices
---

# DGX Spark LLM Optimization

Guidance for running LLMs optimally on NVIDIA DGX Spark (Grace-Blackwell architecture).

## Hardware Overview

- **CPU**: Grace ARM64 (72 cores)
- **GPU**: Blackwell GPU
- **Memory**: 119GB unified memory (GPU can access system RAM)
- **Architecture**: GB10 (ARM + Blackwell unified)

## Optimal llama.cpp Settings

### GPU Offloading
```
-ngl 99  # Full GPU offload (all layers)
```

With 119GB unified memory, most models fit entirely in GPU memory.

### CPU Threads
```
--threads 8
```

Grace CPU benefits from moderate thread count. Higher isn't always better due to memory bandwidth.

### Flash Attention
```
--flash-attn
```

Blackwell supports flash attention natively. Always enable for better memory efficiency.

### Context Size

For large models (30B+):
- Start with 8192 context
- Increase to 16384 or 32768 if needed
- Monitor memory usage with `/llama:status`

## Quantization Recommendations

With 119GB VRAM, prefer higher quality quantizations:

| Model Size | Recommended Quant | Reasoning |
|------------|-------------------|-----------|
| 7B | Q8_0 or F16 | Fits easily, maximize quality |
| 13B | Q8_0 | Still fits with room to spare |
| 30B | Q8_0 | Fits in 119GB |
| 70B | Q6_K or Q5_K_M | May need lower quant |

## Model Selection

For the DGX Spark's capabilities:

### Coding Tasks
- Qwen2.5-Coder-32B (Q8_0)
- DeepSeek-Coder-33B (Q8_0)
- CodeLlama-34B (Q8_0)

### General Reasoning
- Nemotron-3-Nano-30B (MoE, excellent for reasoning)
- Qwen2.5-32B-Instruct
- Llama-3.1-70B (Q5_K_M)

### Fast Inference
- GLM-4.7-Flash
- Llama-3.2-3B (for quick tasks)
- Phi-3-mini (very fast)

## Performance Tuning

### Batch Size
For interactive use:
```
--batch-size 512
```

For throughput:
```
--batch-size 2048
```

### Continuous Batching
Enable for multiple concurrent users:
```
--cont-batching
```

### Memory Mapping
For models close to memory limit:
```
--mlock  # Lock model in memory
```

## Troubleshooting

### Out of Memory
1. Reduce context size: `--ctx-size 4096`
2. Use lower quantization: Q4_K_M instead of Q8_0
3. Reduce batch size: `--batch-size 256`

### Slow Inference
1. Ensure full GPU offload: `-ngl 99`
2. Enable flash attention: `--flash-attn`
3. Check no CPU fallback in logs

### Model Loading Slow
1. Use mmap (default): fast initial load
2. Consider `--mlock` for consistent performance
