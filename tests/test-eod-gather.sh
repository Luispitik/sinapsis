#!/bin/bash
# Tests for core/_eod-gather.sh — Multi-project EOD data collector (v4.2.3)
# Drives the REAL script in a hermetic temp dir via SINAPSIS_HOMUNCULUS/SINAPSIS_SKILLS.
# Covers Bug 1 (non-git root observations) + Bug 2 (cross-OS robustness) + the
# canonical _sinapsis-projects.json registry loader.
# Run: bash tests/test-eod-gather.sh

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GATHER="$SCRIPT_DIR/../core/_eod-gather.sh"

pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

echo "=== EOD Gather Tests (v4.2.3) ==="
echo ""

# Fixtures carry UTC timestamps (…Z) but the gather counts the LOCAL day, so
# they are anchored to local noon — far from either midnight in any timezone.
# They used to be "<UTC date>T10:00:00Z", which silently fell outside the local
# day whenever the two dates disagreed (every evening west of Greenwich).
# The offset travels in the environment, not in argv: node parses a leading "-1"
# as one of its own options, and the helper would print nothing at all. An empty
# timestamp still makes Test 5 pass (it is excluded like a stale one would be),
# so the breakage would have been invisible.
iso_local_noon() {   # $1 = day offset (0 = today, -1 = yesterday)
  SINAPSIS_TEST_DAY_OFFSET="$1" node -e 'const d = new Date();
    d.setDate(d.getDate() + Number(process.env.SINAPSIS_TEST_DAY_OFFSET));
    d.setHours(12, 0, 0, 0);
    console.log(d.toISOString());'
}
TODAY=$(iso_local_noon 0)
YESTERDAY=$(iso_local_noon -1)

# Emit a generic observation.
gen_obs() {
  node -e 'console.log(JSON.stringify({
    timestamp: process.argv[1], event: "tool_complete", tool: process.argv[2],
    project_name: process.argv[3], project_id: "global", is_error: false,
    input: "{}", output: ""
  }))' "$1" "$2" "$3"
}

# Emit an Edit observation carrying a verbatim file_path (any OS path style).
gen_edit_obs() {
  node -e 'console.log(JSON.stringify({
    timestamp: process.argv[1], event: "tool_complete", tool: "Edit",
    project_name: process.argv[2], project_id: "global", is_error: false,
    input: JSON.stringify({ file_path: process.argv[3] }), output: ""
  }))' "$1" "$2" "$3"
}

# run_gather <homunculus_dir> [skills_dir]
run_gather() {
  local sk="${2:-$(mktemp -d)}"
  SINAPSIS_HOMUNCULUS="$1" SINAPSIS_SKILLS="$sk" bash "$GATHER" 2>/dev/null
}

# field "<js-expr-using-r>" — extract a value from gathered JSON on stdin.
field() { node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{const r=JSON.parse(d);console.log($1)})"; }

newhome() { local d; d=$(mktemp -d)/homunculus; mkdir -p "$d/projects"; echo "$d"; }

# ── TEST 1: Bug 1 — non-git project in root observations.jsonl is detected ──
echo "--- Test 1: Root (non-git) observations detected ---"
H=$(newhome)
gen_edit_obs "$TODAY" "NoGitProject" "/tmp/x/a.ts"  >  "$H/observations.jsonl"
gen_obs      "$TODAY" "Bash" "NoGitProject"         >> "$H/observations.jsonl"
gen_obs      "$TODAY" "Read" "NoGitProject"         >> "$H/observations.jsonl"
N=$(run_gather "$H" | field "(r.projects.find(p=>p.name==='NoGitProject')||{}).observations_today")
[ "$N" = "3" ] && pass "Non-git root project detected (3 obs)" || fail "Expected 3, got '$N'"

# ── TEST 2: Distinct non-git projects separated by name ──
echo "--- Test 2: Distinct non-git projects separated by name ---"
H=$(newhome)
gen_obs "$TODAY" "Edit" "Alpha" >  "$H/observations.jsonl"
gen_obs "$TODAY" "Edit" "Beta"  >> "$H/observations.jsonl"
C=$(run_gather "$H" | field "r.project_count")
[ "$C" = "2" ] && pass "Two project_names → 2 projects" || fail "Expected 2, got '$C'"

