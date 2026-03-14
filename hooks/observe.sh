#!/bin/bash
# Sinapsis Continuous Learning - Observation Hook
# Adaptado de ECC v2.1 (affaan-m/everything-claude-code)
#
# Captura eventos de tool use para analisis de patrones.
# Claude Code pasa datos del hook via stdin como JSON.
#
# Uso: bash observe.sh [pre|post]
# Registrar en ~/.claude/settings.json hooks PreToolUse y PostToolUse

set -e

HOOK_PHASE="${1:-post}"

# -- Leer stdin --
INPUT_JSON=$(cat)
[ -z "$INPUT_JSON" ] && exit 0

# -- Resolver Python --
PYTHON_CMD=""
if command -v python3 >/dev/null 2>&1; then
  PYTHON_CMD="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON_CMD="python"
fi

if [ -z "$PYTHON_CMD" ]; then
  echo "[sinapsis-observe] No python encontrado, saltando observacion" >&2
  exit 0
fi

# -- Extraer cwd del stdin para deteccion de proyecto --
STDIN_CWD=$(echo "$INPUT_JSON" | "$PYTHON_CMD" -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("cwd", ""))
except:
    print("")
' 2>/dev/null || echo "")

if [ -n "$STDIN_CWD" ] && [ -d "$STDIN_CWD" ]; then
  export CLAUDE_PROJECT_DIR="$STDIN_CWD"
fi

# -- Configuracion --
CONFIG_DIR="${HOME}/.claude/homunculus"
PROJECTS_DIR="${CONFIG_DIR}/projects"
MAX_FILE_SIZE_MB=10

# Skip si deshabilitado
[ -f "$CONFIG_DIR/disabled" ] && exit 0

# -- Guards de sesion automatizada --

# Skip sesiones no-CLI
case "${CLAUDE_CODE_ENTRYPOINT:-cli}" in
  cli) ;;
  *) exit 0 ;;
esac

# Skip profile minimal
[ "${ECC_HOOK_PROFILE:-standard}" = "minimal" ] && exit 0

# Skip si variable cooperativa activa
[ "${ECC_SKIP_OBSERVE:-0}" = "1" ] && exit 0

# Skip subagents
_AGENT_ID=$(echo "$INPUT_JSON" | "$PYTHON_CMD" -c "import json,sys; print(json.load(sys.stdin).get('agent_id',''))" 2>/dev/null || true)
[ -n "$_AGENT_ID" ] && exit 0

# -- Deteccion de proyecto --

PROJECT_ID="global"
PROJECT_NAME="global"
PROJECT_DIR="$CONFIG_DIR"

# Intentar deteccion por git
if command -v git &>/dev/null; then
  PROJECT_ROOT=""
  if [ -n "$CLAUDE_PROJECT_DIR" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
    PROJECT_ROOT="$CLAUDE_PROJECT_DIR"
  else
    PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
  fi

  if [ -n "$PROJECT_ROOT" ]; then
    PROJECT_NAME=$(basename "$PROJECT_ROOT")

    # Hash del remote URL (portable) o del path (fallback)
    REMOTE_URL=$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null || true)
    HASH_INPUT="${REMOTE_URL:-$PROJECT_ROOT}"
    PROJECT_ID=$(printf '%s' "$HASH_INPUT" | "$PYTHON_CMD" -c "import sys,hashlib; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:12])" 2>/dev/null || echo "fallback")

    PROJECT_DIR="${PROJECTS_DIR}/${PROJECT_ID}"

    # Crear estructura de proyecto
    mkdir -p "${PROJECT_DIR}/instincts/personal"
    mkdir -p "${PROJECT_DIR}/instincts/inherited"
    mkdir -p "${PROJECT_DIR}/observations.archive"
    mkdir -p "${PROJECT_DIR}/evolved/skills"
    mkdir -p "${PROJECT_DIR}/evolved/commands"
    mkdir -p "${PROJECT_DIR}/evolved/agents"

    # Actualizar registry (datos via env vars para evitar inyeccion)
    export _SIN_REGISTRY_PATH="${CONFIG_DIR}/projects.json"
    export _SIN_PROJECT_DIR="$PROJECT_DIR"
    export _SIN_PROJECT_ID="$PROJECT_ID"
    export _SIN_PROJECT_NAME="$PROJECT_NAME"
    export _SIN_PROJECT_ROOT="$PROJECT_ROOT"
    export _SIN_REMOTE_URL="$REMOTE_URL"

    "$PYTHON_CMD" -c '
import json, os, tempfile
from datetime import datetime, timezone

registry_path = os.environ["_SIN_REGISTRY_PATH"]
project_dir = os.environ["_SIN_PROJECT_DIR"]

os.makedirs(project_dir, exist_ok=True)
os.makedirs(os.path.dirname(registry_path), exist_ok=True)

try:
    with open(registry_path) as f:
        registry = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    registry = {}

now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
registry[os.environ["_SIN_PROJECT_ID"]] = {
    "name": os.environ["_SIN_PROJECT_NAME"],
    "root": os.environ["_SIN_PROJECT_ROOT"],
    "remote": os.environ.get("_SIN_REMOTE_URL", ""),
    "last_seen": now,
}

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(registry_path), text=True)
with os.fdopen(fd, "w") as f:
    json.dump(registry, f, indent=2)
os.replace(tmp, registry_path)
' 2>/dev/null || true
  fi
fi

OBSERVATIONS_FILE="${PROJECT_DIR}/observations.jsonl"

