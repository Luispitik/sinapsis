#!/bin/bash
# Session Learner - Sinapsis v4.3.3
# Stop hook: five detectors —
#   1. error-fix pairs (error → same tool success within 5 events)
#   2. user-corrections (same file edited 2+ times within 10 events)
#   3. workflow-chains (tool trigram repeated 2+ times)
#   4. repetitions (same error pattern across 3+ sessions — cross-session memory)
#   5. agent-patterns (subagent tool sequences captured from Agent tool calls)
# Also writes context.md per project.
# NO LLM. Pure deterministic Node.js.

HOMUNCULUS="$HOME/.claude/homunculus"

if [ "${SINAPSIS_DEBUG:-}" = "1" ]; then
  exec 2>>"$HOME/.claude/skills/_sinapsis-debug.log"
fi

INDEX_FILE="$HOME/.claude/skills/_instincts-index.json"
PROPOSALS_FILE="$HOME/.claude/skills/_instinct-proposals.json"
LOG_FILE="$HOME/.claude/skills/_session-learner.log"

# Find the most recently MODIFIED observations file (fix #17: was selecting by hash, not recency)
OBS_FILE=""
if [ -d "$HOMUNCULUS/projects" ]; then
  # Portable: use stat instead of GNU find -printf (works on macOS + Linux + Git Bash)
  OBS_FILE=$(find "$HOMUNCULUS/projects" -name "observations.jsonl" -newer "$HOMUNCULUS/.last-learn" 2>/dev/null | while read -r f; do echo "$(stat -c '%Y' "$f" 2>/dev/null || stat -f '%m' "$f" 2>/dev/null || echo 0) $f"; done | sort -rn | head -1 | cut -d' ' -f2-)
  [ -z "$OBS_FILE" ] && OBS_FILE=$(find "$HOMUNCULUS/projects" -name "observations.jsonl" -size +0c 2>/dev/null | while read -r f; do echo "$(stat -c '%Y' "$f" 2>/dev/null || stat -f '%m' "$f" 2>/dev/null || echo 0) $f"; done | sort -rn | head -1 | cut -d' ' -f2-)
fi

[ -z "$OBS_FILE" ] && exit 0
[ ! -s "$OBS_FILE" ] && exit 0

node -e '
const fs = require("fs");
const path = require("path");

// v4.6.2: strip UTF-8 BOM before JSON.parse (#16) — Windows editors and PowerShell
// redirects add one, and JSON.parse throws on it, silently disabling the reader.
function readJson(p) {
  let raw = fs.readFileSync(p, "utf8");
  if (raw.charCodeAt(0) === 0xFEFF) raw = raw.slice(1);
  return JSON.parse(raw);
}

const obsFile = process.argv[1];
const indexFile = process.argv[2];
const proposalsFile = process.argv[3];
const logFile = process.argv[4];

// Read last 8000 lines of observations (v4.5: 1000 → 5000; v4.6: 5000 → 8000). The 1M
// context in Opus 4.7+ absorbs the payload, and the stronger long-context handling in 4.8
// keeps the cross-session detectors (repetitions, agent patterns) reliable over the window.
let lines;
try {
  const content = fs.readFileSync(obsFile, "utf8").trim().split("\n");
  lines = content.slice(-8000).map(l => { try { return JSON.parse(l); } catch(e) { return null; } }).filter(Boolean);
} catch(e) { process.exit(0); }

if (lines.length < 3) process.exit(0);

// ── JOB 1: Write project context.md (ALWAYS — not just when proposals exist) ──
const projectDir = path.dirname(obsFile);
const projectHash = path.basename(projectDir);
const today = new Date().toISOString().slice(0, 10);

