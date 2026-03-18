#!/usr/bin/env bash
# nemotron3-thor.sh — Launch Nemotron 3 Nano NVFP4 inference server on Jetson AGX Thor
#
# Starts a vLLM OpenAI-compatible inference server using the Nemotron 3 Nano
# NVFP4 model, optimized for the Jetson AGX Thor's unified memory architecture.
#
# The server is used by NemoClaw via the vLLM inference profile. OpenShell
# routes inference requests from the sandbox to this server at:
#   http://host.openshell.internal:8000/v1
#
# Prerequisites:
#   - HF_TOKEN environment variable set with access to the NVFP4 model
#   - Model license accepted at:
#     https://huggingface.co/nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-NVFP4
#   - NVIDIA container runtime available in Docker
#
# Usage:
#   export HF_TOKEN=hf_...
#   ./nemotron3-thor.sh
#
# Memory tuning:
#   --gpu-memory-utilization controls the fraction of Thor's 128GB unified
#   memory allocated to vLLM. The remainder stays available to the OS,
#   OpenShell, and other processes.
#
#   NVFP4 model weights load to ~18-20GB. The rest goes to KV cache.
#   All figures are approximate — actual usage varies with batch size.
#
#   Utilization  Context   vLLM pool   Weights   KV cache   OS headroom
#   0.35         8192      ~44.8 GB    ~19 GB    ~25 GB     ~83 GB
#   0.45         32768     ~57.6 GB    ~19 GB    ~38 GB     ~70 GB   ← default
#   0.55         65536     ~70.4 GB    ~19 GB    ~51 GB     ~57 GB
#
#   If you see out-of-memory errors, reduce utilization and context length.
#   If you need longer agent reasoning chains, move to the 0.55 row.
#
# Model name:
#   --served-model-name must match what NemoClaw expects: nvidia/nemotron-3-nano-30b-a3b
#   The container image uses the full HuggingFace ID internally but serves
#   requests under this shorter name for NemoClaw compatibility.

set -euo pipefail

# ── Preflight ──────────────────────────────────────────────────────────────────

if [[ -z "${HF_TOKEN:-}" ]]; then
    echo "Error: HF_TOKEN is not set." >&2
    echo "Export your HuggingFace token before running this script:" >&2
    echo "  export HF_TOKEN=hf_..." >&2
    exit 1
fi

# ── Launch ─────────────────────────────────────────────────────────────────────

sudo docker run -it --rm --pull always \
    --runtime=nvidia \
    --network host \
    -e HF_TOKEN="${HF_TOKEN}" \
    -e VLLM_USE_FLASHINFER_MOE_FP4=1 \
    -e VLLM_FLASHINFER_MOE_BACKEND=throughput \
    -v "${HOME}/.cache/huggingface:/data/models/huggingface" \
    ghcr.io/nvidia-ai-iot/vllm:latest-jetson-thor \
    bash -c "
        wget -q -O /tmp/nano_v3_reasoning_parser.py \
            --header=\"Authorization: Bearer \$HF_TOKEN\" \
            https://huggingface.co/nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-NVFP4/resolve/main/nano_v3_reasoning_parser.py \
        && vllm serve nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-NVFP4 \
            --served-model-name nvidia/nemotron-3-nano-30b-a3b \
            --host 0.0.0.0 \
            --gpu-memory-utilization 0.45 \
            --max-model-len 32768 \
            --trust-remote-code \
            --enable-auto-tool-choice \
            --tool-call-parser qwen3_coder \
            --reasoning-parser-plugin /tmp/nano_v3_reasoning_parser.py \
            --reasoning-parser nano_v3 \
            --kv-cache-dtype fp8
    "