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
# Since #32 the family of a sighting is a FACT taken from uname -s at observation time
# (Darwin -> mac, Linux -> linux, MINGW*/MSYS* -> windows), so mac<->linux also merges;
# the legacy 2-family "posix" key is left alone and rewritten by its own machine.
#
# Drives the REAL hook in a hermetic temp HOME (it reads process.env.HOME, so we point
# HOME at a sandbox; SINAPSIS_UNAME simulates the machine each sighting happens on).
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
  # MSYS path conversion is disabled for this suite (see top of file), so node — a native
  # Windows binary under Git Bash — resolves a posix "/tmp/..." to "C:\tmp\..." and every
  # fixture write dies with ENOENT. Hand it a path it can actually open.
  h=$(cd "$h" && { pwd -W 2>/dev/null || pwd; })
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

# add_run <home> <hash> <name> <root> <uname> — write 3 obs for a project dir + seed
# its root, then run the learner as if on machine <uname> (Darwin, Linux, MINGW64_NT).
# "unknown" exercises the no-uname fallback: classification by path shape (legacy keys).
add_run() {
  local home="$1" hash="$2" name="$3" root="$4" un="${5:-unknown}"
  mkdir -p "$home/.claude/homunculus/projects/$hash"
  {
    obs "${TODAY}10:00:00Z" Edit "$name" "$root"
    obs "${TODAY}10:01:00Z" Bash "$name" "$root"
    obs "${TODAY}10:02:00Z" Read "$name" "$root"
  } > "$home/.claude/homunculus/projects/$hash/observations.jsonl"
  seed_pj "$home" "$hash" "$name" "$root"
  HOME="$home" SINAPSIS_UNAME="$un" bash "$LEARNER" >/dev/null 2>&1
}

reg() { cat "$1/.claude/skills/_sinapsis-projects.json" 2>/dev/null; }
field() { node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{const r=JSON.parse(d);console.log($1)})"; }

# ── Tests 1-3: same no-remote project from two OSes collapses into one entry ──
echo "--- Same project, two OSes, no remote ---"
H=$(newhome)
add_run "$H" "aaaaaaaaaaaa" "CrossProj" "/Users/tester/CrossProj" Darwin
add_run "$H" "bbbbbbbbbbbb" "CrossProj" "C:/Users/Tester/CrossProj" MINGW64_NT-10.0
R=$(reg "$H")

N=$(echo "$R" | field "r.projects.length")
[ "$N" = "1" ] && pass "Two OS sightings collapsed into ONE entry" || fail "Expected 1 entry, got '$N'"

BOTH=$(echo "$R" | field "(r.projects[0]&&r.projects[0].roots&&r.projects[0].roots.mac&&r.projects[0].roots.windows)?'yes':'no'")
[ "$BOTH" = "yes" ] && pass "Both mac and windows roots recorded under their fact keys" \
  || fail "roots incomplete: $(echo "$R" | field 'JSON.stringify((r.projects[0]||{}).roots)')"

ALIAS=$(echo "$R" | field "(r.projects[0]&&(r.projects[0].aliases||[]).includes('bbbbbbbbbbbb'))?'yes':'no'")
[ "$ALIAS" = "yes" ] && pass "Second per-OS id registered as alias" \
  || fail "alias missing: $(echo "$R" | field 'JSON.stringify((r.projects[0]||{}).aliases)')"

# ── Test 4: a project WITH a remote keeps a remote-based key and does not merge by name ──
echo "--- Remote key takes precedence over name ---"
H2=$(newhome)
add_run "$H2" "cccccccccccc" "DupName" "/Users/tester/DupName" Darwin
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
HOME="$H2" SINAPSIS_UNAME=Darwin bash "$LEARNER" >/dev/null 2>&1
R2=$(reg "$H2")
N2=$(echo "$R2" | field "r.projects.length")
[ "$N2" = "2" ] && pass "Remote-keyed project stays separate from name-keyed namesake" \
  || fail "Expected 2 entries, got '$N2'"

