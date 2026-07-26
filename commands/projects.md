# /projects -- Project Registry

> List known projects with instinct count, observation count,
> installed skills, and activity status.

---

## Trigger

Run with `/projects` or "list my projects".

---

## Process

1. Read `~/.claude/skills/_sinapsis-projects.json`
2. Read `~/.claude/skills/_instincts-index.json` for per-project instinct counts
3. Read `~/.claude/homunculus/projects/{hash}/observations.jsonl` for per-project observation counts — and, for entries with an `aliases` array (cross-OS de-dup keeps every per-OS id there), ALSO add the observations from each `~/.claude/homunculus/projects/{alias}/observations.jsonl` to the same project's count
4. Display dashboard

---

## Dashboard Format

```
KNOWN PROJECTS

  #  Project              Skills  Instincts  Observations  Last Active   Status
  1. project-alpha          12       45          156       today         ACTIVE
  2. project-beta            8       23           89       3 days ago    ACTIVE
  3. project-gamma           5       12           34       3 weeks ago   IDLE
  4. project-delta           3        4           12       2 months ago  STALE

  Current project: project-alpha

  GLOBAL STATS
  ─────────────
  Total projects:     4
  Active (< 7 days):  2
  Idle (7-30 days):   1
  Stale (> 30 days):  1
  Total instincts:    84 (15 global + 69 project)
  Total observations: 291

  PROJECT DETAILS
  ───────────────
  Enter a number for details, or:
  [C] /clone a project  [A] Archive stale  [N] Register new  [X] Close
```

### Detailed View (when user selects a project)

```
PROJECT: project-alpha
  Path:          /path/to/project-alpha
  Created:       2025-01-10
  Last active:   today
  Description:   E-commerce platform

  INSTALLED SKILLS (12):
    api-builder, db-migrations, testing-suite, proposal-writer,
    error-handling, auth-patterns, deploy-checklist, form-builder,
    email-templates, analytics, monitoring, security-audit

  TOKEN OVERHEAD: ~9,800 tokens/session

  INSTINCTS (15):
    Permanent:   3
    Confirmed:   8
    Drafts:      4 (pending /analyze-session)

  TOP INSTINCTS:
    [permanent] security: "Never hardcode secrets"
    [confirmed] git: "Use conventional commits"
    [confirmed] code-quality: "Handle errors explicitly"

  BLUEPRINT: Available (can be cloned with /clone)

  [B] Back  [C] Clone  [S] Skill audit  [I] Instinct details
```
