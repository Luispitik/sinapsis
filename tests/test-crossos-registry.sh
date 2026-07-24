#!/bin/bash
# Tests for the cross-OS project-registry de-dup in core/_session-learner.sh.
#
# Scenario: the SAME project is seen from two machines with different OS roots and no git
# remote. observe_v3.py derives the per-project id from sha256(remote || root), so a
# no-remote project gets a DIFFERENT id on each OS (the root differs: /Users/me vs
# C:/Users/Me). With a shared registry (e.g. a synced folder) the project would otherwise
# appear twice. The learner must collapse the two sightings into ONE entry that carries
# both per-OS roots, registering each per-OS id as an alias.
#
# Drives the REAL hook in a hermetic temp HOME (no SINAPSIS_* overrides exist for the
# learner; it reads process.env.HOME, so we point HOME at a sandbox).
# Run: bash tests/test-crossos-registry.sh

# Git Bash (MSYS) rewrites posix-looking argv (/Users/...) into C:/Program Files/Git/...
# before node ever sees it, so every posix fixture silently becomes a windows path and
# roots.posix never registers. Disable path conversion for this whole suite.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LEARNER="$SCRIPT_DIR/../core/_session-learner.sh"

pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }

echo "=== Cross-OS Registry Tests ==="
echo ""

TODAY=$(date -u +%Y-%m-%dT)

# obs <ts-suffix> <tool> <project_name> <cwd> — one observation line (no remote).
obs() {
  node -e 'console.log(JSON.stringify({
    timestamp: process.argv[1], event: "tool_complete", tool: process.argv[2],
    project_name: process.argv[3], project_id: "global", cwd: process.argv[4],
    is_error: false, input: "{}", output: ""
  }))' "$1" "$2" "$3" "$4"
}

# newhome — hermetic HOME with the dirs the learner expects; .last-learn is old.
newhome() {
  local h; h=$(mktemp -d)
  mkdir -p "$h/.claude/skills" "$h/.claude/homunculus/projects"
  echo "old" > "$h/.claude/homunculus/.last-learn"
  echo "$h"
}

# seed_pj <home> <hash> <name> <root> — legacy projects.json gives the learner a root
# without needing a real git repo at cwd.
seed_pj() {
  node -e 'const fs=require("fs");const f=process.argv[1];let o={};
    try{o=JSON.parse(fs.readFileSync(f,"utf8"))}catch(e){}
    o[process.argv[2]]={name:process.argv[3],root:process.argv[4]};
    fs.writeFileSync(f,JSON.stringify(o))' \
    "$1/.claude/homunculus/projects.json" "$2" "$3" "$4"
}

# add_run <home> <hash> <name> <root> — write 3 obs for a project dir + seed its root.
add_run() {
  local home="$1" hash="$2" name="$3" root="$4"
  mkdir -p "$home/.claude/homunculus/projects/$hash"
  {
    obs "${TODAY}10:00:00Z" Edit "$name" "$root"
    obs "${TODAY}10:01:00Z" Bash "$name" "$root"
    obs "${TODAY}10:02:00Z" Read "$name" "$root"
  } > "$home/.claude/homunculus/projects/$hash/observations.jsonl"
  seed_pj "$home" "$hash" "$name" "$root"
  HOME="$home" bash "$LEARNER" >/dev/null 2>&1
}

reg() { cat "$1/.claude/skills/_sinapsis-projects.json" 2>/dev/null; }
field() { node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{const r=JSON.parse(d);console.log($1)})"; }

# ── Tests 1-3: same no-remote project from two OSes collapses into one entry ──
echo "--- Same project, two OSes, no remote ---"
H=$(newhome)
add_run "$H" "aaaaaaaaaaaa" "CrossProj" "/Users/tester/CrossProj"
add_run "$H" "bbbbbbbbbbbb" "CrossProj" "C:/Users/Tester/CrossProj"
R=$(reg "$H")

N=$(echo "$R" | field "r.projects.length")
[ "$N" = "1" ] && pass "Two OS sightings collapsed into ONE entry" || fail "Expected 1 entry, got '$N'"

BOTH=$(echo "$R" | field "(r.projects[0]&&r.projects[0].roots&&r.projects[0].roots.posix&&r.projects[0].roots.windows)?'yes':'no'")
[ "$BOTH" = "yes" ] && pass "Both posix and windows roots recorded" \
  || fail "roots incomplete: $(echo "$R" | field 'JSON.stringify((r.projects[0]||{}).roots)')"

ALIAS=$(echo "$R" | field "(r.projects[0]&&(r.projects[0].aliases||[]).includes('bbbbbbbbbbbb'))?'yes':'no'")
[ "$ALIAS" = "yes" ] && pass "Second per-OS id registered as alias" \
  || fail "alias missing: $(echo "$R" | field 'JSON.stringify((r.projects[0]||{}).aliases)')"

# ── Test 4: a project WITH a remote keeps a remote-based key and does not merge by name ──
echo "--- Remote key takes precedence over name ---"
H2=$(newhome)
add_run "$H2" "cccccccccccc" "DupName" "/Users/tester/DupName"
# second project, same folder name but a real remote → must stay separate
mkdir -p "$H2/.claude/homunculus/projects/dddddddddddd"
{
  obs "${TODAY}12:00:00Z" Edit "DupName" "/Users/tester/other/DupName"
  obs "${TODAY}12:01:00Z" Bash "DupName" "/Users/tester/other/DupName"
  obs "${TODAY}12:02:00Z" Read "DupName" "/Users/tester/other/DupName"
} > "$H2/.claude/homunculus/projects/dddddddddddd/observations.jsonl"
node -e 'const fs=require("fs");const f=process.argv[1];let o={};
  try{o=JSON.parse(fs.readFileSync(f,"utf8"))}catch(e){}
  o["dddddddddddd"]={name:"DupName",root:"/Users/tester/other/DupName",remote:"https://example.com/x/dupname.git"};
  fs.writeFileSync(f,JSON.stringify(o))' "$H2/.claude/homunculus/projects.json"
