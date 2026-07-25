#!/bin/bash
# Tests for structural error detection in the observer + isRealError() in the learner.
#
# Context (PR #29, v4.9.0): observe_v3.py used to set is_error on ANY output containing
# the substring "error"/"failed" — including the CONTENT of a file read successfully, so
# a Read of source code with `throw new Error` looked like a tool failure. One real
# session produced 190 proposals of which 189 were junk. These tests pin both halves of
# the fix: what the observer WRITES, and how the learner RE-VALIDATES flags written by
# older observers still sitting in the observation window.
#
# Run: bash tests/test-error-detection.sh

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OBSERVER="$SCRIPT_DIR/../skills/sinapsis-learning/hooks/observe_v3.py"
LEARNER="$SCRIPT_DIR/../core/_session-learner.sh"

pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

echo "=== Error Detection Tests ==="
echo ""

PY=""
for c in python3 python py; do
  if command -v "$c" >/dev/null 2>&1; then
    if "$c" --version >/dev/null 2>&1; then PY="$c"; break; fi
  fi
done
if [ -z "$PY" ]; then
  echo "  SKIP: no python interpreter available"
  echo ""
  echo "=== Results: 0 passed, 0 failed (skipped) ==="
  exit 0
fi

SANDBOX=$(mktemp -d)
SANDBOX=$(cd "$SANDBOX" && { pwd -W 2>/dev/null || pwd; })
trap 'rm -rf "$SANDBOX" 2>/dev/null' EXIT

# run_observer <tool> <tool_response> <tag> -> "1" if is_error was set, else "0".
# Drives the REAL hook end to end: feeds it a PostToolUse payload on stdin in a hermetic
# home, then reads the flag back out of the observation it appended.
#
# CRITICAL: the observer resolves its config dir with os.path.expanduser("~"), and on
# Windows that reads USERPROFILE — NOT HOME. Overriding HOME alone leaves the sandbox
# leaking into the developer's real ~/.claude/homunculus and appends synthetic
# observations to live learning data. Both variables must be redirected.
run_observer() {
  local tool="$1" resp="$2" tag="$3"
  local home="$SANDBOX/h$tag"
  rm -rf "$home"; mkdir -p "$home/.claude/homunculus/projects"
  "$PY" -c "
import json,sys
print(json.dumps({
  'hook_event_name':'PostToolUse',
  'tool_name': sys.argv[1],
  'tool_input': {'file_path': '/tmp/x.ts'},
  'tool_response': sys.argv[2],
  'session_id':'test-session',
  'cwd': sys.argv[3],
}))" "$tool" "$resp" "$home" \
    | HOME="$home" USERPROFILE="$home" HOMEDRIVE="" HOMEPATH="" \
      CLAUDE_CODE_ENTRYPOINT="cli" ECC_HOOK_PROFILE="" ECC_SKIP_OBSERVE="" \
      "$PY" "$OBSERVER" post >/dev/null 2>&1
  # cwd is not a git repo, so project_id stays "global" and the observation lands in the
  # homunculus root rather than under projects/<hash>/. Search both.
  local f
  f=$(find "$home/.claude/homunculus" -name observations.jsonl 2>/dev/null | head -1)
  [ -z "$f" ] && { echo "NOFILE"; return; }
  "$PY" -c "
import json,sys
flag='0'
for line in open(sys.argv[1],encoding='utf-8'):
    line=line.strip()
    if not line: continue
    try: o=json.loads(line)
    except Exception: continue
    if o.get('event')=='tool_complete' and o.get('is_error'): flag='1'
print(flag)" "$f"
}

echo "--- Observer: successful calls must NOT be flagged ---"

