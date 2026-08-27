#!/bin/bash
# EOD Gather — Multi-project activity collector
# Sinapsis v4.2.3
# Scans homunculus/projects/ AND the root homunculus/observations.jsonl
# (where non-git projects land) for today's observations across ALL projects.
# Cross-OS safe: handles a Mac+Windows shared observations file (mixed \ and /
# paths, foreign roots absent locally). Groups by project_name so the same
# project merges across machines even when the cwd differs.
# Outputs JSON with project names, observation counts, tools used, and git data.
# Called by /eod command. NO LLM. Pure deterministic Node.js.
#
# v4.2.3 bug fixes (reported by Nestor PV, 2026-06-01):
#   - Bug 1: non-git projects (project_id "global") are written to the ROOT
#            observations.jsonl, but the gather only walked projects/<hash>/, so
#            /eod reported 0 despite real activity. Now reads the root too.
#   - Bug 2: cross-OS robustness — baseName() splits on both / and \ (Node's
#            path.basename is platform-specific); foreign roots are skipped;
#            HOME || USERPROFILE resolved; projects merged by name across OS.
#
# v4.9.1 bug fix (2026-07-30):
#   - "today" was computed and matched in UTC, so the reported day was the UTC
#     one, not the operator's. West of Greenwich the two disagree every evening
#     — and every scheduled close runs in the evening. Now the local day is an
#     explicit [midnight, next midnight) window and timestamps are compared as
#     instants, not string prefixes. See the comment at `dayStart`.
#
# Test overrides (defaults unchanged): SINAPSIS_HOMUNCULUS points the data dir
# elsewhere, SINAPSIS_SKILLS the registry dir. Used by tests/test-eod-gather.sh.

HOMUNCULUS="${SINAPSIS_HOMUNCULUS:-$HOME/.claude/homunculus}"

if [ "${SINAPSIS_DEBUG:-}" = "1" ]; then
  exec 2>>"$HOME/.claude/skills/_sinapsis-debug.log"
fi

if [ ! -d "$HOMUNCULUS/projects" ] && [ ! -f "$HOMUNCULUS/observations.jsonl" ]; then
  echo '{"date":"'$(date +%Y-%m-%d)'","project_count":0,"total_observations":0,"projects":[]}'
  exit 0
fi

node -e '
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const HOME = process.env.HOME || process.env.USERPROFILE || "";
const homunculus = process.env.SINAPSIS_HOMUNCULUS || path.join(HOME, ".claude", "homunculus");
const skillsDir = process.env.SINAPSIS_SKILLS || path.join(HOME, ".claude", "skills");
const projectsDir = path.join(homunculus, "projects");
const rootObsFile = path.join(homunculus, "observations.jsonl");

// The day the operator worked is the LOCAL one; observation timestamps are UTC
// (…Z). Matching a date STRING against a UTC timestamp mixes the two: in UTC-5
// the UTC bucket for a date runs from 19:00 the previous local day to 19:00
// that local day. A prefix match therefore reports the WRONG day in both
// directions — after 19:00 local it counts the next bucket (minutes old, looks
// like an empty day), and a close written from that bucket steals the previous
// evening (looks like a busier day than it was). Both were seen on 2026-07-30:
// the same day was reported as 27 observations and as ~522; the truth was 382.
// So: build the local day as an explicit [start, end) window and compare
// instants, not strings.
const now = new Date();
const dayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
// Next local midnight via the calendar, not +24h — that stays correct across a
// DST change, where a local day is 23 or 25 hours long.
const dayEnd = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1).getTime();
const pad = n => String(n).padStart(2, "0");
const today = now.getFullYear() + "-" + pad(now.getMonth() + 1) + "-" + pad(now.getDate());

function isToday(ts) {
  if (!ts) return false;
  const t = Date.parse(ts);
  return Number.isFinite(t) && t >= dayStart && t < dayEnd;
}

