#!/bin/bash
# Dream Cycle — Sinapsis v4.3
# Index hygiene for _instincts-index.json
# Deterministic. No LLM. Pure Node.js.
# Run: bash ~/.claude/skills/_dream.sh
#   OR via /dream command
#   OR via scheduled task (weekly)

INDEX_FILE="$HOME/.claude/skills/_instincts-index.json"
REPORT_FILE="$HOME/.claude/skills/_dream-report.md"
LOCK_FILE="$HOME/.claude/skills/_dream.lock"
LOG_FILE="$HOME/.claude/skills/_dream.log"
[ ! -f "$INDEX_FILE" ] && exit 0

if [ "${SINAPSIS_DEBUG:-}" = "1" ]; then
  exec 2>>"$HOME/.claude/skills/_sinapsis-debug.log"
fi

node -e '
const fs = require("fs");
const path = require("path");
const os = require("os");

const INDEX_FILE = process.argv[1];
const REPORT_FILE = process.argv[2];
const LOCK_FILE = process.argv[3];
const LOG_FILE = process.argv[4];
// KNOWLEDGE_FILE removed in v4.3.1 (was dead code — Bug #19)

// ── LOCK ──────────────────────────────────────────────────────────────────────
try {
  fs.writeFileSync(LOCK_FILE, process.pid.toString(), { flag: "wx" });
} catch (e) {
  if (e.code === "EEXIST") {
    try {
      const stat = fs.statSync(LOCK_FILE);
      if (Date.now() - stat.mtimeMs > 3600000) {
        fs.unlinkSync(LOCK_FILE);
        try {
          fs.writeFileSync(LOCK_FILE, process.pid.toString(), { flag: "wx" });
        } catch (e2) { process.exit(0); }
      } else {
        process.exit(0);
      }
    } catch (e3) { process.exit(0); }
  } else {
    process.exit(0);
  }
}