# 1. A Read that SUCCEEDS over source code mentioning errors. This is the exact false
#    positive that produced 189 junk proposals: the word lives in the file, not in a verdict.
SRC='{"type":"text","file":{"filePath":"/tmp/x.ts","content":"try { doWork(); } catch (e) { throw new Error(\"request failed\"); }\n// TODO: handle errno and EPERM cases\n"}}'
R=$(run_observer Read "$SRC" 1)
[ "$R" = "0" ] && pass "T1: successful Read of code containing 'throw new Error' is not an error" \
  || fail "T1: Read wrongly flagged (got '$R')"

# 2. A Bash command that SUCCEEDS while printing the word error.
R=$(run_observer Bash "0 errors found
build completed successfully" 2)
[ "$R" = "0" ] && pass "T2: successful Bash printing '0 errors found' is not an error" \
  || fail "T2: Bash wrongly flagged (got '$R')"

# 3. A Grep over log files whose MATCHES contain the word error.
GREP_OUT='{"mode":"content","numLines":3,"filenames":["/var/log/app.log"],"content":"app.log:12:  [error] retry scheduled\napp.log:44:  failed to reconnect\napp.log:88:  exception swallowed"}'
R=$(run_observer Grep "$GREP_OUT" 3)
[ "$R" = "0" ] && pass "T3: successful Grep whose matches mention errors is not an error" \
  || fail "T3: Grep wrongly flagged (got '$R')"

echo ""
echo "--- Observer: real failures MUST be flagged ---"

# 4. Bash permission failure — hard marker on execution output.
R=$(run_observer Bash "bash: /usr/local/bin/deploy: Permission denied" 4)
[ "$R" = "1" ] && pass "T4: Bash 'Permission denied' is flagged" \
  || fail "T4: Bash failure missed (got '$R')"

# 5. Edit failure. Non-Bash, so it survives only via the short-verdict path (v4.9.0).
R=$(run_observer Edit "Error: String to replace not found in file." 5)
[ "$R" = "1" ] && pass "T5: Edit 'String to replace not found' is flagged" \
  || fail "T5: Edit failure missed (got '$R')"

# 6. Read failure. Same path; the gap this closed — nobody flagged it before v4.9.0.
R=$(run_observer Read "File does not exist." 6)
[ "$R" = "1" ] && pass "T6: Read 'File does not exist' is flagged" \
  || fail "T6: Read failure missed (got '$R')"

echo ""
echo "--- Observer: the length discriminator holds ---"

# 7. A LONG non-Bash payload that merely contains a marker inside its content must stay
#    clean — this is what separates a verdict from data, and what T1/T3 rely on.
LONG=$(printf '{"type":"text","file":{"filePath":"/tmp/big.ts","content":"%s String to replace not found %s"}}' \
  "$(printf 'x%.0s' $(seq 1 400))" "$(printf 'y%.0s' $(seq 1 400))")
R=$(run_observer Read "$LONG" 7)
[ "$R" = "0" ] && pass "T7: long Read payload containing a marker in content stays unflagged" \
  || fail "T7: long payload wrongly flagged (got '$R')"

echo ""
echo "--- Learner: isRealError re-validates legacy flags ---"

# The learner must not trust is_error written by observers older than the fix. These
# observations are already on disk in the wild, and the learner re-reads that window.
if grep -q "function isRealError" "$LEARNER"; then
  pass "T8: learner defines isRealError() to re-validate is_error"
else
  fail "T8: isRealError() missing from learner"
fi

if grep -q "String to replace not found" "$LEARNER" \
   && grep -q "File does not exist" "$LEARNER"; then
  pass "T9: HARD_ERR_RE covers non-Bash tool failures (Edit + Read)"
else
  fail "T9: HARD_ERR_RE misses non-Bash failure markers"
fi

# isRealError must be tool-agnostic: the Bash-only restriction belongs to the observer's
# marker branch, not to re-validation, or PowerShell/MCP failures would be discarded.
if grep -A 3 "function isRealError" "$LEARNER" | grep -q 'tool'; then
  fail "T10: isRealError filters by tool — non-Bash failures would be discarded"
else
  pass "T10: isRealError is tool-agnostic (PowerShell/MCP failures survive)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