// Cross-OS basename: split on BOTH / and \ regardless of host platform.
// Node path.basename is platform-specific (posix ignores \), which corrupts
// Windows paths read on Mac/Linux and vice-versa when the file is shared.
function baseName(p) {
  if (!p) return null;
  const parts = String(p).split(/[\\/]/).filter(Boolean);
  return parts.length ? parts[parts.length - 1] : null;
}

// Load project registry for names and roots.
// Primary: canonical _sinapsis-projects.json (array schema, populated by _session-learner.sh).
// Fallback: legacy homunculus/projects.json (map schema, kept for back-compat).
// v4.6.2: strip UTF-8 BOM before JSON.parse (#16) — Windows editors and PowerShell
// redirects add one, and JSON.parse throws on it, silently dropping the registry.
function readJson(p) {
  let raw = fs.readFileSync(p, "utf8");
  if (raw.charCodeAt(0) === 0xFEFF) raw = raw.slice(1);
  return JSON.parse(raw);
}

let registry = {};
try {
  const canonical = readJson(path.join(skillsDir, "_sinapsis-projects.json"));
  if (canonical && Array.isArray(canonical.projects)) {
    for (const p of canonical.projects) {
      if (p && p.id) registry[p.id] = { name: p.name, root: p.root };
      // Cross-OS de-dup keeps every per-OS id in aliases[] — observations written
      // under an aliased id must resolve to the same project name/root.
      if (p && Array.isArray(p.aliases)) {
        for (const a of p.aliases) {
          if (a && !registry[a]) registry[a] = { name: p.name, root: p.root };
        }
      }
    }
  }
} catch(e) {}
try {
  const legacy = readJson(path.join(homunculus, "projects.json"));
  for (const [k, v] of Object.entries(legacy || {})) {
    if (!registry[k]) registry[k] = v;
  }
} catch(e) {}

// name -> root index (first wins). Recovers a LOCAL root for a project even when
// its observations were written on another machine with a different cwd.
const rootByName = {};
for (const k of Object.keys(registry)) {
  const info = registry[k] || {};
  if (info.name && info.root && !rootByName[info.name]) rootByName[info.name] = info.root;
}

// First candidate that exists on THIS machine, else "".
function resolveRoot(candidates) {
  for (const c of candidates) { if (c && fs.existsSync(c)) return c; }
  return "";
}

function parseToday(obsFile) {
  let lines;
  try { lines = fs.readFileSync(obsFile, "utf8").trim().split("\n"); }
  catch(e) { return []; }
  const out = [];
  for (const line of lines) {
    try {
      const obj = JSON.parse(line);
      if (isToday(obj.timestamp)) out.push(obj);
    } catch(e) {}
  }
  return out;
}

// Git data for a root, only when it exists locally (foreign roots → null).
function gitFor(projectRoot) {
  if (!projectRoot || !fs.existsSync(projectRoot)) return null;
  try {
    const branch = execFileSync("git", ["-C", projectRoot, "branch", "--show-current"],
      { stdio: ["pipe","pipe","pipe"], timeout: 3000 }).toString().trim();
    let commits = "";
    try {
      const author = execFileSync("git", ["-C", projectRoot, "config", "user.email"],
        { stdio: ["pipe","pipe","pipe"], timeout: 2000 }).toString().trim();
      if (author) {
        commits = execFileSync("git", ["-C", projectRoot, "log", "--oneline", "--since=00:00", "--author=" + author],
          { stdio: ["pipe","pipe","pipe"], timeout: 5000 }).toString().trim();
      }
    } catch(e) {
      try {
        commits = execFileSync("git", ["-C", projectRoot, "log", "--oneline", "--since=00:00"],
          { stdio: ["pipe","pipe","pipe"], timeout: 5000 }).toString().trim();
      } catch(e2) {}
    }
    let status = "";
    try {
      status = execFileSync("git", ["-C", projectRoot, "status", "-s"],
        { stdio: ["pipe","pipe","pipe"], timeout: 3000 }).toString().trim();
    } catch(e) {}
    return {
      branch: branch,
      commits_today: commits ? commits.split("\n").length : 0,
      commits_log: commits || "(no commits today)",
      uncommitted_files: status ? status.split("\n").length : 0,
      status: status || "(clean)"
    };
  } catch(e) {
    return null; // not a git repo or git error
  }
}

