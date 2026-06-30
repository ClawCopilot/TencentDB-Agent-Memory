#!/bin/bash
set -e

# TencentDB Agent Memory TDAI Gateway Startup Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export TDAI_GATEWAY_CONFIG="$SCRIPT_DIR/tdai-gateway.standalone.yaml"
export TDAI_GATEWAY_HOST="127.0.0.1"
export TDAI_GATEWAY_PORT="8420"
export TDAI_DATA_DIR="$HOME/.memory-tencentdb/memory-tdai"
export TDAI_LLM_API_KEY="sk-cp-JrsXMfjYj9mexu5NAr9Eevedk7IBFoCZFi4azaPEColz-bU0LH0NPA-Z-gxMlM505CKP1Cq-zaAP0OF2bQ0k6y44J1TP0XNodYCxY9oiQAmeGb0RPIivl6A"
export TDAI_LLM_BASE_URL="https://api.minimaxi.com/v1"
export TDAI_LLM_MODEL="MiniMax-M3"

cd "$SCRIPT_DIR"

echo "Starting TDAI Gateway..."
echo "  Config: $TDAI_GATEWAY_CONFIG"
echo "  Host: $TDAI_GATEWAY_HOST:$TDAI_GATEWAY_PORT"
echo "  Data Dir: $TDAI_DATA_DIR"
echo "  LLM Model: $TDAI_LLM_MODEL"
echo ""

node --import tsx/esm src/gateway/server.ts
