#!/usr/bin/env bash
set -euo pipefail

log() { printf '[install-hermes-plugin-v2] %s\n' "$*" >&2; }
fail() { printf '[install-hermes-plugin-v2][ERROR] %s\n' "$*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"; }

# Target user/home detection follows the legacy Hermes installer convention:
#   1. INSTALL_AS_USER, 2. SUDO_USER, 3. current user.
USERNAME="${INSTALL_AS_USER:-${SUDO_USER:-$(whoami)}}"
USER_HOME="$(eval echo "~$USERNAME")"

SDK_WHEEL_URL="${SDK_WHEEL_URL:-https://cnb.cool/tencent/cloud/nosql/nosql-utilities/-/commit-assets/download/cc74bd6dbc931727da9ab6907b5ab1a07d7afd9d/tencentdb_agent_memory_sdk_python-0.1.0-py3-none-any.whl}"
SDK_WHEEL_NAME="tencentdb_agent_memory_sdk_python-0.1.0-py3-none-any.whl"
FORCE="${FORCE:-0}"
ALLOW_SYSTEM_PYTHON="${ALLOW_SYSTEM_PYTHON:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROVIDER_SRC="${HERMES_PROVIDER_SRC:-$REPO_ROOT/hermes-plugin/memory/memory_tencentdb_v2}"

HERMES_HOME="${HERMES_HOME:-$USER_HOME/.hermes}"
HERMES_AGENT_DIR="${HERMES_AGENT_DIR:-$HERMES_HOME/hermes-agent}"
HERMES_VENV_DIR="${HERMES_VENV_DIR:-$HERMES_AGENT_DIR/venv}"
HERMES_CONFIG="${HERMES_CONFIG:-$HERMES_HOME/config.yaml}"
HERMES_ENV="${HERMES_ENV:-$HERMES_HOME/.env}"
HERMES_MEMORY_PLUGIN_DIR="${HERMES_MEMORY_PLUGIN_DIR:-$HERMES_AGENT_DIR/plugins/memory}"
PROVIDER_TARGET="$HERMES_MEMORY_PLUGIN_DIR/memory_tencentdb_v2"

# Install the SDK into the Python environment that Hermes actually uses.
# Selection order:
#   1. PYTHON_BIN, if explicitly provided
#   2. HERMES_VENV_DIR/bin/python, if present
#   3. Python interpreter from the installed `hermes` command shebang, if discoverable
#   4. system python3 only when ALLOW_SYSTEM_PYTHON=1
if [[ -n "${PYTHON_BIN:-}" ]]; then
  :
elif [[ -x "$HERMES_VENV_DIR/bin/python" ]]; then
  PYTHON_BIN="$HERMES_VENV_DIR/bin/python"
elif command -v hermes >/dev/null 2>&1; then
  HERMES_BIN="$(command -v hermes)"
  HERMES_SHEBANG="$(head -n 1 "$HERMES_BIN" 2>/dev/null || true)"
  if [[ "$HERMES_SHEBANG" == '#!'*python* ]]; then
    HERMES_SHEBANG="${HERMES_SHEBANG#'#!'}"
    read -r HERMES_SHEBANG_CMD HERMES_SHEBANG_ARG _ <<<"$HERMES_SHEBANG"
    if [[ "$(basename "$HERMES_SHEBANG_CMD")" == "env" && -n "${HERMES_SHEBANG_ARG:-}" ]]; then
      PYTHON_BIN="$(command -v "$HERMES_SHEBANG_ARG" || true)"
    elif [[ -x "$HERMES_SHEBANG_CMD" ]]; then
      PYTHON_BIN="$HERMES_SHEBANG_CMD"
    fi
  fi
fi

if [[ -z "${PYTHON_BIN:-}" ]]; then
  if [[ "$ALLOW_SYSTEM_PYTHON" == "1" ]]; then
    PYTHON_BIN="python3"
  else
    fail "Hermes Python not found. Set PYTHON_BIN=/path/to/hermes/python or HERMES_VENV_DIR=/path/to/venv. Refusing to use system python3 by default to avoid externally-managed-environment installs."
  fi
