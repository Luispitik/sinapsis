# Sinapsis v4.10

[![Version](https://img.shields.io/badge/version-4.10.0-blue.svg)](https://github.com/Luispitik/sinapsis)
[![Tests](https://img.shields.io/badge/tests-226%20passing-green.svg)](tests/)
[![CI](https://github.com/Luispitik/sinapsis/actions/workflows/tests.yml/badge.svg)](https://github.com/Luispitik/sinapsis/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

### The skill system for Claude Code that learns and adapts to you.

> Stop explaining the same thing twice. Sinapsis remembers, learns, and gets better with every session.

---

## What is Sinapsis?

Sinapsis is an intelligent skill management system for [Claude Code](https://claude.ai/code). It solves a fundamental problem: **Claude Code forgets everything between sessions.**

Every time you start a new session, Claude starts from zero. Your preferences, your tech stack, your workflows, your past decisions — all gone. You end up repeating yourself. Again. And again.

**Sinapsis fixes this.** It gives Claude Code:

- **Memory that persists** across sessions and projects
- **Skills that load on demand** instead of all at once
- **A learning engine** that observes what you do and creates reusable patterns
- **A router** that knows which tools you need for each project

Think of it as going from a dumb terminal to an assistant that actually knows you.

---

## What's New in v4.10.0 — The registry asks, it no longer guesses

**mac ↔ linux finally de-duplicates.** The cross-OS registry key used to classify a project root by its path shape into two families, `windows` and `posix` — so the same no-remote project seen from a Mac and from a Linux box stayed two entries forever. The family of a sighting is now a *fact asked of the machine at observation time* (`uname -s`: `Darwin` → `mac`, `Linux` → `linux`, `MINGW*`/`MSYS*` → `windows`) instead of a guess reconstructed from the path afterwards. Legacy `posix` keys are deliberately **not** reclassified — that would be guessing again; each machine rewrites its own key the next time it sees the project at the same path, and from then on the pair merges. Where the rewrite cannot apply (a root that moved since v4.9.0) the entry keeps missing that merge rather than guessing — cosmetic, and curable by deleting the entry. Design argued and approved in #32; approach by [@Sergio-LPA](https://github.com/Sergio-LPA).

## What's New in v4.9.0 — Cleaner signal, one project per project

**The learner stopped inventing work.** `observe_v3.py` used to flag a tool call as failed whenever its output contained the word `error` — including the *content of files it had just read successfully*. A `Read` of source code with `throw new Error` looked exactly like a crash. One real session produced 190 proposals of which 189 were noise. Detection is now structural (harness-reported failure shapes), plus hard failure markers over execution output, plus a shape-and-length check for other tools, so a genuine `Edit`/`Read` failure is caught while a payload that merely *mentions* an error is not. On a real 8,000-observation window, flagged observations dropped from 1,074 to 22. Thanks to [@juanparisma](https://github.com/juanparisma) (#29).

**One project, one entry.** A project with no git remote used to get a different id on every machine, because the id derives from its root and roots differ by OS. On a shared registry it showed up twice, forever. Entries now carry a cross-OS-stable key, keep every per-OS id as an alias, and record both roots — and a migration pass heals registries that already drifted. Where the match rests on the folder name alone it can still be wrong, so it stamps itself and logs, instead of merging quietly. Thanks to [@Sergio-LPA](https://github.com/Sergio-LPA) (#22).

**Secret scrubbing is actually tested now.** The assertions that were supposed to prove it had been silently reporting SKIP since they were written — they tried to import a script that cannot be imported, then looked for a function that does not exist. They now drive the real hook with a real secret and check what reached disk.

## What's New in v4.8.0 — Plexus moves to the team edition

Sinapsis returns to what it has been since the v4.3.2 separation: **individual autonomous
learning, and only that**. The team layer (Sinapsis Plexus — shared knowledge over a private
git repo, PM directives, traceability, quarantine trust model) shipped here briefly as v4.7.0
and now lives in the **private team edition**, where team-oriented development continues.
Same clean-extraction pattern as the gstack separation in v4.3.2.

- All Plexus code, commands, docs and tests removed from this repo (v4.7.0 remains in the
  git history under MIT).
- The public installer neither installs **nor removes** `_plexus-sync.sh` / `plexus.md` —
  those files may belong to a team-edition install layered on top of this one.
- New `tests/test-plexus-separation.sh` guards the boundary (no plexus references in live
  code paths).
- Interested in the team edition? It builds on exactly this individual pipeline — reach out.

## What's New in v4.6.0 — Opus 4.8

> Same deterministic core, tuned for 4.8's longer attention span.

- **Aligned to Claude Opus 4.8.** The cache-stable instinct ordering from v4.5 pays off harder here: Opus 4.8 lowers the minimum cacheable prompt to **1,024 tokens** and accepts **mid-conversation `system` messages** — exactly the shape of Sinapsis's per-turn `systemMessage` injection — so the byte-stable instinct block caches more readily (~90 % read discount once warm).
- **Caps re-tuned for 4.8's long-context handling**: `MAX_INSTINCTS_INJECTED` 6 → 8, `TOKEN_BUDGET` 4000 → 6000, learner observation window 5000 → 8000 lines. 4.8 holds longer context with fewer compactions, so a richer per-turn injection and a longer cross-session window carry no quality regression.
- **Hot path stays model-free.** The activator and learner remain pure bash/node; Opus 4.8's `effort` parameter (default `high` in Claude Code) needs no Sinapsis change because Sinapsis never calls the model itself.
- **RFC retargeted** ([`docs/rfc-v5-adaptive-thinking.md`](docs/rfc-v5-adaptive-thinking.md)): the opt-in `/analyze-session` SDK path now uses `claude-opus-4-8` with adaptive thinking + `effort`.
- **New guard tests** (`tests/test-v46-opus48.sh`): assert the re-tuned caps and that no stale `claude-opus-4-7` reference lingers in docs or core.

## What's New in v4.5.0 — Opus 4.7 Integration

> Ride the cache, catch the compaction, raise the ceiling.

- **Cache-stable instinct ordering**: added an `id.localeCompare` tiebreaker after the priority + occurrences sort. The injected `systemMessage` prefix is now byte-stable across consecutive tool uses, which unlocks prompt-cache hits on Opus 4.7's cached system block (~90 % discount on the instinct payload once the cache warms).
- **New `PreCompact` hook** (`_precompact-guard.sh`): fires right before Claude Code compacts the context in long-running sessions and re-runs the session-learner so fresh observations are flushed to proposals before the transcript is rewritten. Uses a fire-and-forget pattern with an 8 s cap — compaction is never blocked.
- **Caps raised for 1M context**: `TOKEN_BUDGET` 1500 → 4000, top-N instincts per tool use 3 → 6, observation window for the learner 1000 → 5000 lines. Cross-session detectors (repetitions, agent patterns) see a longer history; per-turn injection can surface more relevant rules.
- **Opt-in adaptive thinking for `/analyze-session`**: design published in [`docs/rfc-v5-adaptive-thinking.md`](docs/rfc-v5-adaptive-thinking.md). Not shipped enabled — core stays fully deterministic, SDK path is additive and gated by `SINAPSIS_LLM_ANALYZE=1`.
- **11 new TDD tests** (`tests/test-v45-opus47.sh`): shuffled-index byte-identical output, alphabetical tiebreaker, PreCompact wiring end-to-end, and cap assertions. All existing suites re-run clean: 112 total passing.

## What's New in v4.4.0 — Observability Dashboard

> See the system that sees you.

- **`/dashboard-sinapsis`** command: generates a self-contained HTML dashboard (`~/.claude/skills/_dashboard.html`) with real data parsed from your instincts, passive rules, proposals, skills catalog, projects and activation logs.
- **Editorial design**: serif display typography (Instrument Serif) on deep ink background with warm accents (lime / coral / sky / amber). Not the usual dashboard chrome.
- **8 metric sections**: hero KPIs · velocity (creation rate per week) · timings (hour-of-day distribution + maturation phases) · 21-day activity heatmap · funnel observations→permanent · 10-point leaderboards (instincts / passive rules) · skills donut + dead-instincts table · projects ranking · decision timeline.
- **Zero LLM, zero tokens**: pure Python deterministic parser of 8 data sources. Milliseconds to regenerate.
- **Portable**: honors `$SINAPSIS_HOME` env var or falls back to `~/.claude/`. Works on macOS / Linux / Windows (Git Bash).
- **12 new TDD tests** (`tests/test-dashboard.sh`) — 95 total passing.

## What's New in v4.3.3 — Hardening + Portability

### From the Cortex v3.10 Comparison (credit: [Fernando Montero / fs-cortex](https://github.com/fermonterom/fs-cortex))
- **`/downvote`**: demote or archive instincts that give bad advice. Closes the feedback loop.
- **Multi-session auto-promote**: drafts need 5+ occurrences AND 3+ distinct sessions (not just 5 hits in one session).
- **5 pattern detectors**: error-fix, corrections, workflow chains, repetitions (3+ sessions), agent patterns.
- **8 secret scrubbing patterns**: +Stripe, Slack, SendGrid (was 5).
- **Path traversal protection** + **token budget cap** (1500 chars/tool-use) in instinct injection.
- **GitHub Actions CI**: tests on Ubuntu, macOS, Windows on every push.
- **Pre-push hook**: blocks push if tests fail.

### Portability
- **`/backup [path]`**: export your full Sinapsis state to a folder. Sync via OneDrive, Dropbox, or USB.
- **`/restore [path]`**: import on another machine with intelligent merge (by ID, keeps local data).
- **`/cleanup`**: remove legacy files, orphan projects, old archives from homunculus.

### Previous versions

<details>
<summary>v4.3 — Dream Cycle</summary>

5-module index hygiene system inspired by Anthropic's AutoDream. Duplicate detection, contradiction detection, staleness scoring, trigger validation, health metrics. 40 new tests.
</details>

<details>
<summary>v4.2 — Occurrence Tracking + Multi-project EOD</summary>

3 pattern detectors (error-fix, user-corrections, workflow-chains). Occurrence tracking with auto-promote at 5+ matches. Domain pre-filter by project stack. Multi-project `/eod`.
</details>

<details>
<summary>v4.1 — Closed Learning Pipeline</summary>

End-to-end observe → learn → inject pipeline. 3-level confidence model (draft/confirmed/permanent). Domain deduplication. Project context bridge.
</details>

See [CHANGELOG.md](CHANGELOG.md) for full details.

---

## The Problem (Before Sinapsis)

| Issue | Impact |
|-------|--------|
| All skills loaded every session | ~25,000 tokens wasted before you say a word |
| No memory between sessions | You explain your stack, preferences, and context every time |
| No memory between projects | Decisions in project A don't carry to project B |
| No skill management | 50+ skills compete for attention, most irrelevant |
| No learning | Claude doesn't improve from session to session |

**In short: you do the same work over and over, and Claude never gets smarter.**

---

## The Solution (With Sinapsis)

| Feature | How it works |
|---------|-------------|
| **Skills on Demand** | Only loads the skills your current project needs (~2,800 tokens vs ~25,000) |
| **Operator State** | Your identity, stack, and decisions persist across ALL projects |
| **Sinapsis Engine** | 4 deterministic hooks: observe, inject, learn, bridge |
| **Skill Router** | Matches your intent to the right skills from a dormant catalog |
| **Passive Rules** | Technical guardrails that fire automatically (security, quality, workflow) |
| **Instinct Injection** | Learned patterns injected silently when context matches |
| **Project Cloning** | Clone a successful project as the base for a new one |

**Result: 90% less token waste. Zero repetition. Claude that actually improves.**

---

## Quick Start

### Requirements
- [Claude Code](https://claude.ai/code) installed
- [Node.js](https://nodejs.org) v18+ (required — injection hooks use it)
- [Python 3](https://python.org) (recommended — required for the observation pipeline that feeds the learning system; without it, passive rules and instinct injection still work, but Claude won't learn from your sessions)
- Git
- Git Bash (Windows only — needed to run `.sh` hook scripts)

### Fresh Installation

**macOS / Linux:**
```bash
git clone https://github.com/Luispitik/sinapsis.git
cd sinapsis
chmod +x install.sh
./install.sh
```

**Windows (Command Prompt):**
```cmd
git clone https://github.com/Luispitik/sinapsis.git
cd sinapsis
install.bat
```

> **Windows note:** The `.sh` hook scripts run via Git Bash or WSL. If you use Claude Code on Windows, make sure Git Bash is installed and Claude Code can access it. The installer will remind you of this.

After install, open Claude Code in any project folder. Sinapsis guides you through first-time setup.

---

## Upgrading from v3.2

If you already have v3.2 installed, the installer handles the upgrade automatically — it backs up your existing installation first and preserves your `operator-state.json` and `CLAUDE.md`.

```bash
# Pull the latest changes
git -C sinapsis pull origin main

# Run the installer again — it detects the upgrade automatically
cd sinapsis
./install.sh        # macOS / Linux
# install.bat       # Windows
```

**What the upgrade adds:**

| File | Where | What it does |
|------|-------|-------------|
| `_passive-activator.sh` | `~/.claude/skills/` | Fires matching passive rules per tool use |
| `_instinct-activator.sh` | `~/.claude/skills/` | Injects matched instincts per tool use |
| `_session-learner.sh` | `~/.claude/skills/` | Writes `context.md` + detects patterns at session end |
| `_project-context.sh` | `~/.claude/skills/` | Injects last-session context at session start (once) |
| `_instincts-index.json` | `~/.claude/skills/` | Instinct registry (starts with 3 generic examples) |

**If you prefer to upgrade manually:**

```bash
# 1. Pull the repo
git pull origin main

# 2. Copy the new scripts
cp core/_passive-activator.sh ~/.claude/skills/
cp core/_instinct-activator.sh ~/.claude/skills/
cp core/_session-learner.sh ~/.claude/skills/
cp core/_project-context.sh ~/.claude/skills/
chmod +x ~/.claude/skills/_passive-activator.sh
chmod +x ~/.claude/skills/_instinct-activator.sh
chmod +x ~/.claude/skills/_session-learner.sh
chmod +x ~/.claude/skills/_project-context.sh

# 3. Copy the new config files
cp core/_instincts-index.json ~/.claude/skills/
cp core/_passive-rules.json ~/.claude/skills/   # optional: review before overwriting

# 4. Add hooks to ~/.claude/settings.json
# See core/settings.template.json for the exact format
```

**Windows manual upgrade:**
```cmd
copy /Y core\_passive-activator.sh %USERPROFILE%\.claude\skills\
copy /Y core\_instinct-activator.sh %USERPROFILE%\.claude\skills\
copy /Y core\_session-learner.sh %USERPROFILE%\.claude\skills\
copy /Y core\_project-context.sh %USERPROFILE%\.claude\skills\
copy /Y core\_instincts-index.json %USERPROFILE%\.claude\skills\
```

**Then update `settings.json`** — see `core/settings.template.json` for the 6-hook configuration. If you already have hooks, merge them rather than overwriting.

---

## How It Works

### The Session Flow

```
Open Claude Code
       |
       v
  CLAUDE.md loads (entry point)
       |
       v
  Read Operator State
  (your identity + decisions)
       |
       v
  Check for EOD summary
  (auto-resume if exists)
       |
       v
  Launcher appears
  (skipped if resuming):
  [1] Skills on Demand
  [2] Skill Picker (manual)
  [3] Freestyle (vanilla)
       |
       v
  Install ONLY what you need
  (~2,800 tokens instead of ~25,000)
       |
       v
  You work normally
  Hooks observe silently (deterministic)
       |
       v
  Run /eod before closing
  (saves context for tomorrow)
```

### The Learning Pipeline (v4.1)

```
  You work on your project
         |
         v
  observe.sh logs every tool use
  → observations.jsonl (local only)
         |
         v
  Session ends (Stop hook)
         |
    session-learner runs:
    ├── Writes context.md per project
    └── Detects error→fix patterns
        → _instinct-proposals.json
         |
         v
  Next session:
  context.md injected (once, first tool use)
         |
         v
  You run /analyze-session
  → Review proposals → Accept
  → _instincts-index.json (confirmed)
         |
         v
  Future sessions:
  _instinct-activator.sh matches
  instincts → injects as context
         |
         v
  Pattern matures? Run /evolve
  → Create Skill, Command, Rule...
         |
         v
  Cycle repeats.
  Every session feeds the next.
```

---

## The Hook Architecture (v4.1)

Sinapsis uses 6 deterministic hooks configured in `settings.json`:

| Hook | Event | Type | Purpose |
|------|-------|------|---------|
| `observe.sh pre` | PreToolUse | async | Log tool name + input |
| `_project-context.sh` | PreToolUse | sync (3s) | Inject last session context (once/session) |
| `_passive-activator.sh` | PreToolUse | sync (5s) | Fire matching passive rules |
| `_instinct-activator.sh` | PreToolUse | sync (5s) | Inject matched instincts |
| `observe.sh post` | PostToolUse | async | Log tool output + is_error flag |
| `_session-learner.sh` | Stop | sync (15s) | Write context.md + detect error patterns |

See `core/settings.template.json` for the exact configuration.

---

## Token Budget

| Component | Tokens | When |
|-----------|--------|------|
| 2 global skills (router + learning) | ~2,800 | Every session |
| Passive rules (matched only) | ~20–80 | Per matching tool use |
| Instincts (matched only) | ~50–200 | Per matching tool use |
| Project context bridge | ~50–150 | Once per session |
| **Total session start** | **~2,800–3,200** | vs ~25,000 before |

---

## Commands

| Command | What it does |
|---------|-------------|
| `/system-status` | Full dashboard: skills, tokens, projects, health |
| `/evolve` | Analyze mature instincts, create skills/rules/commands |
| `/analyze-session` | Review proposals from session-learner, accept/reject |
| `/passive-status` | Which passive rules fire, which never triggered |
| `/instinct-status` | All learned patterns with levels + `--cross-project` search |
| `/promote` | Move instinct from project scope to global |
| `/projects` | List all known projects with stats |
| `/eod` | Save work context for tomorrow's session |
| `/dream` | Run dream cycle: index hygiene with 5-module analysis |
| `/downvote` | Demote or archive instincts that give bad advice |
| `/backup [path]` | Export full Sinapsis state for sync between machines |
| `/restore [path]` | Import state from backup with intelligent merge |
| `/cleanup` | Remove legacy files, orphan projects, old archives |

### Session Continuity (`/eod`)

Never lose context between sessions. Run `/eod` before closing Claude:

1. Sinapsis captures your git activity, open PRs, and learning progress
2. You add priorities and notes for tomorrow
3. Next morning, Claude greets you with a summary and asks where to start

No more "what was I doing yesterday?" — Sinapsis remembers for you.

Use `/eod --quick` for a fast auto-generated summary, or `/eod --yesterday` to review your last saved session.

---

## Architecture

```
~/.claude/
  CLAUDE.md                    <-- Entry point (loaded every session)
  skills/
    skill-router/              <-- Orchestrator (always active)
    sinapsis-learning/         <-- Learning engine (always active)
    _library/                  <-- Dormant skills (installed on demand)
    _archived/                 <-- Retired skills (recoverable)
    _daily-summaries/          <-- EOD session summaries (auto-resume)
    _catalog.json              <-- Skill registry with token estimates
    _passive-rules.json        <-- Automatic guardrails
    _passive-activator.sh      <-- Hook: fires matching passive rules
    _instinct-activator.sh     <-- Hook: injects matched instincts
    _instincts-index.json      <-- Instinct registry
    _instinct-proposals.json   <-- Draft proposals from session-learner
    _project-context.sh        <-- Hook: injects project context (once/session)
    _session-learner.sh        <-- Stop hook: writes context + detects patterns
    _dream.sh                  <-- Dream cycle: 5-module index hygiene
    _operator-state.json       <-- Your identity + decisions (cross-project)
    _sinapsis-projects.json             <-- Project registry
  commands/                    <-- Slash commands (/evolve, /dream, etc.)
  homunculus/
    projects/{hash}/
      observations.jsonl       <-- Raw tool observations (local only)
      context.md               <-- Last session summary (14-day TTL)
```

---

## FAQ

**Does this work with any Claude Code project?**
Yes. Sinapsis is project-agnostic. It adapts to whatever you're building.

**Will it slow down Claude?**
No. Async hooks don't block responses. By reducing token overhead by ~90%, Claude has more context for actual work.

**Can I use it without the learning system?**
Yes. Choose [3] Freestyle in the launcher for vanilla Claude Code.

**Can I create my own instincts?**
Yes. Edit `_instincts-index.json` directly, or use `/evolve`, or tell Claude "learn this pattern."

**Can I create my own passive rules?**
Yes. Use `/evolve → [R]` or edit `_passive-rules.json` directly.

**Does it work on Windows, Mac, and Linux?**
Yes. Installers for all three platforms included.

**Is my data sent anywhere?**
No. All observations, instincts, and context files stay in `~/.claude/homunculus/` on your machine.

---

## Want More?

Sinapsis is the open-source foundation. If you want:

- **Custom skills** for your business or industry
- **Mentoring** on how to build and optimize your own skill system
- **Advanced features** like marketplace integration and team sharing
- **Training** for your team on Claude Code + Sinapsis

Visit **[salgadoia.com](https://salgadoia.com)** for mentoring, courses, and consulting.

---

## License

Sinapsis is released under the **MIT License** — free for personal, commercial, and any other use, including modification, distribution, and sale. The only condition is that the copyright notice in [LICENSE](LICENSE) is preserved.

---

## Credits

Built by [Luis Salgado](https://salgadoia.com) — AI consultant, developer, and educator.

Powered by [Claude Code](https://claude.ai/code) by Anthropic.

v4.3.3 hardening inspired by [Fernando Montero / fs-cortex](https://github.com/fermonterom/fs-cortex) (Cortex v3.10 comparison analysis). Confidence decay inspired by [garrytan/gstack](https://github.com/garrytan/gstack) (MIT License). v4.3.1 security audit by Fernando Montero (Fersora Solutions).

---

*Sinapsis: because your AI assistant should remember who you are.*