# ── Test 5: idempotent — re-running the same machine does not duplicate ──
echo "--- Idempotency ---"
add_run "$H" "aaaaaaaaaaaa" "CrossProj" "/Users/tester/CrossProj" Darwin
N3=$(reg "$H" | field "r.projects.length")
[ "$N3" = "1" ] && pass "Re-run of an existing sighting is idempotent" || fail "Expected 1 entry, got '$N3'"

# ── Test 6 (anti-regression): same name, SAME OS family must stay separate ──
# ~/work/app and ~/personal/app are two different no-remote projects that happen to
# share a folder name. The name-key fallback must NOT collapse them: it only applies
# when the OS families differ (the genuine cross-OS scenario).
echo "--- Same name, same OS family stays separate ---"
H3=$(newhome)
add_run "$H3" "eeeeeeeeeeee" "app" "/Users/tester/work/app" Darwin
add_run "$H3" "ffffffffffff" "app" "/Users/tester/personal/app" Darwin
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
add_run "$H4" "gggggggggggg" "Fresh" "/Users/tester/Fresh" Darwin
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

# ── Test 9: Git Bash /c/... roots land under the windows family ──
# observe_v3.py normally emits C:/... cwds, but a Git Bash shell can produce /c/...;
# the MINGW uname classifies the sighting as windows (and pathFamily() still proves
# windows for /c/ shapes in the fallback), so cover it: a /c/ sighting must merge
# with the mac entry (families differ) and land under roots.windows.
echo "--- Git Bash /c/ path branch ---"
H5=$(newhome)
add_run "$H5" "hhhhhhhhhhhh" "GBProj" "/Users/tester/GBProj" Darwin
add_run "$H5" "iiiiiiiiiiii" "GBProj" "/c/Users/Tester/GBProj" MINGW64_NT-10.0
R5=$(reg "$H5")
N5=$(echo "$R5" | field "r.projects.length")
GB=$(echo "$R5" | field "(r.projects[0]&&r.projects[0].roots&&r.projects[0].roots.windows==='/c/Users/Tester/GBProj')?'yes':'no'")
if [ "$N5" = "1" ] && [ "$GB" = "yes" ]; then
  pass "Git Bash /c/ root classified as windows family and merged cross-OS"
else
  fail "expected 1 entry with roots.windows=/c/Users/Tester/GBProj, got n=$N5 gb=$GB"
fi

# ── Tests 11-12: a name-key fusion is ACCEPTED but never silent ──
# Two UNRELATED projects that merely share a folder name, seen from different OS
# families with no remote, still merge — nothing is left to tell them apart. That is
# the accepted limit of the "name:" fallback. What must NOT happen is that it merges
# quietly: the entry carries name_merged + the offending root pair, so a wrong fusion
# is auditable and reversible by hand.
echo ""
echo "--- Name-key fusion is stamped, not silent ---"
H6=$(newhome)
add_run "$H6" "jjjjjjjjjjjj" "app" "C:/work/app" MINGW64_NT-10.0
add_run "$H6" "kkkkkkkkkkkk" "app" "/home/other/personal/app" Linux
R6=$(reg "$H6")

STAMP=$(echo "$R6" | field "(r.projects[0]&&r.projects[0].name_merged===true)?'yes':'no'")
[ "$STAMP" = "yes" ] && pass "Cross-family name fusion stamped with name_merged" \
  || fail "name_merged missing: $(echo "$R6" | field 'JSON.stringify(r.projects[0]||{})')"

LOG=$(echo "$R6" | field "(r.projects[0]&&(r.projects[0].name_merge_log||[]).some(s=>s.indexOf('C:/work/app')>=0&&s.indexOf('/home/other/personal/app')>=0))?'yes':'no'")
[ "$LOG" = "yes" ] && pass "Both roots recorded in name_merge_log for audit" \
  || fail "name_merge_log incomplete: $(echo "$R6" | field 'JSON.stringify((r.projects[0]||{}).name_merge_log)')"