try {

// ── READ INDEX ────────────────────────────────────────────────────────────────
let index;
try {
  // v4.6.2: strip UTF-8 BOM (#16) — JSON.parse throws on it, aborting the dream cycle
  let rawIndex = fs.readFileSync(INDEX_FILE, "utf8");
  if (rawIndex.charCodeAt(0) === 0xFEFF) rawIndex = rawIndex.slice(1);
  index = JSON.parse(rawIndex);
} catch (e) { process.exit(0); }

const instincts = index.instincts || [];
if (instincts.length === 0) {
  // Generate minimal report for empty index
  const emptyReport = "# Sinapsis Dream Report\n> Generated: " + new Date().toISOString() + "\n\n## Executive Summary\nHealth Score: **100/100**\n- 0 instincts — nothing to consolidate.\n\n## Module 1: Duplicates\nNo duplicates detected.\n\n## Module 2: Contradictions\nNo contradictions detected.\n\n## Module 3: Staleness\n### Auto-Actions Taken\nNo auto-actions taken.\n\n### Flagged for Review\nAll instincts are fresh.\n\n## Module 4: Trigger Validation\nAll trigger patterns are valid.\n\n## Module 5: Index Health\nEmpty index.\n";
  try { fs.writeFileSync(REPORT_FILE, emptyReport); } catch(e) {}
  try { fs.unlinkSync(LOCK_FILE); } catch(e) {}
  process.exit(0);
}

const now = new Date();
const isoNow = now.toISOString();

// ── HELPERS ───────────────────────────────────────────────────────────────────
function tokenize(text) {
  if (!text || typeof text !== "string") return new Set();
  return new Set(text.toLowerCase().replace(/[^\p{L}\p{N} ]/gu, " ").split(/\s+/).filter(w => w.length > 2));
}

function jaccard(setA, setB) {
  if (setA.size === 0 && setB.size === 0) return 0;
  let inter = 0;
  for (const w of setA) { if (setB.has(w)) inter++; }
  const union = setA.size + setB.size - inter;
  return union === 0 ? 0 : inter / union;
}

function daysBetween(dateStr) {
  if (!dateStr) return Infinity;
  const d = new Date(dateStr);
  if (isNaN(d.getTime())) return Infinity;
  return Math.floor((now.getTime() - d.getTime()) / 86400000);
}

function triggersOverlap(a, b) {
  if (!a || !b) return false;
  if (a === b) return true;
  if (a.includes(b) || b.includes(a)) return true;
  return false;
}

function triggerAlternatives(pattern) {
  if (!pattern) return new Set();
  return new Set(pattern.split("|").map(s => s.trim().toLowerCase()).filter(Boolean));
}

// ── MODULE 1: DUPLICATE DETECTION ─────────────────────────────────────────────
const duplicateFindings = [];

for (let i = 0; i < instincts.length; i++) {
  const a = instincts[i];
  const tokensA = tokenize(a.inject);
  const altA = triggerAlternatives(a.trigger_pattern);

  for (let j = i + 1; j < instincts.length; j++) {
    const b = instincts[j];

    const sameDomain = (a.domain || "_default") === (b.domain || "_default");
    const tOverlap = triggersOverlap(a.trigger_pattern, b.trigger_pattern);

    if (!sameDomain && !tOverlap) continue;

    const tokensB = tokenize(b.inject);
    const sim = jaccard(tokensA, tokensB);

    if (sim > 0.80) {
      duplicateFindings.push({
        type: "duplicate",
        ids: [a.id, b.id],
        similarity: Math.round(sim * 100) / 100,
        reason: "inject_similarity"
      });
    } else if (tOverlap && a.trigger_pattern && b.trigger_pattern && a.trigger_pattern === b.trigger_pattern) {
      duplicateFindings.push({
        type: "duplicate",
        ids: [a.id, b.id],
        similarity: sim > 0 ? Math.round(sim * 100) / 100 : 0,
        reason: "trigger_overlap"
      });
    }
  }
}

// ── MODULE 2: CONTRADICTION DETECTION ─────────────────────────────────────────
const contradictionFindings = [];

const opposingPairs = [
  { a: /\bnever\b/i,    b: /\balways\b/i,   label: "never_vs_always" },
  { a: /\bnunca\b/i,    b: /\bsiempre\b/i,  label: "nunca_vs_siempre" },
  { a: /\bskip\b/i,     b: /\brequire\b/i,  label: "skip_vs_require" },
  { a: /\bavoid\b/i,    b: /\buse\b/i,      label: "avoid_vs_use" },
  { a: /\bevitar\b/i,   b: /\busar\b/i,     label: "evitar_vs_usar" },
  { a: /\bdon[\u2019\u0027]?t\b/i, b: /\bdo (?:use|require|add|apply|enable)\b/i, label: "dont_vs_do" },
  { a: /^No /m,         b: null,             label: "no_prefix_vs_positive" }
];

for (let i = 0; i < instincts.length; i++) {
  const a = instincts[i];
  for (let j = i + 1; j < instincts.length; j++) {
    const b = instincts[j];
    if ((a.domain || "_default") !== (b.domain || "_default")) continue;

    const textA = a.inject || "";
    const textB = b.inject || "";

    for (const pair of opposingPairs) {
      if (pair.label === "no_prefix_vs_positive") {
        if (pair.a.test(textA) && !pair.a.test(textB)) {
          const keywordsA = tokenize(textA);
          const keywordsB = tokenize(textB);
          let shared = 0;
          for (const w of keywordsA) { if (keywordsB.has(w)) shared++; }
          if (shared >= 3) {
            contradictionFindings.push({
              type: "contradiction",
              ids: [a.id, b.id],
              reason: pair.label
            });
            break;
          }
        }
        if (pair.a.test(textB) && !pair.a.test(textA)) {
          const keywordsA = tokenize(textA);
          const keywordsB = tokenize(textB);
          let shared = 0;
          for (const w of keywordsA) { if (keywordsB.has(w)) shared++; }
          if (shared >= 3) {
            contradictionFindings.push({
              type: "contradiction",
              ids: [a.id, b.id],
              reason: pair.label
            });
            break;
          }
        }
      } else {
        if ((pair.a.test(textA) && pair.b.test(textB)) ||
            (pair.b.test(textA) && pair.a.test(textB))) {
          contradictionFindings.push({
            type: "contradiction",
            ids: [a.id, b.id],
            reason: pair.label
          });
          break;
        }
      }
    }
  }
}

// ── MODULE 3: STALENESS SCORING ───────────────────────────────────────────────
const stalenessFindings = [];
const autoArchived = [];

for (const inst of instincts) {
  const daysSinceTriggered = daysBetween(inst.last_triggered);
  const daysSinceAdded = daysBetween(inst.added);
  const occ = inst.occurrences || 0;

  let freshness;
  if (occ === 0 && daysSinceAdded > 30) {
    freshness = "never_activated";
  } else if (daysSinceTriggered <= 30) {
    freshness = "fresh";
  } else if (daysSinceTriggered <= 60) {
    freshness = "stale";
  } else {
    freshness = "archive_candidate";
  }

  let archived = false;

  // AUTO-ACTION: draft + 0 occurrences + >90 days old
  if (inst.level === "draft" && occ === 0 && daysSinceAdded > 90) {
    archived = true;
    autoArchived.push(inst);
  }

  if (freshness !== "fresh" || archived) {
    stalenessFindings.push({
      type: "staleness",
      id: inst.id,
      freshness: freshness,
      daysSinceTriggered: daysSinceTriggered === Infinity ? "never" : daysSinceTriggered,
      daysSinceAdded: daysSinceAdded === Infinity ? "unknown" : daysSinceAdded,
      autoArchived: archived
    });
  }
}

// ── MODULE 4: TRIGGER PATTERN VALIDATION ──────────────────────────────────────
const triggerFindings = [];

for (const inst of instincts) {
  if (!inst.trigger_pattern) continue;

  // Check valid regex. "invalid_regex" on its own sends the reader hunting; the
  // overwhelmingly common cause is an inline flag group like `(?i)`, which is
  // Python/PCRE syntax that JavaScript rejects outright. Name that case, because
  // it is the one the activators now auto-heal and the one worth cleaning at the
  // source so the pattern reads honestly.
  try {
    new RegExp(inst.trigger_pattern, "i");
  } catch (e) {
    const inlineFlags = /\(\?[imsxu]+\)/.test(inst.trigger_pattern);
    triggerFindings.push({
      type: "trigger_issue",
      id: inst.id,
      issue: inlineFlags ? "inline_flag_group" : "invalid_regex",
      detail: inlineFlags
        ? "`(?i)`-style inline flags are not valid in JavaScript; the activators strip them, but the pattern should drop them too"
        : e.message
    });
    continue;
  }

  // Check overly broad
  const p = inst.trigger_pattern.trim();
  if (p === ".*" || p === ".+" || p === "." || p.length === 1) {
    triggerFindings.push({ type: "trigger_issue", id: inst.id, issue: "overly_broad" });
  }
}

// Cross-domain overlap
for (let i = 0; i < instincts.length; i++) {
  const a = instincts[i];
  if (!a.trigger_pattern) continue;
  for (let j = i + 1; j < instincts.length; j++) {
    const b = instincts[j];
    if (!b.trigger_pattern) continue;
    if ((a.domain || "_default") === (b.domain || "_default")) continue;

    const altA = triggerAlternatives(a.trigger_pattern);
    const altB = triggerAlternatives(b.trigger_pattern);
    let overlap = 0;
    for (const x of altA) { if (altB.has(x)) overlap++; }
    if (overlap > 0) {
      triggerFindings.push({
        type: "trigger_issue",
        id: a.id + "+" + b.id,
        issue: "cross_domain_overlap"
      });
    }
  }
}

// ── MODULE 5: HEALTH METRICS & SCORE ──────────────────────────────────────────
const totalByLevel = { permanent: 0, confirmed: 0, draft: 0 };
const domainDistribution = {};
let activatedCount = 0;

for (const inst of instincts) {
  const lvl = inst.level || "draft";
  totalByLevel[lvl] = (totalByLevel[lvl] || 0) + 1;
  const dom = inst.domain || "_default";
  domainDistribution[dom] = (domainDistribution[dom] || 0) + 1;
  if ((inst.occurrences || 0) > 0) activatedCount++;
}

const total = instincts.length;
const coverageRatio = total > 0 ? Math.round((activatedCount / total) * 100) : 0;

const sortedByOcc = [...instincts].sort((a, b) => (b.occurrences || 0) - (a.occurrences || 0));
const top5Active = sortedByOcc.slice(0, 5).map(i => ({ id: i.id, occurrences: i.occurrences || 0 }));
const bottom5Active = sortedByOcc.slice(-5).reverse().map(i => ({ id: i.id, occurrences: i.occurrences || 0 }));

// Health score
let score = 100;
score -= duplicateFindings.length * 10;
score -= contradictionFindings.length * 15;
score -= stalenessFindings.filter(f => f.freshness === "archive_candidate" || f.freshness === "never_activated").length * 5;
score -= stalenessFindings.filter(f => f.freshness === "stale").length * 2;
score -= triggerFindings.filter(f => f.issue === "invalid_regex" || f.issue === "overly_broad").length * 5;
if (coverageRatio < 50) score -= 10;
score = Math.max(0, Math.min(100, score));

// ── APPLY AUTO-ACTIONS: Archive drafts ────────────────────────────────────────
let indexDirty = false;

if (autoArchived.length > 0) {
  if (!index.archived) index.archived = [];
  const archivedIds = new Set(autoArchived.map(i => i.id));

  for (const inst of autoArchived) {
    inst._archived_at = isoNow;
    inst._archived_reason = "dream_cycle_auto: draft + 0 occurrences + >90 days";
    index.archived.push(inst);
  }

  index.instincts = index.instincts.filter(i => !archivedIds.has(i.id));
  indexDirty = true;

  // Log auto-archival
  try {
    const ids = autoArchived.map(i => i.id).join(", ");
    fs.appendFileSync(LOG_FILE, isoNow + " | dream-cycle | auto-archived: " + ids + "\n");
  } catch (e) {}
}

// ── GENERATE REPORT ───────────────────────────────────────────────────────────
const lines = [];
lines.push("# Sinapsis Dream Report");
lines.push("> Generated: " + isoNow);
lines.push("");

// Executive Summary
lines.push("## Executive Summary");
lines.push("Health Score: **" + score + "/100**");
lines.push("- " + total + " instincts (" + (totalByLevel.permanent || 0) + " permanent, " + (totalByLevel.confirmed || 0) + " confirmed, " + (totalByLevel.draft || 0) + " draft)");
lines.push("- " + activatedCount + " active (" + coverageRatio + "% coverage)");
lines.push("- " + autoArchived.length + " auto-action(s) taken");
lines.push("- " + duplicateFindings.length + " duplicate candidate(s)");
lines.push("- " + contradictionFindings.length + " contradiction(s)");
lines.push("- " + triggerFindings.length + " trigger issue(s)");
lines.push("");

// Module 1: Duplicates
lines.push("## Module 1: Duplicates");
if (duplicateFindings.length === 0) {
  lines.push("No duplicates detected.");
} else {
  lines.push("| Pair | Similarity | Reason |");
  lines.push("|------|-----------|--------|");
  for (const f of duplicateFindings) {
    lines.push("| " + f.ids.join(" / ") + " | " + f.similarity + " | " + f.reason + " |");
  }
}
lines.push("");

// Module 2: Contradictions
lines.push("## Module 2: Contradictions");
if (contradictionFindings.length === 0) {
  lines.push("No contradictions detected.");
} else {
  lines.push("| Pair | Reason |");
  lines.push("|------|--------|");
  for (const f of contradictionFindings) {
    lines.push("| " + f.ids.join(" / ") + " | " + f.reason + " |");
  }
}
lines.push("");

// Module 3: Staleness
lines.push("## Module 3: Staleness");
lines.push("### Auto-Actions Taken");
if (autoArchived.length === 0) {
  lines.push("No auto-actions taken.");
} else {
  for (const inst of autoArchived) {
    lines.push("- **" + inst.id + "**: auto-archived (draft, 0 occurrences, >" + daysBetween(inst.added) + " days old)");
  }
}
lines.push("");
lines.push("### Flagged for Review");
const reviewItems = stalenessFindings.filter(f => !f.autoArchived);
if (reviewItems.length === 0) {
  lines.push("All instincts are fresh.");
} else {
  lines.push("| ID | Freshness | Days Since Triggered | Days Since Added |");
  lines.push("|----|-----------|---------------------|-----------------|");
  for (const f of reviewItems) {
    lines.push("| " + f.id + " | " + f.freshness + " | " + f.daysSinceTriggered + " | " + f.daysSinceAdded + " |");
  }
}
lines.push("");

// Module 4: Trigger Validation
lines.push("## Module 4: Trigger Validation");
if (triggerFindings.length === 0) {
  lines.push("All trigger patterns are valid.");
} else {
  lines.push("| ID | Issue | Detail |");
  lines.push("|----|-------|--------|");
  for (const f of triggerFindings) {
    lines.push("| " + f.id + " | " + f.issue + " | " + (f.detail || "") + " |");
  }
}
lines.push("");

// Module 5: Index Health
lines.push("## Module 5: Index Health");
lines.push("");
lines.push("### Level Distribution");
lines.push("| Level | Count |");
lines.push("|-------|-------|");
for (const [lvl, cnt] of Object.entries(totalByLevel)) {
  if (cnt > 0) lines.push("| " + lvl + " | " + cnt + " |");
}
lines.push("");

lines.push("### Domain Distribution");
lines.push("| Domain | Count |");
lines.push("|--------|-------|");
const sortedDomains = Object.entries(domainDistribution).sort((a, b) => b[1] - a[1]);
for (const [dom, cnt] of sortedDomains) {
  lines.push("| " + dom + " | " + cnt + " |");
}
lines.push("");

lines.push("### Top 5 Most Active");
lines.push("| ID | Occurrences |");
lines.push("|----|-------------|");
for (const t of top5Active) {
  lines.push("| " + t.id + " | " + t.occurrences + " |");
}
lines.push("");

lines.push("### Bottom 5 Least Active");
lines.push("| ID | Occurrences |");
lines.push("|----|-------------|");
for (const b of bottom5Active) {
  lines.push("| " + b.id + " | " + b.occurrences + " |");
}
lines.push("");

// ── WRITE REPORT (atomic: tmp + rename) ───────────────────────────────────────
const reportContent = lines.join("\n");
const reportTmp = REPORT_FILE + ".tmp";
try {
  fs.writeFileSync(reportTmp, reportContent);
  fs.renameSync(reportTmp, REPORT_FILE);
} catch (e) {
  // fallback: direct write
  try { fs.writeFileSync(REPORT_FILE, reportContent); } catch (e2) {}
}

// ── WRITE INDEX (atomic, only if auto-actions taken) ──────────────────────────
if (indexDirty) {
  const indexTmp = INDEX_FILE + ".tmp";
  try {
    fs.writeFileSync(indexTmp, JSON.stringify(index, null, 2));
    fs.renameSync(indexTmp, INDEX_FILE);
  } catch (e) {
    try { fs.writeFileSync(INDEX_FILE, JSON.stringify(index, null, 2)); } catch (e2) {}
  }
}

// ── LOG ───────────────────────────────────────────────────────────────────────
try {
  const summary = "report generated | " +
    "duplicates=" + duplicateFindings.length +
    " contradictions=" + contradictionFindings.length +
    " stale=" + stalenessFindings.length +
    " trigger_issues=" + triggerFindings.length +
    " auto_archived=" + autoArchived.length +
    " | score=" + score;
  fs.appendFileSync(LOG_FILE, isoNow + " | dream-cycle | " + summary + "\n");
} catch (e) {}

} finally {
  // ── UNLOCK ──────────────────────────────────────────────────────────────────
  try { fs.unlinkSync(LOCK_FILE); } catch (e) {}
}
' "$INDEX_FILE" "$REPORT_FILE" "$LOCK_FILE" "$LOG_FILE" 2>/dev/null

exit 0
