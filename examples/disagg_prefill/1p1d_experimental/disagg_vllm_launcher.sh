#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# NOTE: For correct KV cache transfer, ensure all processes use the same PYTHONHASHSEED to keep the hash of the KV cache consistent across processes.
export PYTHONHASHSEED=0

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <prefiller | decoder> [model]"
    exit 1
fi

if [[ $# -eq 1 ]]; then
    echo "Using default model: meta-llama/Llama-3.1-8B-Instruct"
    MODEL="Qwen/Qwen2.5-7B"
else
    echo "Using model: $2"
    MODEL=$2
fi


if [[ $1 == "prefiller" ]]; then
    # Prefiller listens on port 7100
    prefill_config_file=$SCRIPT_DIR/configs/lmcache-prefiller-config.yaml

    UCX_TLS=cuda_ipc,cuda_copy,tcp \
        LMCACHE_CONFIG_FILE=$prefill_config_file \
        VLLM_ENABLE_V1_MULTIPROCESSING=1 \
        VLLM_WORKER_MULTIPROC_METHOD=spawn \
        CUDA_VISIBLE_DEVICES=0,1 \
        NIXL_DELETE_PORT=10003,10004 \
        vllm serve $MODEL \
        --port 7100 \
        --gpu-memory-utilization 0.37 \
        --max-model-len 1000 \
        -tp 2 \
        --max-num-batched-tokens 1000 \
        --disable-log-requests \
        --max-num-seqs 1 \
        --enforce-eager \
        --no-enable-prefix-caching \
        --kv-transfer-config \
        '{"kv_connector":"LMCacheConnectorV1","kv_role":"kv_producer","kv_connector_extra_config": {"discard_partial_chunks": false, "lmcache_rpc_port": "producer1"}}'




elif [[ $1 == "decoder" ]]; then
    # Decoder listens on port 7200
    decode_config_file=$SCRIPT_DIR/configs/lmcache-decoder-config.yaml

    UCX_TLS=cuda_ipc,cuda_copy,tcp \
        LMCACHE_CONFIG_FILE=$decode_config_file \
        VLLM_ENABLE_V1_MULTIPROCESSING=1 \
        VLLM_WORKER_MULTIPROC_METHOD=spawn \
        CUDA_VISIBLE_DEVICES=0,1 \
        NIXL_DELETE_PORT=10001,10002 \
        vllm serve $MODEL \
        --port 7200 \
        --gpu-memory-utilization 0.39 \
        --max-model-len 1000 \
        -tp 2 \
        --max-num-batched-tokens 1000 \
        --disable-log-requests \
        --max-num-seqs 10 \
        --enforce-eager \
        --no-enable-prefix-caching \
        --kv-transfer-config \
        '{"kv_connector":"LMCacheConnectorV1","kv_role":"kv_consumer","kv_connector_extra_config": {"discard_partial_chunks": false, "lmcache_rpc_port": "consumer1", "skip_last_n_tokens": 1}}'


else
    echo "Invalid role: $1"
    echo "Should be either prefill, decode"
    exit 1
fi