# ── Test 13: a legitimate remote-keyed merge is NOT stamped (no false alarm) ──
echo ""
echo "--- Remote-keyed merge stays unstamped ---"
H7=$(newhome)
mkdir -p "$H7/.claude/homunculus/projects/llllllllllll"
obs "${TODAY}10:00:00Z" Edit "RemoteProj" "/Users/tester/RemoteProj" > "$H7/.claude/homunculus/projects/llllllllllll/observations.jsonl"
obs "${TODAY}10:01:00Z" Bash "RemoteProj" "/Users/tester/RemoteProj" >> "$H7/.claude/homunculus/projects/llllllllllll/observations.jsonl"
obs "${TODAY}10:02:00Z" Read "RemoteProj" "/Users/tester/RemoteProj" >> "$H7/.claude/homunculus/projects/llllllllllll/observations.jsonl"
node -e 'const fs=require("fs");const f=process.argv[1];let o={};try{o=JSON.parse(fs.readFileSync(f,"utf8"))}catch(e){}
  o["llllllllllll"]={name:"RemoteProj",root:"/Users/tester/RemoteProj",remote:"https://example.com/x/remoteproj.git"};
  fs.writeFileSync(f,JSON.stringify(o))' "$H7/.claude/homunculus/projects.json"
HOME="$H7" SINAPSIS_UNAME=Darwin bash "$LEARNER" >/dev/null 2>&1
R7=$(reg "$H7")
UNSTAMPED=$(echo "$R7" | field "(r.projects[0]&&!r.projects[0].name_merged)?'yes':'no'")
[ "$UNSTAMPED" = "yes" ] && pass "Remote-keyed entry carries no name_merged stamp" \
  || fail "remote-keyed entry wrongly stamped: $(echo "$R7" | field 'JSON.stringify(r.projects[0]||{})')"

# ── Tests 14-15 (#32): mac and linux are now distinct families and merge ──
echo ""
echo "--- mac <-> linux sightings merge (#32) ---"
H8=$(newhome)
add_run "$H8" "mmmmmmmmmmm1" "TriProj" "/Users/me/TriProj" Darwin
add_run "$H8" "mmmmmmmmmmm2" "TriProj" "/home/me/TriProj" Linux
R8=$(reg "$H8")
N8=$(echo "$R8" | field "r.projects.length")
[ "$N8" = "1" ] && pass "mac + linux sightings collapsed into ONE entry" \
  || fail "Expected 1 entry, got '$N8': $(echo "$R8" | field 'JSON.stringify(r.projects.map(p=>p.root))')"
TRI=$(echo "$R8" | field "(r.projects[0]&&r.projects[0].roots&&r.projects[0].roots.mac==='/Users/me/TriProj'&&r.projects[0].roots.linux==='/home/me/TriProj')?'yes':'no'")
[ "$TRI" = "yes" ] && pass "roots.mac and roots.linux both recorded as facts" \
  || fail "roots wrong: $(echo "$R8" | field 'JSON.stringify((r.projects[0]||{}).roots)')"

# ── Test 16 (#32): a legacy posix key is NOT guessed at — no mac/linux merge ──
# A v4.9.0 registry entry carries roots.posix; posix may be mac OR linux, so a linux
# sighting from another machine must NOT merge with it (same-machine guard stays safe).
echo ""
echo "--- Legacy posix key blocks mac/linux merge until rewritten ---"
H9=$(newhome)
node -e 'const fs=require("fs");
  const reg={version:"4.1",system:"sinapsis",projects:[
    {id:"ppppppppppp1",crossKey:"name:legacyproj",name:"LegacyProj",root:"/Users/me/LegacyProj",
     roots:{posix:"/Users/me/LegacyProj"},aliases:[],created:"2026-01-01T00:00:00Z",last_seen:"2026-01-02T00:00:00Z"}
  ]};
  fs.writeFileSync(process.argv[1],JSON.stringify(reg))' "$H9/.claude/skills/_sinapsis-projects.json"
add_run "$H9" "ppppppppppp2" "LegacyProj" "/home/me/LegacyProj" Linux
R9=$(reg "$H9")
N9=$(echo "$R9" | field "r.projects.length")
[ "$N9" = "2" ] && pass "Linux sighting did NOT merge into the legacy posix entry" \
  || fail "Expected 2 entries, got '$N9': $(echo "$R9" | field 'JSON.stringify(r.projects.map(p=>p.roots))')"