// Aggregate today-observations into a project record.
function summarize(todayLines, name, root, hash, contextMd) {
  const tools = [...new Set(todayLines.filter(l => l.tool).map(l => l.tool))];
  const errorCount = todayLines.filter(l => l.is_error).length;
  const filesTouched = [...new Set(
    todayLines
      .filter(l => l.event === "tool_complete" && (l.tool === "Edit" || l.tool === "Write"))
      .map(l => {
        try {
          const inp = typeof l.input === "string" ? JSON.parse(l.input || "{}") : (l.input || {});
          return baseName(inp.file_path);
        } catch(e) { return null; }
      })
      .filter(Boolean)
  )].slice(0, 15);
  return {
    hash: hash || null,
    name: name,
    root: root || "",
    observations_today: todayLines.length,
    tools_used: tools,
    files_touched: filesTouched,
    errors_today: errorCount,
    git: gitFor(root),
    context: contextMd || null
  };
}

// Collect keyed by NAME so the same project from different machines / cwd /
// storage location merges into one entry (cross-OS stable).
const byName = {};
function add(rec) {
  if (!byName[rec.name]) { byName[rec.name] = rec; return; }
  const e = byName[rec.name];
  e.observations_today += rec.observations_today;
  e.errors_today += rec.errors_today;
  e.tools_used = [...new Set([...e.tools_used, ...rec.tools_used])];
  e.files_touched = [...new Set([...e.files_touched, ...rec.files_touched])].slice(0, 15);
  if (!e.git && rec.git) e.git = rec.git;
  if (!e.root && rec.root) e.root = rec.root;
  if (!e.hash && rec.hash) e.hash = rec.hash;
  if (!e.context && rec.context) e.context = rec.context;
}

// 1) Per-project subdirs (git-tracked projects).
let entries = [];
try { entries = fs.readdirSync(projectsDir); } catch(e) {}
for (const hash of entries) {
  const obsFile = path.join(projectsDir, hash, "observations.jsonl");
  if (!fs.existsSync(obsFile)) continue;
  const todayLines = parseToday(obsFile);
  if (todayLines.length === 0) continue;
  const info = registry[hash] || {};
  const seen = todayLines.find(l => l.project_name && l.project_name !== "global");
  const name = info.name || (seen ? seen.project_name : hash);
  const root = resolveRoot([info.root, rootByName[name]]);
  let contextMd = null;
  const ctxFile = path.join(projectsDir, hash, "context.md");
  if (fs.existsSync(ctxFile)) { try { contextMd = fs.readFileSync(ctxFile, "utf8").trim(); } catch(e) {} }
  add(summarize(todayLines, name, root, hash, contextMd));
}

// 2) Root observations.jsonl — non-git projects land here with project_id
//    "global". Group by project_name (stable across OS even if cwd differs).
if (fs.existsSync(rootObsFile)) {
  const groups = {};
  for (const l of parseToday(rootObsFile)) {
    const nm = l.project_name || "global";
    (groups[nm] = groups[nm] || []).push(l);
  }
  for (const nm of Object.keys(groups)) {
    add(summarize(groups[nm], nm, resolveRoot([rootByName[nm]]), null, null));
  }
}

const projects = Object.values(byName).sort((a, b) => b.observations_today - a.observations_today);

const result = {
  date: today,
  project_count: projects.length,
  total_observations: projects.reduce((s, p) => s + p.observations_today, 0),
  projects
};
console.log(JSON.stringify(result, null, 2));
' 2>/dev/null

exit 0
