#!/bin/bash
# Instinct Activator - Sinapsis v4.3.3
# Reads tool data from stdin, matches against learned instincts, outputs systemMessage
# v4.2: occurrence tracking + auto-promote draft→confirmed at 5+ matches
# v4.2.1: occurrences tiebreaker in domain dedup + domain pre-filter by project stack
#         (inspired by fs-cortex project-scoped instincts — credit: Fernando Montero)
# v4.4: confidence decay — confirmed(60d inactive)→draft, draft(90d inactive)→archived
#       (inspired by gstack learnings confidence decay — credit: garrytan/gstack)
# v4.6.2: BOM-safe index read (#16) + decay demotions persisted on the no-match path

INDEX_FILE="$HOME/.claude/skills/_instincts-index.json"
LOG_FILE="$HOME/.claude/skills/_instinct.log"

[ ! -f "$INDEX_FILE" ] && exit 0

# v4.3.1: SINAPSIS_DEBUG mode (#22) — redirect stderr to log instead of /dev/null
if [ "${SINAPSIS_DEBUG:-}" = "1" ]; then
  exec 2>>"$HOME/.claude/skills/_sinapsis-debug.log"
fi

node -e '
const fs = require("fs");

let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  let data;
  try { data = JSON.parse(input); } catch(e) { process.exit(0); }

  const toolName = data.tool_name || data.tool || "";
  const toolInput = data.tool_input || data.input || {};
  const context = toolName + " " + (typeof toolInput === "object" ? JSON.stringify(toolInput) : String(toolInput));

  let index;
  try {
    // v4.6.2: strip UTF-8 BOM (#16) — Windows editors and PowerShell redirects add one,
    // JSON.parse throws on it and the catch made the whole hook a silent no-op.
    let raw = fs.readFileSync(process.env.HOME + "/.claude/skills/_instincts-index.json", "utf8");
    if (raw.charCodeAt(0) === 0xFEFF) raw = raw.slice(1);
    index = JSON.parse(raw);
  } catch(e) { process.exit(0); }

  const instincts = index.instincts || [];

  // v4.4: Confidence decay — demote stale instincts (inspired by gstack learnings decay)
  // confirmed without activation in 60d → draft, draft without activation in 90d → archived
  const DECAY_CONFIRMED_DAYS = 60;
  const DECAY_DRAFT_DAYS = 90;
  const DAY_MS = 86400000;
  const nowMs = Date.now();
  let decayDirty = false;
  for (const inst of instincts) {
    if (inst.level === "permanent") continue; // permanent never decays
    const lastTs = inst.last_triggered ? new Date(inst.last_triggered).getTime() : (inst.first_triggered ? new Date(inst.first_triggered).getTime() : 0);
    if (!lastTs) continue; // no activation data yet, skip
    const daysInactive = Math.floor((nowMs - lastTs) / DAY_MS);
    if (inst.level === "confirmed" && daysInactive > DECAY_CONFIRMED_DAYS) {
      inst.level = "draft";
      inst._decayed = true;
      decayDirty = true;
    } else if (inst.level === "draft" && daysInactive > DECAY_DRAFT_DAYS) {
      inst.level = "archived";
      inst._decayed = true;
      decayDirty = true;
    }
  }

  // v4.2.1: domain pre-filter by project stack (inspired by fs-cortex project-scoped instincts)
  // Reads context.md to detect project tech, skips irrelevant domains. Reduces regex evals.
  const ALWAYS_DOMAINS = new Set(["_default", "general", "git", "security", "operations", "quality"]);
  let skipDomains = null; // null = no filtering (safe default)
  try {
    const cwd = data.cwd || "";
    if (cwd) {
      const { execFileSync } = require("child_process");
      const root = execFileSync("git", ["-C", cwd, "rev-parse", "--show-toplevel"],
        { stdio: ["pipe","pipe","pipe"], timeout: 2000 }).toString().trim();
      const crypto = require("crypto");
      let remote = "";
      try { remote = execFileSync("git", ["-C", root, "remote", "get-url", "origin"],
        { stdio: ["pipe","pipe","pipe"], timeout: 1000 }).toString().trim(); } catch(e) {}
      const hash = crypto.createHash("sha256").update(remote || root).digest("hex").slice(0, 12);
      const ctxPath = process.env.HOME + "/.claude/homunculus/projects/" + hash + "/context.md";
      if (fs.existsSync(ctxPath)) {
        const ctx = fs.readFileSync(ctxPath, "utf8").toLowerCase();
        const stackDomains = new Set(ALWAYS_DOMAINS);
        // Detect tech from context.md and allow matching domains
        if (/next|react|tsx|jsx/.test(ctx)) { stackDomains.add("nextjs"); stackDomains.add("react"); stackDomains.add("frontend"); }
        if (/supabase|rls|postgres/.test(ctx)) { stackDomains.add("database"); stackDomains.add("supabase"); stackDomains.add("auth"); }
        if (/stripe|payment|billing/.test(ctx)) { stackDomains.add("stripe"); stackDomains.add("billing"); }
        if (/prisma|schema\.prisma/.test(ctx)) { stackDomains.add("prisma"); stackDomains.add("orm"); }
        if (/docker|container/.test(ctx)) stackDomains.add("docker");
        if (/python|django|flask/.test(ctx)) stackDomains.add("python");
        if (/formaci|training|curso/.test(ctx)) stackDomains.add("formacion");
        if (/contrato|nda|dpa|propuesta/.test(ctx)) stackDomains.add("contratos");
        if (/content|brand|copper|salgado/.test(ctx)) stackDomains.add("content");
        if (/remotion|video/.test(ctx)) stackDomains.add("video");
        if (/vercel|deploy/.test(ctx)) stackDomains.add("deploy");
        skipDomains = stackDomains;
      }
    }
  } catch(e) { /* no context = no filtering, safe */ }


