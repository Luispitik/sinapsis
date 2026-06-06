#!/bin/bash
# Sinapsis Observer - v4.1
# Writes one JSONL line per tool use to observations.jsonl
# Requires: python3
# Called by settings.json hooks as:
#   PreToolUse:  bash ~/.claude/skills/sinapsis-learning/hooks/observe.sh pre
#   PostToolUse: bash ~/.claude/skills/sinapsis-learning/hooks/observe.sh post

HOOK_PHASE="${1:-post}"

# Read stdin
INPUT_JSON=$(cat)
[ -z "$INPUT_JSON" ] && exit 0

# Skip if disabled
[ -f "$HOME/.claude/homunculus/disabled" ] && exit 0

# Skip non-interactive entrypoints
case "${CLAUDE_CODE_ENTRYPOINT:-cli}" in
  cli|sdk|api|claude-desktop|"") ;;
  *) exit 0 ;;
esac

[ "${ECC_HOOK_PROFILE:-standard}" = "minimal" ] && exit 0
[ "${ECC_SKIP_OBSERVE:-0}" = "1" ] && exit 0

# Find Python
# Patch local (Windows): validar --version antes de aceptar el comando.
# En Windows, `python3` suele ser el shim del Microsoft Store que responde a
# `command -v` pero NO ejecuta nada (imprime un aviso y sale ≠0). Sin validar
# --version, observe.sh aceptaba el shim y el observador fallaba en silencio.
PYTHON_CMD=""
for candidate in "py -3" python3 python python3.12 python3.11 python3.10; do
  cmd=$(echo "$candidate" | awk '{print $1}')
  if command -v "$cmd" >/dev/null 2>&1; then
    if $candidate --version 2>&1 | grep -qE "Python 3\.(9|10|11|12|13)"; then
      PYTHON_CMD="$candidate"
      break
    fi
  fi
done
[ -z "$PYTHON_CMD" ] && exit 0

# Run the observer
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "$INPUT_JSON" | $PYTHON_CMD "$SCRIPT_DIR/observe_v3.py" "$HOOK_PHASE"

exit 0