KEPT=$(echo "$R9" | field "(r.projects.some(p=>p.roots&&p.roots.posix==='/Users/me/LegacyProj'))?'yes':'no'")
[ "$KEPT" = "yes" ] && pass "Legacy posix key left untouched (not reclassified)" \
  || fail "posix key was altered: $(echo "$R9" | field 'JSON.stringify(r.projects.map(p=>p.roots))')"

# ── Test 17 (#32): each machine rewrites its own key, and THEN the merge heals ──
# The mac re-sights its project (same id, same path): roots.mac supersedes the posix
# key it wrote under the 2-family model. The migration pass in that same run can now
# prove the linux entry is a different family, and the pair finally merges.
echo ""
echo "--- Rewrite-own-key heals the legacy entry ---"
add_run "$H9" "ppppppppppp1" "LegacyProj" "/Users/me/LegacyProj" Darwin
R9b=$(reg "$H9")
N9b=$(echo "$R9b" | field "r.projects.length")
HEAL=$(echo "$R9b" | field "(function(){const p=r.projects[0];if(!p||!p.roots)return 'no';
  return (p.roots.mac==='/Users/me/LegacyProj'&&p.roots.linux==='/home/me/LegacyProj'&&!p.roots.posix)?'yes':'no'})()")
if [ "$N9b" = "1" ] && [ "$HEAL" = "yes" ]; then
  pass "Mac re-sighting rewrote posix -> mac and the linux entry merged in"
else
  fail "expected 1 healed entry (mac+linux, no posix), got n=$N9b: $(echo "$R9b" | field 'JSON.stringify(r.projects.map(p=>p.roots))')"
fi

# ── Test 18 (anti-regression): windows <-> legacy posix still merges as in v4.9.0 ──
echo ""
echo "--- Windows sighting still merges with a legacy posix entry ---"
H10=$(newhome)
node -e 'const fs=require("fs");
  const reg={version:"4.1",system:"sinapsis",projects:[
    {id:"qqqqqqqqqqq1",crossKey:"name:winproj",name:"WinProj",root:"/Users/me/WinProj",
     roots:{posix:"/Users/me/WinProj"},aliases:[],created:"2026-01-01T00:00:00Z",last_seen:"2026-01-02T00:00:00Z"}
  ]};
  fs.writeFileSync(process.argv[1],JSON.stringify(reg))' "$H10/.claude/skills/_sinapsis-projects.json"
add_run "$H10" "qqqqqqqqqqq2" "WinProj" "C:/Users/Me/WinProj" MINGW64_NT-10.0
R10=$(reg "$H10")
N10=$(echo "$R10" | field "r.projects.length")
W10=$(echo "$R10" | field "(r.projects[0]&&r.projects[0].roots&&r.projects[0].roots.posix==='/Users/me/WinProj'&&r.projects[0].roots.windows==='C:/Users/Me/WinProj')?'yes':'no'")
if [ "$N10" = "1" ] && [ "$W10" = "yes" ]; then
  pass "Windows sighting merged with the legacy posix entry (v4.9.0 behavior kept)"
else
  fail "expected 1 entry with posix+windows roots, got n=$N10: $(echo "$R10" | field 'JSON.stringify(r.projects.map(p=>p.roots))')"
fi

# ── Test 19 (#32): migration pass merges two fact-keyed entries (synced registry) ──
echo ""
echo "--- Migration merges roots.mac + roots.linux entries ---"
H11=$(newhome)
node -e 'const fs=require("fs");
  const reg={version:"4.1",system:"sinapsis",projects:[
    {id:"rrrrrrrrrrr1",crossKey:"name:syncproj",name:"SyncProj",root:"/Users/x/SyncProj",
     roots:{mac:"/Users/x/SyncProj"},aliases:[],created:"2026-02-01T00:00:00Z",last_seen:"2026-02-02T00:00:00Z"},
    {id:"rrrrrrrrrrr2",crossKey:"name:syncproj",name:"SyncProj",root:"/home/x/SyncProj",
     roots:{linux:"/home/x/SyncProj"},aliases:[],created:"2026-02-03T00:00:00Z",last_seen:"2026-02-04T00:00:00Z"}
  ]};
  fs.writeFileSync(process.argv[1],JSON.stringify(reg))' "$H11/.claude/skills/_sinapsis-projects.json"
