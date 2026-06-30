#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# start-offload-local.sh — 本地启动 Offload Server（零外部依赖）
# ═══════════════════════════════════════════════════════════════════
#
# 使用 LocalStorageBackend（本地文件） + LocalStateBackend（进程内存）
# 替代生产环境的 COS + Redis，适合本地开发调试。
#
# 用法:
#   bash scripts/start-offload-local.sh [start|stop|restart|status]
#   默认: start（后台运行）
#
# 环境变量（可选）:
#   PORT                    — 服务端口，默认 9100
#   DATA_DIR                — 数据存储目录，默认 /tmp/openclaw/data
#   LOG_DIR                 — 日志输出目录，默认 /tmp/openclaw/logs
#   API_KEY                 — 认证 API Key，默认 "dev-local-key"
#   LLM_BASE_URL            — LLM API 地址（L1/L1.5/L2 需要），默认空
#   LLM_API_KEY             — LLM API Key，默认空
#   OPIK_ENABLED            — 是否启用 Opik 追踪，默认 "false"
#   OPIK_URL_OVERRIDE       — Opik Server 地址
#   OPIK_API_KEY            — Opik API Key
#   OPIK_WORKSPACE          — Opik Workspace，默认 "default"
#   OPIK_PROJECT_NAME       — Opik Project，默认 "openclaw-offload-server"
#   L2_NULL_THRESHOLD       — L2 触发阈值，默认 6（设为 999999 可禁用 L2）
#   AGGRESSIVE_COMPRESS_RATIO — aggressive 压缩触发比例，默认 0.85（设为 999 可禁用）
#   EMERGENCY_COMPRESS_RATIO  — emergency 压缩触发比例，默认 0.95（设为 999 可禁用）
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── 配置 ──
PORT="${PORT:-9100}"
DATA_DIR="${DATA_DIR:-/tmp/openclaw/data}"
LOG_DIR="${LOG_DIR:-/tmp/openclaw/logs}"
API_KEY="${API_KEY:-dev-local-key}"
LLM_BASE_URL="${LLM_BASE_URL:-https://tokenhub.tencentmaas.com/v1}"
LLM_API_KEY="${LLM_API_KEY:-sk-yYBudowP30M9t4X99vBOtNzhqz4a39jud4i3Br328mh87qcr}"
LLM_MODEL="${LLM_MODEL:-ep-91sgogyz}"
OPIK_ENABLED="${OPIK_ENABLED:-true}"
OPIK_URL_OVERRIDE="${OPIK_URL_OVERRIDE:-http://21.6.226.49:5173/api}"
OPIK_API_KEY="${OPIK_API_KEY:-}"
OPIK_WORKSPACE="${OPIK_WORKSPACE:-default}"
OPIK_PROJECT_NAME="${OPIK_PROJECT_NAME:-offload_server_49}"
L2_NULL_THRESHOLD="${L2_NULL_THRESHOLD:-6}"
AGGRESSIVE_COMPRESS_RATIO="${AGGRESSIVE_COMPRESS_RATIO:-0.85}"
EMERGENCY_COMPRESS_RATIO="${EMERGENCY_COMPRESS_RATIO:-0.95}"
PID_FILE="/tmp/openclaw/offload.pid"

# ── 子命令 ──
CMD="${1:-start}"

do_stop() {
  if [ -f "${PID_FILE}" ]; then
    local pid
    pid=$(cat "${PID_FILE}")
    if kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}"
      echo "[OK] Stopped (pid=${pid})"
    else
      echo "[WARN] Process ${pid} not running"
    fi
    rm -f "${PID_FILE}"
  else
    echo "[WARN] No PID file found"
  fi
}

do_status() {
  if [ -f "${PID_FILE}" ] && kill -0 "$(cat "${PID_FILE}")" 2>/dev/null; then
    echo "[OK] Running (pid=$(cat "${PID_FILE}"), port=${PORT})"
  else
    echo "[OFF] Not running"
  fi
}