HOME="$H2" bash "$LEARNER" >/dev/null 2>&1
R2=$(reg "$H2")
N2=$(echo "$R2" | field "r.projects.length")
[ "$N2" = "2" ] && pass "Remote-keyed project stays separate from name-keyed namesake" \
  || fail "Expected 2 entries, got '$N2'"

# ── Test 5: idempotent — re-running the same machine does not duplicate ──
echo "--- Idempotency ---"
add_run "$H" "aaaaaaaaaaaa" "CrossProj" "/Users/tester/CrossProj"
N3=$(reg "$H" | field "r.projects.length")
[ "$N3" = "1" ] && pass "Re-run of an existing sighting is idempotent" || fail "Expected 1 entry, got '$N3'"

# ── Test 6 (anti-regression): same name, SAME OS family must stay separate ──
# ~/work/app and ~/personal/app are two different no-remote projects that happen to
# share a folder name. The name-key fallback must NOT collapse them: it only applies
# when the OS families differ (the genuine cross-OS scenario).
echo "--- Same name, same OS family stays separate ---"
H3=$(newhome)
add_run "$H3" "eeeeeeeeeeee" "app" "/Users/tester/work/app"
add_run "$H3" "ffffffffffff" "app" "/Users/tester/personal/app"
R3=$(reg "$H3")
N4=$(echo "$R3" | field "r.projects.length")
[ "$N4" = "2" ] && pass "Two same-named no-remote projects on the SAME family stay 2 entries" \
  || fail "Expected 2 entries, got '$N4': $(echo "$R3" | field 'JSON.stringify(r.projects.map(p=>p.root))')"
BOTHROOTS=$(echo "$R3" | field "(r.projects.some(p=>p.root==='/Users/tester/work/app')&&r.projects.some(p=>p.root==='/Users/tester/personal/app'))?'yes':'no'")
[ "$BOTHROOTS" = "yes" ] && pass "Neither same-family root was overwritten" \
  || fail "a root disappeared: $(echo "$R3" | field 'JSON.stringify(r.projects.map(p=>p.root))')"

# ── Tests 7-8: migration pass cures PRE-EXISTING duplicates ──
# A registry synced via Nextcloud already contains both per-OS entries (written by
# machines running the pre-feature learner: no crossKey, no roots map). One learner
# run must merge them: union aliases/roots, oldest created, newest last_seen.
echo "--- Migration pass: pre-existing duplicates ---"
H4=$(newhome)
node -e 'const fs=require("fs");
  const reg={version:"4.1",system:"sinapsis",projects:[
    {id:"111111111111",name:"OldProj",root:"/Users/tester/OldProj",created:"2026-01-01T00:00:00Z",last_seen:"2026-01-02T00:00:00Z"},
    {id:"222222222222",name:"OldProj",root:"C:/Users/Tester/OldProj",created:"2026-01-03T00:00:00Z",last_seen:"2026-01-04T00:00:00Z"}
  ]};
  fs.writeFileSync(process.argv[1],JSON.stringify(reg))' "$H4/.claude/skills/_sinapsis-projects.json"
add_run "$H4" "gggggggggggg" "Fresh" "/Users/tester/Fresh"
R4=$(reg "$H4")
NM=$(echo "$R4" | field "r.projects.filter(p=>p&&p.name==='OldProj').length")
[ "$NM" = "1" ] && pass "Pre-existing cross-OS duplicates merged into one entry" \
  || fail "Expected 1 OldProj entry, got '$NM'"
MR=$(echo "$R4" | field "(function(){const p=r.projects.find(p=>p&&p.name==='OldProj');if(!p)return 'missing';
  return (p.roots&&p.roots.posix==='/Users/tester/OldProj'&&p.roots.windows==='C:/Users/Tester/OldProj'
    &&(p.aliases||[]).includes('222222222222')
    &&p.created==='2026-01-01T00:00:00Z'&&p.last_seen==='2026-01-04T00:00:00Z')?'yes':'no'})()")
[ "$MR" = "yes" ] && pass "Merged entry: union roots+aliases, oldest created, newest last_seen" \
  || fail "merged entry wrong ($MR): $(echo "$R4" | field 'JSON.stringify(r.projects)')"

# ── Test 9: Git Bash /c/... roots classify as the windows family ──
# observe_v3.py normally emits C:/... cwds, but a Git Bash shell can produce /c/...;
# osFamily() handles that branch, so cover it: a /c/ sighting must merge with the
# posix entry (families differ) and land under roots.windows.
echo "--- Git Bash /c/ path branch ---"
H5=$(newhome)
add_run "$H5" "hhhhhhhhhhhh" "GBProj" "/Users/tester/GBProj"
add_run "$H5" "iiiiiiiiiiii" "GBProj" "/c/Users/Tester/GBProj"
R5=$(reg "$H5")
N5=$(echo "$R5" | field "r.projects.length")
GB=$(echo "$R5" | field "(r.projects[0]&&r.projects[0].roots&&r.projects[0].roots.windows==='/c/Users/Tester/GBProj')?'yes':'no'")
if [ "$N5" = "1" ] && [ "$GB" = "yes" ]; then
  pass "Git Bash /c/ root classified as windows family and merged cross-OS"
else
  fail "expected 1 entry with roots.windows=/c/Users/Tester/GBProj, got n=$N5 gb=$GB"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