# ── TEST 3: Bug 2 — cross-OS basename on a Windows-style path ──
echo "--- Test 3: Cross-OS basename (Windows \\ path) ---"
H=$(newhome)
gen_edit_obs "$TODAY" "WinProj" 'C:\Users\tester\app\page.tsx' > "$H/observations.jsonl"
F=$(run_gather "$H" | field "(r.projects.find(p=>p.name==='WinProj')||{}).files_touched.join(',')")
[ "$F" = "page.tsx" ] && pass "Windows path split to 'page.tsx'" || fail "Expected 'page.tsx', got '$F'"

# ── TEST 4: Same name from a subdir AND the root merges into one entry ──
echo "--- Test 4: Merge subdir + root by project_name ---"
H=$(newhome); mkdir -p "$H/projects/hash4"
gen_obs "$TODAY" "Edit" "Merged" >  "$H/projects/hash4/observations.jsonl"
gen_obs "$TODAY" "Bash" "Merged" >> "$H/projects/hash4/observations.jsonl"
gen_obs "$TODAY" "Read" "Merged" >  "$H/observations.jsonl"
OUT=$(run_gather "$H")
C=$(echo "$OUT" | field "r.project_count")
N=$(echo "$OUT" | field "(r.projects.find(p=>p.name==='Merged')||{}).observations_today")
{ [ "$C" = "1" ] && [ "$N" = "3" ]; } && pass "Subdir(2)+root(1) merged → 1 project, 3 obs" || fail "Expected 1/3, got count=$C obs=$N"

# ── TEST 5: Yesterday-only observations in the root are ignored ──
echo "--- Test 5: Stale root observations ignored ---"
H=$(newhome)
gen_obs "$YESTERDAY" "Edit" "StaleOne" >  "$H/observations.jsonl"
gen_obs "$TODAY"     "Edit" "FreshOne" >> "$H/observations.jsonl"
OUT=$(run_gather "$H")
S=$(echo "$OUT" | field "r.projects.some(p=>p.name==='StaleOne')")
FR=$(echo "$OUT" | field "r.projects.some(p=>p.name==='FreshOne')")
{ [ "$S" = "false" ] && [ "$FR" = "true" ]; } && pass "Today-only filter honored on root file" || fail "stale=$S fresh=$FR"

# ── TEST 6: Empty homunculus (no projects dir, no root file) → 0, no crash ──
echo "--- Test 6: Empty homunculus graceful exit ---"
H=$(mktemp -d)/homunculus; mkdir -p "$H"   # deliberately no projects/ and no observations.jsonl
C=$(run_gather "$H" | field "r.project_count")
[ "$C" = "0" ] && pass "Empty homunculus → 0 projects" || fail "Expected 0, got '$C'"

# ── TEST 7: Canonical _sinapsis-projects.json (array schema) resolves project name ──
echo "--- Test 7: Canonical _sinapsis-projects.json name resolution ---"
H=$(newhome); SK=$(mktemp -d); mkdir -p "$H/projects/abc123canon"
gen_obs "$TODAY" "Edit" "global" > "$H/projects/abc123canon/observations.jsonl"
cat > "$SK/_sinapsis-projects.json" << 'EOF'
{ "projects": [ { "id": "abc123canon", "name": "CanonName", "root": "" } ] }
EOF
NAME=$(run_gather "$H" "$SK" | field "r.projects.map(p=>p.name).join(',')")
echo "$NAME" | grep -q "CanonName" && pass "Canonical registry maps hash → 'CanonName'" || fail "Expected CanonName, got '$NAME'"

# ── TEST 8: Output is valid JSON with required fields ──
echo "--- Test 8: Valid JSON shape ---"
H=$(newhome)
gen_obs "$TODAY" "Edit" "Shape" > "$H/observations.jsonl"
OK=$(run_gather "$H" | field "(typeof r.date==='string' && typeof r.project_count==='number' && typeof r.total_observations==='number' && Array.isArray(r.projects))")
[ "$OK" = "true" ] && pass "Output has date/project_count/total_observations/projects" || fail "Bad output shape: $OK"

# ── Summary ──
echo ""
echo "=== Results: $PASS passed, $FAIL failed (of $((PASS + FAIL))) ==="
[ "$FAIL" -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $FAIL