add_run "$H11" "ssssssssssss" "Fresh2" "/Users/tester/Fresh2" Darwin
R11=$(reg "$H11")
NS=$(echo "$R11" | field "r.projects.filter(p=>p&&p.name==='SyncProj').length")
SY=$(echo "$R11" | field "(function(){const p=r.projects.find(p=>p&&p.name==='SyncProj');if(!p||!p.roots)return 'no';
  return (p.roots.mac==='/Users/x/SyncProj'&&p.roots.linux==='/home/x/SyncProj'&&(p.aliases||[]).includes('rrrrrrrrrrr2'))?'yes':'no'})()")
if [ "$NS" = "1" ] && [ "$SY" = "yes" ]; then
  pass "Two fact-keyed per-OS entries merged by the migration pass"
else
  fail "expected 1 SyncProj with mac+linux roots, got n=$NS sy=$SY: $(echo "$R11" | field 'JSON.stringify(r.projects)')"
fi

# ── Test 20 (#32 review): a multi-family entry must not fold into a same-family rival ──
# K was seen from the mac at work/app; P is a DIFFERENT project (personal/app, on that
# same mac) later also seen from linux. P's LAST family is linux, which K lacks — but
# folding P into K would silently drop P's mac root and erase a project. The migration
# guard must check EVERY family root P carries, not just the last-seen one.
echo ""
echo "--- Migration refuses a multi-family fold that would drop a root ---"
H13=$(newhome)
node -e 'const fs=require("fs");
  const reg={version:"4.1",system:"sinapsis",projects:[
    {id:"uuuuuuuuuuu1",crossKey:"name:app",name:"app",root:"/Users/me/work/app",
     roots:{mac:"/Users/me/work/app"},aliases:[],created:"2026-03-01T00:00:00Z",last_seen:"2026-03-02T00:00:00Z"},
    {id:"uuuuuuuuuuu2",crossKey:"name:app",name:"app",root:"/home/ci/app",
     roots:{mac:"/Users/me/personal/app",linux:"/home/ci/app"},aliases:[],created:"2026-03-03T00:00:00Z",last_seen:"2026-03-04T00:00:00Z"}
  ]};
  fs.writeFileSync(process.argv[1],JSON.stringify(reg))' "$H13/.claude/skills/_sinapsis-projects.json"
add_run "$H13" "vvvvvvvvvvvv" "Fresh3" "/Users/tester/Fresh3" Darwin
R13=$(reg "$H13")
NA=$(echo "$R13" | field "r.projects.filter(p=>p&&p.name==='app').length")
RK=$(echo "$R13" | field "(r.projects.some(p=>p.roots&&p.roots.mac==='/Users/me/work/app')&&r.projects.some(p=>p.roots&&p.roots.mac==='/Users/me/personal/app'))?'yes':'no'")
if [ "$NA" = "2" ] && [ "$RK" = "yes" ]; then
  pass "Multi-family entry kept separate from its same-family rival (no root dropped)"
else
  fail "expected 2 app entries with both mac roots intact, got n=$NA rk=$RK: $(echo "$R13" | field 'JSON.stringify(r.projects.map(p=>p.roots))')"
fi

# ── Test 21 (fallback): no uname available -> path shape, legacy posix/windows keys ──
echo ""
echo "--- No-uname fallback keeps the 2-family behavior ---"
H12=$(newhome)
add_run "$H12" "ttttttttttt1" "FallProj" "/Users/tester/FallProj" unknown
add_run "$H12" "ttttttttttt2" "FallProj" "C:/Users/Tester/FallProj" unknown
R12=$(reg "$H12")
N12=$(echo "$R12" | field "r.projects.length")
F12=$(echo "$R12" | field "(r.projects[0]&&r.projects[0].roots&&r.projects[0].roots.posix==='/Users/tester/FallProj'&&r.projects[0].roots.windows==='C:/Users/Tester/FallProj')?'yes':'no'")
if [ "$N12" = "1" ] && [ "$F12" = "yes" ]; then
  pass "Fallback classified by path shape and merged posix <-> windows"
else
  fail "expected 1 entry with posix+windows roots, got n=$N12: $(echo "$R12" | field 'JSON.stringify(r.projects.map(p=>p.roots))')"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