# -- Auto-purge observaciones >30 dias --
PURGE_MARKER="${PROJECT_DIR}/.last-purge"
if [ ! -f "$PURGE_MARKER" ] || [ "$(find "$PURGE_MARKER" -mtime +1 2>/dev/null)" ]; then
  find "${PROJECT_DIR}" -name "observations-*.jsonl" -mtime +30 -delete 2>/dev/null || true
  touch "$PURGE_MARKER" 2>/dev/null || true
fi

# -- Parsear input JSON --
PARSED=$(echo "$INPUT_JSON" | HOOK_PHASE="$HOOK_PHASE" "$PYTHON_CMD" -c '
import json, sys, os

try:
    data = json.load(sys.stdin)
    hook_phase = os.environ.get("HOOK_PHASE", "post")
    event = "tool_start" if hook_phase == "pre" else "tool_complete"

    tool_name = data.get("tool_name", data.get("tool", "unknown"))
    tool_input = data.get("tool_input", data.get("input", {}))
    tool_output = data.get("tool_response", data.get("tool_output", data.get("output", "")))
    session_id = data.get("session_id", "unknown")
    cwd = data.get("cwd", "")

    if isinstance(tool_input, dict):
        tool_input_str = json.dumps(tool_input)[:5000]
    else:
        tool_input_str = str(tool_input)[:5000]

    if isinstance(tool_output, dict):
        tool_output_str = json.dumps(tool_output)[:5000]
    else:
        tool_output_str = str(tool_output)[:5000]

    print(json.dumps({
        "parsed": True,
        "event": event,
        "tool": tool_name,
        "input": tool_input_str if event == "tool_start" else None,
        "output": tool_output_str if event == "tool_complete" else None,
        "session": session_id,
        "cwd": cwd
    }))
except Exception as e:
    print(json.dumps({"parsed": False, "error": str(e)}))
')

PARSED_OK=$(echo "$PARSED" | "$PYTHON_CMD" -c "import json,sys; print(json.load(sys.stdin).get('parsed', False))" 2>/dev/null || echo "False")

if [ "$PARSED_OK" != "True" ]; then
  exit 0
fi

# -- Archivar si fichero demasiado grande --
if [ -f "$OBSERVATIONS_FILE" ]; then
  file_size_mb=$(du -m "$OBSERVATIONS_FILE" 2>/dev/null | cut -f1)
  if [ "${file_size_mb:-0}" -ge "$MAX_FILE_SIZE_MB" ]; then
    archive_dir="${PROJECT_DIR}/observations.archive"
    mkdir -p "$archive_dir"
    mv "$OBSERVATIONS_FILE" "$archive_dir/observations-$(date +%Y%m%d-%H%M%S)-$$.jsonl" 2>/dev/null || true
  fi
fi

# -- Escribir observacion (con scrub de secrets) --
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
export PROJECT_ID_ENV="$PROJECT_ID"
export PROJECT_NAME_ENV="$PROJECT_NAME"
export TIMESTAMP="$timestamp"

echo "$PARSED" | "$PYTHON_CMD" -c '
import json, sys, os, re

parsed = json.load(sys.stdin)

SECRET_RE = re.compile(
    r"(?i)(api[_-]?key|token|secret|password|authorization|credentials?|auth|bearer)"
    r"""(["'"'"'"'"'"'\s:=]+)"""
    r"([A-Za-z]+\s+)?"
    r"([A-Za-z0-9_\-/.+=]{8,})"
)
JWT_RE = re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")
PEM_RE = re.compile(r"-----BEGIN[A-Z \n]+-----[\s\S]*?-----END[A-Z \n]+-----")

def scrub(val):
    if val is None:
        return None
    s = str(val)
    s = SECRET_RE.sub(lambda m: m.group(1) + m.group(2) + (m.group(3) or "") + "[REDACTED]", s)
    s = JWT_RE.sub("[JWT_REDACTED]", s)
    s = PEM_RE.sub("[PEM_REDACTED]", s)
    return s

observation = {
    "timestamp": os.environ["TIMESTAMP"],
    "event": parsed["event"],
    "tool": parsed["tool"],
    "session": parsed["session"],
    "project_id": os.environ.get("PROJECT_ID_ENV", "global"),
    "project_name": os.environ.get("PROJECT_NAME_ENV", "global"),
}

if parsed.get("input"):
    observation["input"] = scrub(parsed["input"])
if parsed.get("output") is not None:
    observation["output"] = scrub(parsed["output"])

print(json.dumps(observation))
' | {
  # File locking para escrituras concurrentes seguras
  if command -v flock >/dev/null 2>&1; then
    if ! flock -w 10 "$OBSERVATIONS_FILE" -c "cat >> '$OBSERVATIONS_FILE'" 2>/dev/null; then
      # Fallback si flock falla: escribir a temp + append
      _TMP="${OBSERVATIONS_FILE}.tmp.$$"
      cat > "$_TMP" && cat "$_TMP" >> "$OBSERVATIONS_FILE" && rm -f "$_TMP"
      echo "[sinapsis-observe] Lock timeout, used fallback write" >&2
    fi
  else
    # Fallback sin flock (macOS sin coreutils) — append atomico del OS
    cat >> "$OBSERVATIONS_FILE"
  fi
}

# -- Watchdog: alertas proactivas en errores criticos --
if [ "$HOOK_PHASE" = "post" ]; then
  _OUTPUT=$(echo "$PARSED" | "$PYTHON_CMD" -c "import json,sys; print(json.load(sys.stdin).get('output','') or '')" 2>/dev/null || echo "")
  if echo "$_OUTPUT" | grep -qiE "(FATAL|PANIC|OOM|segfault|killed|ENOSPC|out of memory)"; then
    echo "[sinapsis-watchdog] ⚠ Error critico detectado en output. Considera ejecutar /gotcha para capturarlo." >&2
  fi
fi

exit 0
