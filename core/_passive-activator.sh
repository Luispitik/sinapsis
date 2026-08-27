#!/bin/bash
# Passive Activator - Sinapsis v4.1
# PreToolUse hook (sync, 5s): reads _passive-rules.json, matches trigger regex
# against current tool+input, injects matched rules as systemMessage.
# Only matched rules are injected (~20-80 tokens per tool use).

RULES="$HOME/.claude/skills/_passive-rules.json"
[ ! -f "$RULES" ] && exit 0

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

  let cfg;
  try {
    // v4.6.2: strip UTF-8 BOM (#16) — JSON.parse throws on it, silently disabling all rules
    let raw = fs.readFileSync(process.argv[1], "utf8");
    if (raw.charCodeAt(0) === 0xFEFF) raw = raw.slice(1);
    cfg = JSON.parse(raw);
  } catch(e) { process.exit(0); }

  const rules = cfg.rules || [];
  if (rules.length === 0) process.exit(0);

  // Build context string from tool name + input fields
  const tool = data.tool_name || "";
  let inputContent = "";
  try {
    const inp = data.tool_input || {};
    inputContent = [inp.command, inp.file_path, inp.pattern, inp.prompt, inp.content]
      .filter(Boolean).join(" ").slice(0, 500);
  } catch(e) {}
  const context = tool + " " + inputContent;

  // Match rules: test trigger regex against context
  // Same inline-flag trap as the instinct activator: `(?i)` is Python/PCRE syntax
  // that JavaScript rejects, and the catch below would hide the rule forever. The
  // shipped rules are clean today, but they are hand-written like the instincts, so
  // the next one added is one `(?i)` away from vanishing without a trace.
  function normalizeInlineFlags(pattern) {
    if (typeof pattern !== "string" || pattern.indexOf("(?") === -1) return pattern;
    return pattern.replace(/\(\?([imsxu]+)\)/g, "");
  }

  const matched = [], matchedIds = [];
  for (const rule of rules) {
    if (!rule.trigger || !rule.inject) continue;
    // EVERY_SESSION rules always fire
    if (rule.trigger === "EVERY_SESSION") {
      matched.push(rule.inject); matchedIds.push(rule.id || "unknown");
      continue;
    }
    try {
      // v4.3.1: ReDoS protection — reject patterns with nested quantifiers
      const trigger = normalizeInlineFlags(rule.trigger);
      if (/(\+|\*|\{)\)?(\+|\*|\{)/.test(trigger)) continue;
      if (new RegExp(trigger, "i").test(context)) {
        matched.push(rule.inject); matchedIds.push(rule.id || "unknown");
      }
    } catch(e) { continue; }
  }

  if (matched.length === 0) process.exit(0);

  // Cap at 3 rules to avoid token bloat
  const top = matched.slice(0, 3);
  const topIds = matchedIds.slice(0, 3);
  // Telemetry: log fired rules so the dashboard & /passive-status can track activations.
  // Format: "TIMESTAMP | rule_id | tool" (rule_id between pipes, matches dashboard parser).
  try {
    const logPath = process.argv[1].replace(/_passive-rules\.json$/, "_passive.log");
    const ts = new Date().toISOString();
    fs.appendFileSync(logPath, topIds.map(id => ts + " | " + id + " | " + tool + "\n").join(""));
  } catch(e) {}
  console.log(JSON.stringify({ systemMessage: top.join("\n") }));
});
' "$RULES" 2>/dev/null

exit 0