// Get project name + root + remote (hoisted — used by JOB 1, JOB 1.5 upsert and JOB 2)
// Primary source: observations (observe.sh writes project_name and cwd into each entry)
let projectName = projectHash;
let projectRoot = "";
let projectRemote = "";
const { execFileSync } = require("child_process");
// On Windows under Git Bash, cwd may arrive as "/c/Users/..." which native
// git.exe rejects. Convert to "C:/Users/..." form which works on both POSIX and Windows.
function normalizeCwd(p) {
  if (!p) return p;
  const m = p.match(/^\/([a-zA-Z])\/(.*)$/);
  return m ? m[1].toUpperCase() + ":/" + m[2] : p;
}
try {
  // Prefer most recent observation (cwd may have moved over time)
  for (let i = lines.length - 1; i >= 0; i--) {
    if (!projectName || projectName === projectHash) {
      if (lines[i].project_name) projectName = lines[i].project_name;
    }
    if (!projectRoot && lines[i].cwd) {
      const cwd = normalizeCwd(lines[i].cwd);
      try {
        const root = execFileSync("git", ["-C", cwd, "rev-parse", "--show-toplevel"],
          { stdio: ["ignore", "pipe", "ignore"], encoding: "utf8", timeout: 2000 }).trim();
        if (root) {
          projectRoot = root;
          try {
            projectRemote = execFileSync("git", ["-C", root, "remote", "get-url", "origin"],
              { stdio: ["ignore", "pipe", "ignore"], encoding: "utf8", timeout: 2000 }).trim();
          } catch(e) {}
        }
      } catch(e) {}
    }
    if (projectName !== projectHash && projectRoot) break;
  }
} catch(e) {}
// Legacy fallback: homunculus/projects.json (kept for back-compat with installs that created it)
try {
  const pj = readJson(process.env.HOME + "/.claude/homunculus/projects.json");
  if (pj[projectHash]) {
    if (pj[projectHash].name && projectName === projectHash) projectName = pj[projectHash].name;
    if (pj[projectHash].root && !projectRoot) projectRoot = pj[projectHash].root;
    if (pj[projectHash].remote && !projectRemote) projectRemote = pj[projectHash].remote;
  }
} catch(e) {}

try {
  // Get total obs count from full file
  let totalObs = lines.length;
  try {
    totalObs = fs.readFileSync(obsFile, "utf8").trim().split("\n").length;
  } catch(e) {}

  // Files touched this session (Edit/Write, deduplicated, max 6)
  const filesTouched = [...new Set(
    lines
      .filter(l => l.event === "tool_complete" && (l.tool === "Edit" || l.tool === "Write"))
      .map(l => {
        try {
          const inp = JSON.parse(l.input || "{}");
          return inp.file_path ? path.basename(inp.file_path) : null;
        } catch(e) { return null; }
      })
      .filter(Boolean)
  )].slice(0, 6);

  // Error patterns count (for proposals hint)
  let errorCount = 0;
  for (let i = 0; i < lines.length - 1; i++) {
    if (!lines[i].is_error) continue;
    for (let j = i+1; j < Math.min(i+6, lines.length); j++) {
      if (lines[j].tool === lines[i].tool && !lines[j].is_error) {
        errorCount++;
        break;
      }
    }
  }

  const contextLines = [
    "## Proyecto: " + projectName,
    "Última sesión: " + today,
    "Observaciones totales: " + totalObs,
    filesTouched.length > 0
      ? "Archivos activos: " + filesTouched.join(", ")
      : null,
    errorCount > 0
      ? "Posibles gotchas detectados: " + errorCount + " — ejecuta /analyze-session"
      : null,
  ].filter(Boolean).join("\n");

  fs.writeFileSync(projectDir + "/context.md", contextLines);
} catch(e) {
  // context.md write failure is non-critical
}