fi

TDAI_MEMORY_ENDPOINT="${TDAI_MEMORY_ENDPOINT:-http://127.0.0.1:8420}"
TDAI_MEMORY_API_KEY="${TDAI_MEMORY_API_KEY:-local}"
TDAI_MEMORY_SERVICE_ID="${TDAI_MEMORY_SERVICE_ID:-default}"
WRITE_HERMES_ENV="${WRITE_HERMES_ENV:-1}"
WRITE_HERMES_CONFIG="${WRITE_HERMES_CONFIG:-1}"

need_cmd curl
need_cmd "$PYTHON_BIN"

ensure_pip() {
  if "$PYTHON_BIN" -m pip --version >/dev/null 2>&1; then
    return
  fi

  log "pip not found in selected Hermes Python; trying ensurepip: $PYTHON_BIN"
  if "$PYTHON_BIN" -m ensurepip --upgrade; then
    "$PYTHON_BIN" -m pip --version >/dev/null 2>&1 || fail "ensurepip completed but pip is still unavailable for $PYTHON_BIN"
    return
  fi

  cat >&2 <<EOF
[install-hermes-plugin-v2][ERROR] pip is not available in the selected Hermes Python:
  $PYTHON_BIN

Fix options:
  1. Install pip into that Hermes venv and rerun:
     $PYTHON_BIN -m ensurepip --upgrade

  2. If ensurepip is unavailable on Ubuntu/Debian, install venv support and recreate/fix the Hermes venv:
     sudo apt-get update && sudo apt-get install -y python3-venv python3-pip

  3. Or explicitly point this installer to the Python that Hermes actually uses:
     PYTHON_BIN=/path/to/hermes/python bash scripts/install-hermes-plugin-v2.sh
EOF
  exit 1
}

if [[ ! -d "$PROVIDER_SRC" ]]; then
  fail "Hermes provider directory not found: $PROVIDER_SRC"
fi

if [[ ! -d "$HERMES_AGENT_DIR" ]]; then
  log "WARN: Hermes agent dir not found: $HERMES_AGENT_DIR"
  log "      Set HERMES_AGENT_DIR if Hermes is installed elsewhere."
fi

ensure_pip

log "Downloading Python SDK wheel"
TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT
curl -fL -o "$TMP_DIR/$SDK_WHEEL_NAME" "$SDK_WHEEL_URL"

log "Installing Python SDK with $PYTHON_BIN"
"$PYTHON_BIN" -m pip install "$TMP_DIR/$SDK_WHEEL_NAME"

log "Installing Hermes provider"
mkdir -p "$HERMES_MEMORY_PLUGIN_DIR"
if [[ -e "$PROVIDER_TARGET" || -L "$PROVIDER_TARGET" ]]; then
  if [[ "$FORCE" == "1" ]]; then
    rm -rf "$PROVIDER_TARGET"
  else
    fail "target already exists: $PROVIDER_TARGET (set FORCE=1 to overwrite)"
  fi
fi
ln -s "$PROVIDER_SRC" "$PROVIDER_TARGET"
log "Provider linked: $PROVIDER_TARGET -> $PROVIDER_SRC"

log "Checking Hermes config"
if [[ "$WRITE_HERMES_CONFIG" == "1" ]]; then
  log "Enabling memory.provider=memory_tencentdb_v2 in $HERMES_CONFIG"
  mkdir -p "$(dirname "$HERMES_CONFIG")"
  if [[ -f "$HERMES_CONFIG" ]]; then
    cp "$HERMES_CONFIG" "$HERMES_CONFIG.bak.$(date +%Y%m%d%H%M%S)"
  fi

  HERMES_CONFIG="$HERMES_CONFIG" "$PYTHON_BIN" <<'PY'
