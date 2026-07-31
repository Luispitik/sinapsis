#!/bin/bash
# Tests for inline regex flag groups in trigger patterns.
#
# Context (v4.9.1): trigger patterns are written by the model when an instinct is
# created, and `(?i)` is the reflex spelling for anyone used to Python or grep. But
# JavaScript has no inline flags: `new RegExp("(?i)foo")` throws "Invalid group".
# Both activators compiled patterns inside a try/catch whose handler was a bare
# `continue`, so such an instinct was dropped in total silence — it sat in the index
# looking perfectly healthy, valid JSON, right level, and never fired once. One index
# in the wild had 50 of 57 instincts dead this way; the survivors were simply the
# ones nobody had prefixed.
#
# These tests pin the three halves of the fix: the activator matches despite the
# flag group, it says so in the log when a pattern genuinely cannot compile, and
# /dream names the inline-flag case instead of the generic "invalid_regex".
#
# Run: bash tests/test-inline-regex-flags.sh

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ACTIVATOR="$SCRIPT_DIR/../core/_instinct-activator.sh"
PASSIVE="$SCRIPT_DIR/../core/_passive-activator.sh"
DREAM="$SCRIPT_DIR/../core/_dream.sh"

pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

echo "=== Inline Regex Flag Tests ==="
echo ""

# ── TEST 1: the bug is real — JS rejects (?i) ────────────────────────────────
echo "--- Test 1: JavaScript rejects inline flag groups ---"
OUT=$(node -e 'try { new RegExp("(?i)foo","i"); console.log("compiled"); } catch(e) { console.log("threw"); }')
[ "$OUT" = "threw" ] && pass "new RegExp(\"(?i)foo\") throws — the premise holds" \
                     || fail "Expected throw, got '$OUT'"

# ── TEST 2: normalizeInlineFlags is present in both activators ───────────────
echo "--- Test 2: both activators normalise inline flags ---"
A=$(grep -c "normalizeInlineFlags" "$ACTIVATOR")
P=$(grep -c "normalizeInlineFlags" "$PASSIVE")
{ [ "$A" -ge 2 ] && [ "$P" -ge 2 ]; } && pass "instinct + passive activators both normalise" \
                                      || fail "instinct=$A passive=$P occurrences (want >=2 each)"

# ── TEST 3: a (?i)-prefixed instinct actually matches ────────────────────────
# The whole point: an index written the natural way must still fire.
echo "--- Test 3: a (?i) instinct fires instead of vanishing ---"
H=$(mktemp -d)
mkdir -p "$H/.claude/skills"
cat > "$H/.claude/skills/_instincts-index.json" << 'EOF'
{
  "version": "1.0",
  "instincts": [
    {
      "id": "inline-flag-canary",
      "domain": "tooling",
      "level": "confirmed",
      "trigger_pattern": "(?i)(canary-token)",
      "inject": "The canary fired.",
      "occurrences": 0
    }
  ],
  "archived": []
}
EOF
OUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"echo CANARY-TOKEN"}}' \
      | HOME="$H" bash "$ACTIVATOR" 2>/dev/null)
echo "$OUT" | grep -q "The canary fired" \
  && pass "(?i) pattern matched (and case-insensitively)" \
  || fail "Canary did not fire. Output: ${OUT:-<empty>}"

# ── TEST 4: a genuinely broken pattern is LOGGED, not swallowed ──────────────
# Silence was the reason this went unnoticed for months.
echo "--- Test 4: an uncompilable pattern is reported ---"
H2=$(mktemp -d)
mkdir -p "$H2/.claude/skills"
cat > "$H2/.claude/skills/_instincts-index.json" << 'EOF'
{
  "version": "1.0",
  "instincts": [
    {
      "id": "genuinely-broken",
      "domain": "tooling",
      "level": "confirmed",
      "trigger_pattern": "([unclosed",
      "inject": "never",
      "occurrences": 0
    }
  ],
  "archived": []
}
EOF
echo '{"tool_name":"Bash","tool_input":{"command":"anything"}}' \
  | HOME="$H2" bash "$ACTIVATOR" >/dev/null 2>&1
if grep -q "BAD_PATTERN | genuinely-broken" "$H2/.claude/skills/_instinct.log" 2>/dev/null; then
  pass "Uncompilable pattern logged as BAD_PATTERN"
else
  fail "Nothing logged — the failure is still silent"
fi

# ── TEST 5: /dream names the inline-flag case ────────────────────────────────
echo "--- Test 5: dream distinguishes inline_flag_group from invalid_regex ---"
H3=$(mktemp -d)
mkdir -p "$H3/.claude/skills"
cat > "$H3/.claude/skills/_instincts-index.json" << 'EOF'
{
  "version": "1.0",
  "instincts": [
    { "id": "flagged",  "domain": "tooling", "level": "confirmed",
      "trigger_pattern": "(?i)(alpha)", "inject": "a", "occurrences": 0 },
    { "id": "trulybad", "domain": "tooling", "level": "confirmed",
      "trigger_pattern": "([unclosed", "inject": "b", "occurrences": 0 }
  ],
  "archived": []
}
EOF
HOME="$H3" bash "$DREAM" >/dev/null 2>&1
REPORT="$H3/.claude/skills/_dream-report.md"
if [ -f "$REPORT" ]; then
  # The inline-flag case must be named, not lumped under the generic label: that
  # generic label is what made this bug take months to find. And a genuinely
  # broken pattern must still be reported as invalid_regex, so the new bucket has
  # not swallowed the old one.
  FLAGGED=$(grep "flagged" "$REPORT" | grep -c "inline_flag_group")
  BROKEN=$(grep "trulybad" "$REPORT" | grep -c "invalid_regex")
  { [ "$FLAGGED" -ge 1 ] && [ "$BROKEN" -ge 1 ]; } \
    && pass "dream reports inline_flag_group and invalid_regex separately" \
    || fail "flagged->inline_flag_group=$FLAGGED trulybad->invalid_regex=$BROKEN (want >=1 each)"
else
  fail "dream produced no report"
fi

# ── Summary ──
echo ""
echo "=== Results: $PASS passed, $FAIL failed (of $((PASS + FAIL))) ==="
[ "$FAIL" -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $FAIL