do_start() {
  # Kill existing if running
  if [ -f "${PID_FILE}" ] && kill -0 "$(cat "${PID_FILE}")" 2>/dev/null; then
    kill "$(cat "${PID_FILE}")" 2>/dev/null
    sleep 1
  fi

  mkdir -p "${DATA_DIR}" "${LOG_DIR}"

  local LOG_FILE="${LOG_DIR}/offload-server-$(date +%Y%m%d).log"

  echo "═══════════════════════════════════════════════════════════"
  echo "  Offload Server — Local Mode (zero dependencies)"
  echo "═══════════════════════════════════════════════════════════"
  echo "  Port:       ${PORT}"
  echo "  Data:       ${DATA_DIR}"
  echo "  Log:        ${LOG_FILE}"
  echo "  API Key:    ${API_KEY:0:8}..."
  echo "  LLM URL:    ${LLM_BASE_URL}"
  echo "  LLM Model:  ${LLM_MODEL}"
  echo "  Opik:       ${OPIK_ENABLED} (${OPIK_URL_OVERRIDE:-disabled})"
  echo "  L2 threshold:        ${L2_NULL_THRESHOLD}"
  echo "  Aggressive ratio:    ${AGGRESSIVE_COMPRESS_RATIO}"
  echo "  Emergency ratio:     ${EMERGENCY_COMPRESS_RATIO}"
  echo "═══════════════════════════════════════════════════════════"

  cd "${PROJECT_ROOT}"

  # 动态生成临时配置文件，将 standalone yaml 与 offload 覆盖项合并
  local OVERRIDE_CONFIG="/tmp/openclaw/tdai-gateway.override.yaml"
  mkdir -p /tmp/openclaw
  cat "${PROJECT_ROOT}/tdai-gateway.standalone.yaml" > "${OVERRIDE_CONFIG}"
  cat >> "${OVERRIDE_CONFIG}" << YAML_EOF

# ── 动态注入的 offload 覆盖配置（由 start-offload-local.sh 生成）──
offload:
  l2NullThreshold: ${L2_NULL_THRESHOLD}
  aggressiveCompressRatio: ${AGGRESSIVE_COMPRESS_RATIO}
  emergencyCompressRatio: ${EMERGENCY_COMPRESS_RATIO}
YAML_EOF

  TDAI_GATEWAY_CONFIG="${OVERRIDE_CONFIG}" \
  TDAI_GATEWAY_PORT="${PORT}" \
  TDAI_GATEWAY_HOST="0.0.0.0" \
  TDAI_DATA_DIR="${DATA_DIR}" \
  STATE_BACKEND="local" \
  TDAI_V2_API_KEY="${API_KEY}" \
  TDAI_LLM_API_KEY="${LLM_API_KEY}" \
  TDAI_LLM_BASE_URL="${LLM_BASE_URL}" \
  TDAI_LLM_MODEL="${LLM_MODEL}" \
  OPIK_ENABLED="${OPIK_ENABLED}" \
  OPIK_URL_OVERRIDE="${OPIK_URL_OVERRIDE}" \
  OPIK_API_KEY="${OPIK_API_KEY}" \
  OPIK_WORKSPACE="${OPIK_WORKSPACE}" \
  OPIK_PROJECT_NAME="${OPIK_PROJECT_NAME}" \
  MEMORY_MAX_BODY_BYTES="10485760" \
  nohup npx tsx src/gateway/server.ts >> "${LOG_FILE}" 2>&1 &

  echo $! > "${PID_FILE}"
  sleep 2

  if kill -0 "$(cat "${PID_FILE}")" 2>/dev/null; then
    echo "[OK] Started (pid=$(cat "${PID_FILE}"), log=${LOG_FILE})"
    echo ""
    echo "  验证: curl -s http://127.0.0.1:${PORT}/health"
    echo "  停止: bash scripts/start-offload-local.sh stop"
    echo "  日志: tail -f ${LOG_FILE}"
  else
    echo "[FAIL] Process exited, check log: ${LOG_FILE}"
    tail -10 "${LOG_FILE}"
    exit 1
  fi
}

case "${CMD}" in
  start)   do_start ;;
  stop)    do_stop ;;
  restart) do_stop; sleep 1; do_start ;;
  status)  do_status ;;
  *)
    echo "用法: bash scripts/start-offload-local.sh [start|stop|restart|status]"
    exit 1
    ;;
esac