import os
import re
from pathlib import Path

path = Path(os.environ["HERMES_CONFIG"])
provider_line = "  provider: memory_tencentdb_v2"


def update_with_pyyaml(text: str) -> str:
    import yaml
    data = yaml.safe_load(text) if text.strip() else {}
    if not isinstance(data, dict):
        data = {}
    memory = data.get("memory")
    if not isinstance(memory, dict):
        memory = {}
    data["memory"] = memory
    memory["provider"] = "memory_tencentdb_v2"
    return yaml.safe_dump(data, sort_keys=False, allow_unicode=True)


def update_minimal(text: str) -> str:
    lines = text.splitlines()
    memory_start = None
    memory_end = None
    for i, line in enumerate(lines):
        if re.match(r"^memory\s*:\s*(#.*)?$", line):
            memory_start = i
            memory_end = len(lines)
            for j in range(i + 1, len(lines)):
                if lines[j] and not lines[j].startswith((" ", "\t")):
                    memory_end = j
                    break
            break

    if memory_start is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines.extend(["memory:", provider_line])
        return "\n".join(lines) + "\n"

    for i in range(memory_start + 1, memory_end):
        if re.match(r"^\s*provider\s*:", lines[i]):
            indent = re.match(r"^(\s*)", lines[i]).group(1) or "  "
            lines[i] = f"{indent}provider: memory_tencentdb_v2"
            return "\n".join(lines) + "\n"

    insert_at = memory_start + 1
    lines.insert(insert_at, provider_line)
    return "\n".join(lines) + "\n"


text = path.read_text() if path.exists() else ""
try:
    updated = update_with_pyyaml(text)
except Exception:
    updated = update_minimal(text)
path.write_text(updated)
PY
else
  if [[ -f "$HERMES_CONFIG" ]] && sed -n '/^memory:/,/^[[:alpha:]_][[:alnum:]_]*:/p' "$HERMES_CONFIG" | grep -q 'provider: memory_tencentdb_v2'; then
    log "memory.provider already set to memory_tencentdb_v2"
  else
    log "Provider installed but NOT enabled because WRITE_HERMES_CONFIG=$WRITE_HERMES_CONFIG. Add/edit in $HERMES_CONFIG:"
    cat >&2 <<'EOF'

memory:
  provider: memory_tencentdb_v2
EOF
  fi
fi

_update_env() {
  local key="$1"
  local value="$2"
  local file="$3"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  local tmp
  tmp="$(mktemp)"
  grep -v -E "^(# *)?${key}=" "$file" > "$tmp" || true
  local escaped="$value"
  escaped="${escaped//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  printf '%s="%s"\n' "$key" "$escaped" >> "$tmp"
  mv "$tmp" "$file"
}

if [[ "$WRITE_HERMES_ENV" == "1" ]]; then
  log "Writing Memory SDK env vars to $HERMES_ENV"
  _update_env "TDAI_MEMORY_ENDPOINT" "$TDAI_MEMORY_ENDPOINT" "$HERMES_ENV"
  _update_env "TDAI_MEMORY_API_KEY" "$TDAI_MEMORY_API_KEY" "$HERMES_ENV"
  _update_env "TDAI_MEMORY_SERVICE_ID" "$TDAI_MEMORY_SERVICE_ID" "$HERMES_ENV"
fi

cat >&2 <<EOF

[install-hermes-plugin-v2] Done.
Provider installed at:
  $PROVIDER_TARGET

SDK env file:
  $HERMES_ENV

Hermes config:
  $HERMES_CONFIG
  memory.provider = memory_tencentdb_v2

Standalone Gateway env:
  TDAI_MEMORY_ENDPOINT="$TDAI_MEMORY_ENDPOINT"
  TDAI_MEMORY_API_KEY="$TDAI_MEMORY_API_KEY"
  TDAI_MEMORY_SERVICE_ID="$TDAI_MEMORY_SERVICE_ID"
EOF