// Inline flag groups like `(?i)` are Python/PCRE syntax. JavaScript has no inline
// flags: `new RegExp("(?i)foo")` throws "Invalid group", the catch below swallows
// it, and the instinct silently never matches — for the rest of its life.
//
// The patterns are written by the model when an instinct is created, and `(?i)` is
// the reflex spelling for anyone used to grep or Python. One index in the wild had
// 50 of 57 instincts dead this way; the six that still fired were simply the ones
// nobody had prefixed. Nothing reported it, because nothing looked broken: the
// index was valid JSON, the levels were right, and the occurrence counters just
// stayed at zero.
//
// Stripping the group is safe and lossless here: this matcher already compiles
// every pattern with the "i" flag, so `(?i)` was redundant on top of being fatal.
// Other inline groups (`(?m)`, `(?s)`, `(?x)`) are mapped to real flags where a JS
// equivalent exists, and dropped otherwise, which is still strictly better than
// the whole instinct disappearing.
function normalizeInlineFlags(pattern) {
  if (typeof pattern !== "string" || pattern.indexOf("(?") === -1) return pattern;
  return pattern.replace(/\(\?([imsxu]+)\)/g, "");
}

  const matches = [];

  for (const inst of instincts) {
    if (!inst.trigger_pattern) continue;
    // v4.3.1: drafts participate in matching for occurrence tracking + auto-promote
    // but are NOT injected into context (only confirmed/permanent inject)
    const isDraft = inst.level === "draft";
    // v4.2.1: skip instincts from irrelevant domains (if project context available)
    if (skipDomains && inst.domain && !skipDomains.has(inst.domain)) continue;
    try {
      // v4.3.1: ReDoS protection — reject patterns with nested quantifiers
      const tp = normalizeInlineFlags(inst.trigger_pattern);
      if (/(\+|\*|\{)\)?(\+|\*|\{)/.test(tp)) continue; // skip catastrophic backtracking patterns
      if (!new RegExp(tp, "i").test(context)) continue;
    } catch(e) {
      // A pattern that cannot compile used to be dropped in total silence, so an
      // instinct could sit in the index for months looking healthy while never
      // once firing. Say so — once per pattern per run is enough to be findable.
      try {
        fs.appendFileSync(process.env.HOME + "/.claude/skills/_instinct.log",
          new Date().toISOString() + " | BAD_PATTERN | " + inst.id + " | " + e.message + "\n");
      } catch(_) {}
      continue;
    }
    matches.push(inst);
  }

  // v4.6.2: atomic index write, shared by the decay-only path and the occurrence-tracking
  // path below. Skips while the dream cycle holds the lock (#6 race condition) and filters
  // archived instincts out of the index (v4.4 — they stay in the log only).
  function persistIndex() {
    const indexPath = process.env.HOME + "/.claude/skills/_instincts-index.json";
    const dreamLock = process.env.HOME + "/.claude/skills/_dream.lock";
    if (fs.existsSync(dreamLock)) return;
    index.instincts = index.instincts.filter(i => i.level !== "archived");
    const tmpPath = indexPath + ".tmp";
    fs.writeFileSync(tmpPath, JSON.stringify(index, null, 2));
    fs.renameSync(tmpPath, indexPath);
  }

  if (!matches.length) {
    // v4.6.2: persist decay demotions even when nothing matches. The shared write below
    // sat after this early-exit, so on every no-match tool use the demotions were
    // recomputed and then discarded — confirmed/draft instincts never actually decayed.
    if (decayDirty) {
      try {
        persistIndex();
        const decayed = instincts.filter(i => i._decayed).map(i => i.id + "(" + i.level + ")");
        fs.appendFileSync(process.env.HOME + "/.claude/skills/_instinct.log",
          new Date().toISOString() + " | (no-match) | DECAYED:" + decayed.join(",") + "\n");
      } catch(e) {}
    }
    process.exit(0);
  }

  // Separate drafts from injectable instincts
  const draftMatches = matches.filter(m => m.level === "draft");
  const injectableMatches = matches.filter(m => m.level !== "draft");

  // Priority sort: permanent first, then confirmed; within same level, highest occurrences wins
  // v4.2.1: occurrences tiebreaker (inspired by fs-cortex confidence granularity)
  // v4.5: id alphabetical tiebreaker — guarantees deterministic order across runs so the
  //       injected systemMessage prefix is byte-stable across consecutive tool uses, which
  //       is the prerequisite for prompt-cache hits on the Opus 4.7+ cached system block.
  const order = { permanent: 0, confirmed: 1 };
  injectableMatches.sort((a, b) => {
    const lvl = (order[a.level] ?? 2) - (order[b.level] ?? 2);
    if (lvl !== 0) return lvl;
    const occ = (b.occurrences || 0) - (a.occurrences || 0);
    if (occ !== 0) return occ;
    return (a.id || "").localeCompare(b.id || ""); // v4.5 cache stability tiebreaker
  });

  // Deduplicate by domain — keep only highest priority match per domain
  const domainMap = {};
  for (const m of injectableMatches) {
    const d = m.domain || "_default";
    if (!domainMap[d]) domainMap[d] = m; // already sorted, first = highest priority
  }
  // v4.5: top-N raised from 3 to 6 — with Opus 4.7+ prompt caching the cost of extra
  // instincts is amortised across tool uses, so we can be more generous per turn.
  // v4.6 (Opus 4.8): 6 → 8. The lower 1,024-token cache minimum in 4.8 plus its stronger
  // long-context handling let the larger byte-stable block cache reliably, no regression.
  const MAX_INSTINCTS_INJECTED = 8;
  const top = Object.values(domainMap).slice(0, MAX_INSTINCTS_INJECTED);

  // v4.3.1: sanitize inject content (#5F — prompt injection prevention)
  const INJECT_MAX_LEN = 500;
  const INJECT_BLOCKED = /ignore\s+(previous|above|all)\s+instructions|system:\s*you\s+are|<\/?system>|<\/?prompt>/i;
  // v4.3.3: path traversal protection (inspired by Cortex v3.10)
  const PATH_TRAVERSAL = /\.\.[\/\\]|~\/|\/etc\/|\/proc\/|%2e%2e/i;
  // v4.3.3: token budget cap — max chars injected per tool use (inspired by Cortex 8000/session)
  // v4.5: raised 1500 → 4000 to match 6-instinct cap; still well below any sane context ceiling.
  // v4.6 (Opus 4.8): 4000 → 6000 to match the 8-instinct cap.
  const TOKEN_BUDGET = 6000;

  // Only output systemMessage if there are injectable matches
  if (top.length > 0) {
    let totalLen = 0;
    const msgs = [];
    for (const m of top) {
      const inj = (m.inject || "").slice(0, INJECT_MAX_LEN);
      if (INJECT_BLOCKED.test(inj)) continue;
      if (PATH_TRAVERSAL.test(inj)) continue; // v4.3.3: block path_blocked traversal
      if (totalLen + inj.length > TOKEN_BUDGET) break; // v4.3.3: budget cap
      totalLen += inj.length;
      msgs.push("[instinct] " + inj);
    }
    if (msgs.length > 0) {
      console.log(JSON.stringify({ systemMessage: msgs.join("\n\n") }));
    }
  }

  // v4.3.3: Occurrence tracking + multi-session auto-promote (inspired by Cortex 5+acts,3+sessions)
  const now = new Date().toISOString();
  const sessionId = data.session_id || ("s-" + Date.now());
  let promoted = [];
  try {
    const allMatchedIds = new Set([...top.map(m => m.id), ...draftMatches.map(m => m.id)]);
    let dirty = false;
    for (const inst of index.instincts) {
      if (!allMatchedIds.has(inst.id)) continue;
      inst.occurrences = (inst.occurrences || 0) + 1;
      inst.last_triggered = now;
      if (!inst.first_triggered) inst.first_triggered = now;
      // v4.3.3: track distinct sessions for multi-session promote
      if (!inst.sessions_seen) inst.sessions_seen = [];
      if (!inst.sessions_seen.includes(sessionId)) {
        inst.sessions_seen.push(sessionId);
        // Cap at 20 to prevent unbounded growth
        if (inst.sessions_seen.length > 20) inst.sessions_seen = inst.sessions_seen.slice(-20);
      }
      dirty = true;
      // v4.3.3: Auto-promote: draft with 5+ occurrences AND 3+ distinct sessions → confirmed
      if (inst.level === "draft" && inst.occurrences >= 5 && (inst.sessions_seen || []).length >= 3) {
        inst.level = "confirmed";
        promoted.push(inst.id);
      }
    }
    if (dirty || decayDirty) persistIndex();
  } catch(e) {}

  // Log activations (audit trail — kept as backup)
  try {
    const ids = top.map(m => m.id).join(",");
    const promoMsg = promoted.length > 0 ? " | PROMOTED:" + promoted.join(",") : "";
    // v4.4: log decayed instincts
    const decayed = instincts.filter(i => i._decayed).map(i => i.id + "(" + i.level + ")");
    const decayMsg = decayed.length > 0 ? " | DECAYED:" + decayed.join(",") : "";
    fs.appendFileSync(process.env.HOME + "/.claude/skills/_instinct.log",
      now + " | " + toolName + " | " + ids + promoMsg + decayMsg + "\n");
  } catch(e) {}
});
' 2>/dev/null

exit 0