// ── JOB 1.5: Upsert canonical project registry _sinapsis-projects.json ──
// FIX: prior to this, _sinapsis-projects.json was never populated by any hook even though
// /projects, /eod, /instinct-status, /evolve, /backup all read from it.
// We upsert here on every Stop event — atomic write + advisory lock, idempotent.
try {
  const registryPath = process.env.HOME + "/.claude/skills/_sinapsis-projects.json";
  const lockPath = registryPath + ".lock";
  const now = new Date().toISOString();

  // Advisory lock to prevent lost updates when multiple Stop hooks fire concurrently
  // from different sessions. tmp+rename alone prevents torn writes but NOT lost updates.
  // Strategy: O_EXCL create on .lock, retry with backoff, skip if still locked.
  const STALE_LOCK_MS = 10000;
  let lockFd = null;
  for (let attempt = 0; attempt < 8 && lockFd === null; attempt++) {
    try {
      lockFd = fs.openSync(lockPath, "wx");
    } catch(e) {
      if (e.code !== "EEXIST") throw e;
      // Lock exists — check if stale (orphaned by crashed process)
      try {
        const stat = fs.statSync(lockPath);
        if (Date.now() - stat.mtimeMs > STALE_LOCK_MS) {
          fs.unlinkSync(lockPath);
          continue;
        }
      } catch(_) {}
      // Backoff: 50ms, 100ms, 150ms, ...
      const sleepMs = 50 * (attempt + 1);
      const waitUntil = Date.now() + sleepMs;
      while (Date.now() < waitUntil) { /* spin (no sleep primitive in stdlib) */ }
    }
  }
  if (lockFd === null) {
    // Could not acquire lock — skip this upsert. Next Stop will retry.
    if (process.env.SINAPSIS_DEBUG === "1") {
      process.stderr.write("[session-learner] _sinapsis-projects.json: lock contention, skipping upsert\n");
    }
  } else {
    try {
      // Read registry AFTER acquiring lock (prevents lost updates: another writer
      // may have added entries between our earlier code and now).
      let registry;
      try {
        registry = readJson(registryPath);
      } catch(e) {
        registry = { version: "4.1", system: "sinapsis", projects: [], note: "Projects registered automatically by _session-learner.sh on Stop events." };
      }
      if (!Array.isArray(registry.projects)) registry.projects = [];

      // Cross-OS de-dup: the project id is sha256(remote || root); for a project with
      // no git remote the id is derived from the root, which differs per OS
      // (/Users/me/Proj vs C:/Users/Me/Proj), so the SAME project gets a different id on
      // each machine — two entries for one project when the registry is shared (e.g. via
      // a synced folder). We match on a cross-OS-stable key (the remote when present, else
      // the project name), register every per-OS id as an alias, and record each OS root.
      // Only two families are distinguished: "windows" and "posix". macOS and Linux both
      // classify as posix, so a no-remote project seen from a Mac and from a Linux box is
      // NOT de-duplicated (the name-key merge below requires the families to differ). That
      // is deliberate: it keeps the same-machine guard cheap. Windows<->posix, the case
      // this feature targets, is covered.
      function osFamily(p) {
        // Windows: "C:\\", "C:/" or Git-Bash "/c/"; everything else (Linux, macOS) is posix.
        return (/^[a-zA-Z]:[\\/]/.test(p) || /^\/[a-zA-Z]\//.test(p)) ? "windows" : "posix";
      }
      // Stamp + log a name-key fusion. Only reached for cross-OS-family matches with no
      // remote, i.e. exactly the case that can be wrong. Keeps the last few pairs so a
      // bad fusion is auditable after the fact.
      function noteNameMerge(entry, rootA, rootB) {
        entry.name_merged = true;
        if (!Array.isArray(entry.name_merge_log)) entry.name_merge_log = [];
        const pair = [rootA, rootB].filter(Boolean).sort().join(" <> ");
        if (pair && !entry.name_merge_log.includes(pair)) {
          entry.name_merge_log.push(pair);
          if (entry.name_merge_log.length > 5) entry.name_merge_log.shift();
          // NOT stderr: the whole node block is invoked with 2>/dev/null, so anything
          // written there is discarded. The log file is the only channel that survives.
          // No literal single-quote in this block — it would close the bash -e string.
          try {
            fs.appendFileSync(logFile, now + " | registry: merged [" + entry.name
              + "] by NAME across OS families (no remote to verify) | " + pair + "\n");
          } catch (e) {}
        }
      }

      const crossKey = (projectRemote && projectRemote.trim())
        ? "remote:" + projectRemote.trim().toLowerCase()
        : "name:" + (projectName || "").toLowerCase();

      // Known asymmetry (documented, not handled): remote detection can fail on ONE
      // machine (git not on PATH for execFileSync) — that sighting falls back to a
      // "name:" crossKey and will not match the "remote:" entry, so a duplicate
      // persists until a session on that machine sees the remote again (the key
      // upgrade below then lets the migration pass heal it).
      function findByCrossKey() {
        if (crossKey.startsWith("remote:")) {
          // Same remote = same project, whatever the OS. (Distinct ids with an equal
          // lowercased remote can only come from remote-string case differences.)
          return registry.projects.find(p => p && p.crossKey === crossKey);
        }
        // "name:" fallback — ONLY for the genuine cross-OS scenario. A bare name match
        // would collapse two different projects that share a folder name on the SAME
        // machine (~/work/app vs ~/personal/app), and a false merge corrupts the
        // registry where a duplicate is merely cosmetic. Accept the match only when
        // the OS families differ AND the entry has no root of our family recorded.
        //
        // Residual risk, accepted and made visible rather than guarded away: two
        // UNRELATED projects that merely share a folder name ("app", "api", "docs")
        // on machines of different OS families still merge — with no remote there is
        // nothing left to tell them apart. Every such merge is stamped on the entry
        // (name_merged) and logged, so a wrong fusion is a visible event that can be
        // undone by hand instead of silent registry drift.
        if (crossKey === "name:" || !projectRoot) return null;
        const fam = osFamily(projectRoot);
        const hit = registry.projects.find(p => p && p.crossKey === crossKey && p.root
          && osFamily(p.root) !== fam
          && !(p.roots && p.roots[fam]));
        if (hit) noteNameMerge(hit, projectRoot, hit.root);
        return hit;
      }

      let entry = registry.projects.find(p => p && p.id === projectHash)
        || registry.projects.find(p => p && Array.isArray(p.aliases) && p.aliases.includes(projectHash))
        || findByCrossKey();

      if (!entry) {
        entry = { id: projectHash, crossKey: crossKey, name: projectName, root: projectRoot,
                  roots: {}, remote: projectRemote, aliases: [], created: now, last_seen: now };
        registry.projects.push(entry);
      }
      if (!Array.isArray(entry.aliases)) entry.aliases = [];
      if (entry.id !== projectHash && !entry.aliases.includes(projectHash)) entry.aliases.push(projectHash);
      if (projectName && projectName !== projectHash) entry.name = projectName;
      if (projectRoot) {
        entry.root = projectRoot;                       // most-recently-seen OS path
        if (!entry.roots || typeof entry.roots !== "object") entry.roots = {};
        entry.roots[osFamily(projectRoot)] = projectRoot;  // { posix, windows }
      }
      if (projectRemote) {
        entry.remote = projectRemote;
        entry.crossKey = "remote:" + projectRemote.trim().toLowerCase();  // upgrade key if a remote appears later
      } else if (!entry.crossKey) {
        entry.crossKey = crossKey;
      }
      entry.last_seen = now;

      // Migration pass: cure PRE-EXISTING duplicates (the synced-registry symptom this
      // feature targets). The lookup above only prevents future duplicates on a clean
      // registry; two entries already both present (each machine updating its own via
      // id-match) would otherwise persist forever. Merge pairs under the SAME guard as
      // the lookup: "remote:" keys merge freely, "name:" keys only across OS families.
      // Union aliases/roots, oldest created, newest last_seen (whose root also wins as
      // the most-recently-seen path). crossKey is backfilled for legacy entries so
      // registries written before this feature are cured too. O(n²) over tens of
      // entries — negligible on a Stop hook.
      {
        const keyOf = p => p.crossKey ||
          (p.remote && p.remote.trim() ? "remote:" + p.remote.trim().toLowerCase()
                                       : "name:" + (p.name || "").toLowerCase());
        const kept = [];
        for (const p of registry.projects) {
          if (!p) continue;
          p.crossKey = keyOf(p);
          const famP = p.root ? osFamily(p.root) : null;
          const target = kept.find(k => {
            if (k.crossKey !== p.crossKey) return false;
            if (k.crossKey.startsWith("remote:")) return true;
            if (k.crossKey === "name:" || !k.root || !famP) return false;
            const pRootFam = (p.roots && p.roots[famP]) || p.root;
            return osFamily(k.root) !== famP
              && !(k.roots && k.roots[famP] && k.roots[famP] !== pRootFam);
          });
          if (!target) { kept.push(p); continue; }
          // Same accepted-but-visible rule as the lookup path: a fusion that rests on
          // the folder name alone gets stamped and logged.
          if (target.crossKey && target.crossKey.startsWith("name:")) {
            noteNameMerge(target, p.root, target.root);
          }
          const ids = new Set([...(target.aliases || []), ...(p.aliases || []), p.id].filter(Boolean));
          ids.delete(target.id);
          target.aliases = Array.from(ids);
          if (!target.roots || typeof target.roots !== "object") target.roots = {};
          // Legacy entries (pre-feature) carry root but no roots map — backfill so the
          // union below actually records both families.
          if (target.root) {
            const famT = osFamily(target.root);
            if (!target.roots[famT]) target.roots[famT] = target.root;
          }
          const pRoots = (p.roots && typeof p.roots === "object") ? p.roots : {};
          if (p.root && famP && !pRoots[famP]) pRoots[famP] = p.root;
          for (const f of Object.keys(pRoots)) if (!target.roots[f]) target.roots[f] = pRoots[f];
          if (!target.remote && p.remote) target.remote = p.remote;
          if (p.created && (!target.created || p.created < target.created)) target.created = p.created;
          if (p.last_seen && (!target.last_seen || p.last_seen > target.last_seen)) {
            target.last_seen = p.last_seen;
            if (p.root) target.root = p.root;
          }
        }
        registry.projects = kept;
      }

      // Atomic write: tmp + rename (still needed for crash safety)
      const tmpPath = registryPath + ".tmp." + process.pid;
      fs.writeFileSync(tmpPath, JSON.stringify(registry, null, 2));
      fs.renameSync(tmpPath, registryPath);
    } finally {
      try { fs.closeSync(lockFd); } catch(_) {}
      try { fs.unlinkSync(lockPath); } catch(_) {}
    }
  }
} catch(e) {
  // Registry upsert failure is non-critical (logged for debugging)
  if (process.env.SINAPSIS_DEBUG === "1") {
    process.stderr.write("[session-learner] _sinapsis-projects.json upsert failed: " + e.message + "\n");
  }
}

// ── JOB 2: Detect error-resolution patterns → proposals ──

// Read existing instincts to avoid re-proposing known patterns
let existing = new Set();
try {
  const idx = readJson(indexFile);
  (idx.instincts || []).forEach(i => existing.add(i.id));
} catch(e) {}

// Load proposals for today (session-based, overwrites on new day)
let proposals;
try {
  const raw = readJson(proposalsFile);
  proposals = (raw.session_date === today) ? raw : { version: "1.0", session_date: today, proposals: [] };
} catch(e) {
  proposals = { version: "1.0", session_date: today, proposals: [] };
}

// IDs already proposed today
const proposedIds = new Set(proposals.proposals.map(p => p.id));
const found = [];

// PATTERN 1: error → same tool success within 5 events (uses is_error flag from observe_v3)
// Dedup: one proposal per tool per day
for (let i = 0; i < lines.length - 1; i++) {
  if (!lines[i].is_error) continue;

  const toolId = "fix-" + lines[i].tool.toLowerCase().replace(/[^a-z]/g, "");
  if (existing.has(toolId) || proposedIds.has(toolId)) continue;

  for (let j = i+1; j < Math.min(i+6, lines.length); j++) {
    if (lines[j].tool === lines[i].tool && !lines[j].is_error) {
      found.push({
        type: "error_resolution",
        id: toolId,
        description: lines[i].tool + " error resuelto — posible gotcha a documentar",
        evidence: "Sesion " + today + ": fallo y recuperacion en misma herramienta",
        project_name: projectName,
        sample_input: (lines[i].input || "").slice(0, 200),
        sample_output: (lines[i].output || "").slice(0, 200),
        err_msg: (lines[i].err_msg || "").slice(0, 200),
        is_critical: !!lines[i].is_critical
      });
      proposedIds.add(toolId);
      break;
    }
  }
}

// PATTERN 2: user corrections — Edit/Write on same file within 10 events = refinement
// v4.2: detects when user iterates on same file (correction/preference signal)
const editEvents = lines
  .map((l, idx) => ({ ...l, _idx: idx }))
  .filter(l => l.event === "tool_complete" && (l.tool === "Edit" || l.tool === "Write"));

const correctedFiles = {};
for (let i = 0; i < editEvents.length - 1; i++) {
  let fileA = "";
  try { const inp = JSON.parse(editEvents[i].input || "{}"); fileA = inp.file_path || ""; } catch(e) {}
  if (!fileA) continue;

  for (let j = i + 1; j < editEvents.length; j++) {
    if (editEvents[j]._idx - editEvents[i]._idx > 10) break; // window of 10 events
    let fileB = "";
    try { const inp = JSON.parse(editEvents[j].input || "{}"); fileB = inp.file_path || ""; } catch(e) {}
    if (fileA === fileB) {
      const slug = path.basename(fileA).toLowerCase().replace(/[^a-z0-9]/g, "-").replace(/-+/g, "-").slice(0, 30);
      correctedFiles[slug] = (correctedFiles[slug] || 0) + 1;
      break;
    }
  }
}

for (const [slug, count] of Object.entries(correctedFiles)) {
  if (count < 2) continue; // need at least 2 correction cycles
  const corrId = "correction-" + slug;
  if (existing.has(corrId) || proposedIds.has(corrId)) continue;
  found.push({
    type: "user_correction",
    id: corrId,
    description: "Archivo " + slug + " editado " + (count + 1) + "+ veces — posible patron de correccion",
    evidence: "Sesion " + today + ": " + count + " ciclos de re-edicion en mismo archivo",
    project_name: projectName,
    sample_input: "",
    sample_output: ""
  });
  proposedIds.add(corrId);
}

// PATTERN 3: workflow chains — same sequence of 3+ tools appears 2+ times
// v4.2: detects repeated tool sequences (workflow signal)
const toolSeq = lines
  .filter(l => l.event === "tool_complete")
  .map(l => l.tool);

if (toolSeq.length >= 6) {
  const trigramCounts = {};
  for (let i = 0; i <= toolSeq.length - 3; i++) {
    const key = toolSeq[i] + ">" + toolSeq[i+1] + ">" + toolSeq[i+2];
    trigramCounts[key] = (trigramCounts[key] || 0) + 1;
  }

  for (const [seq, count] of Object.entries(trigramCounts)) {
    if (count < 2) continue;
    const parts = seq.split(">");
    const wfId = "workflow-" + parts.map(p => p.toLowerCase().replace(/[^a-z]/g, "")).join("-");
    if (existing.has(wfId) || proposedIds.has(wfId)) continue;
    found.push({
      type: "workflow_chain",
      id: wfId,
      description: parts.join(" → ") + " repetido " + count + "x — posible workflow a documentar",
      evidence: "Sesion " + today + ": secuencia de 3 tools repetida " + count + " veces",
      project_name: projectName,
      sample_input: "",
      sample_output: ""
    });
    proposedIds.add(wfId);
  }
}

// PATTERN 4: repetitions — same error tool seen in proposals from 3+ different days
// v4.3.3: cross-session memory. Reads prior proposals to find recurring error patterns.
// Cortex tracks this via "repetitions (>3 sessions)" — we use proposal history.
try {
  const rawProposals = readJson(proposalsFile);
  const priorPropDates = {};
  for (const p of (rawProposals.proposals || [])) {
    if (p.type === "error_resolution" && p.proposed_at) {
      const day = p.proposed_at.slice(0, 10);
      if (!priorPropDates[p.id]) priorPropDates[p.id] = new Set();
      priorPropDates[p.id].add(day);
    }
  }
  // Also count today errors
  for (const f of found) {
    if (f.type === "error_resolution") {
      if (!priorPropDates[f.id]) priorPropDates[f.id] = new Set();
      priorPropDates[f.id].add(today);
    }
  }
  for (const [errId, days] of Object.entries(priorPropDates)) {
    if (days.size < 3) continue; // need 3+ distinct days
    const repId = "repetition-" + errId;
    if (existing.has(repId) || proposedIds.has(repId)) continue;
    found.push({
      type: "repetition",
      id: repId,
      description: errId + " repetido en " + days.size + " sesiones distintas — patron recurrente confirmado",
      evidence: "Detectado en fechas: " + [...days].sort().join(", "),
      project_name: projectName,
      sample_input: "",
      sample_output: ""
    });
    proposedIds.add(repId);
  }
} catch(e) { /* no prior proposals = skip */ }

// PATTERN 5: agent patterns — captures tool sequences within Agent tool calls
// v4.3.3: subagent behaviors are valuable learning data (Cortex agent-patterns)
const agentEvents = lines.filter(l =>
  l.tool === "Agent" && l.event === "tool_complete" && l.output
);
for (const ae of agentEvents) {
  // Extract subagent type and result patterns from output
  const output = (ae.output || "").slice(0, 1000);
  // \u0027 is single-quote: avoids closing the bash single-quoted node -e block
  const agentTypeMatch = output.match(/subagent_type[=:]?\s*["\u0027]?(\w+)/i);
  const agentType = agentTypeMatch ? agentTypeMatch[1] : "general";
  // If agent output contains error keywords, propose a pattern
  const hasError = /\berror\b|\bfailed\b|\bexception\b/i.test(output);
  if (hasError) {
    const agId = "agent-error-" + agentType.toLowerCase();
    if (existing.has(agId) || proposedIds.has(agId)) continue;
    found.push({
      type: "agent_pattern",
      id: agId,
      description: "Subagente " + agentType + " reporto errores — posible gotcha a documentar",
      evidence: "Sesion " + today + ": Agent tool con errores en output",
      project_name: projectName,
      sample_input: (ae.input || "").slice(0, 200),
      sample_output: output.slice(0, 200)
    });
    proposedIds.add(agId);
  }
}

const now = new Date().toISOString();

// Write proposals (only if new ones found)
if (found.length > 0) {
  found.forEach(f => {
    proposals.proposals.push({ ...f, proposed_at: now, status: "pending", level: "draft" });
  });
  try { fs.writeFileSync(proposalsFile, JSON.stringify(proposals, null, 2)); } catch(e) {}
}

// Touch marker
try {
  fs.writeFileSync(process.env.HOME + "/.claude/homunculus/.last-learn", now);
} catch(e) {}

// Log
try {
  const summary = found.length > 0
    ? found.length + " patterns: " + found.map(f => f.id).join(",")
    : "no patterns";
  fs.appendFileSync(logFile, now + " | " + summary + " | context.md written for " + projectHash + "\n");
} catch(e) {}

// Output systemMessage only if proposals found
if (found.length > 0) {
  const msg = "Sinapsis: " + found.length + " patron(es) detectado(s):\n" +
    found.map(f => "  - " + f.description).join("\n") +
    "\nRevisa con /analyze-session.";
  console.log(JSON.stringify({ systemMessage: msg }));
}
' "$OBS_FILE" "$INDEX_FILE" "$PROPOSALS_FILE" "$LOG_FILE" 2>/dev/null

exit 0
