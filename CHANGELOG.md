# Changelog

## v4.9.0 (2026-07-27)

### Added

- **Cross-OS project de-dup in the registry** (`_session-learner.sh`): the per-project id is `sha256(remote || root)`, so a project with **no git remote** gets a different id on each OS (its root differs — `/Users/me/Proj` vs `C:/Users/Me/Proj`). When the registry is shared between machines (e.g. a synced folder), the same project surfaced as two entries — duplicating it in `/projects`, `/eod` and cross-project instinct search. The learner now matches on a cross-OS-stable key (the git remote when present, otherwise the project name), so the two sightings collapse into one entry: each per-OS id is preserved in `aliases[]`, and each observed root is stored under `roots.{posix,windows}`. The name key is **restricted to the genuine cross-OS scenario**: it only matches an entry whose root belongs to a different OS family and that has no root of the candidate's family recorded, so two same-named projects on the same machine (`~/work/app` vs `~/personal/app`) always stay separate. Projects **with** a remote already shared one id and are unaffected; the remote key takes precedence over the name. Purely additive — the new `aliases`, `roots` and `crossKey` fields are optional and ignored by readers that don't use them.
- **Migration pass for pre-existing duplicates**: registries that already contain both per-OS entries (written by pre-feature learners and synced since) are cured on the next Stop event — entries with the same cross-OS key merge under the same family guard as the lookup, with union of `aliases`/`roots`, the oldest `created` and the newest `last_seen`; `crossKey` is backfilled for legacy entries.
- **Alias-aware consumers**: `_eod-gather.sh` resolves observations recorded under an aliased per-OS id to the merged project, and `/projects` counts observations from each alias's `homunculus/projects/{alias}/` directory.
- **Name-key fusions are stamped and logged.** The name fallback cannot rule out two *unrelated* projects that merely share a folder name (`app`, `api`, `docs`) seen from a Windows and a posix machine — with no remote there is nothing left to tell them apart. Guarding it away would cost more than it saves: requiring a matching parent directory breaks the legitimate case, where one project lives at a different path on each OS. So the limit is accepted and made visible instead — every name-based fusion sets `name_merged` on the entry, records the offending root pair in `name_merge_log`, and appends a line to `_session-learner.log`. A wrong fusion becomes an auditable event rather than silent registry drift.

### Fixed

- **Session-learner false positives eliminated** (#29, @juanparisma): `observe_v3.py` set `is_error` whenever the output contained the substring `error`/`failed` — *including the content of files read successfully*, so a `Read` of source code containing `throw new Error` was recorded as a tool failure. One real session produced 190 proposals of which 189 were junk. Detection is now (a) structural — harness-reported failure shapes, every tool; (b) hard failure markers over execution output (`Bash`, `PowerShell`), which is a verdict rather than arbitrary content; (c) hard markers over bare, short output from other tools. `user_correction` no longer counts files re-edited by design (journals, control panels, daily summaries), and `workflow_chain` requires 5+ repetitions with at least two distinct tools and one non-generic tool instead of proposing every `Bash>Bash>Bash` trigram. Measured over a real 8,000-observation window: 1,074 flagged observations drop to 22, `error_resolution` proposals from 11 to 3, `workflow_chain` from 507 to 51.
- **Genuine non-Bash tool failures are no longer discarded.** Restricting hard markers to `Bash` left real `Edit` and `Read` failures (`String to replace not found`, `File does not exist`) flagged by nobody — they are not harness-shaped, so the structural branch missed them too. Detection for these tools keys on *shape*: a failure returns a bare verdict string, a success returns a payload that serialises starting with `{` or `[`, and payloads are never scanned for marker words — that scan is the very bug this release fixes. Verified against 7,931 real non-Bash observations: zero false positives. `isRealError()` in the learner, which re-validates flags written by older observers still sitting in the observation window, stays deliberately tool-agnostic so PowerShell and MCP failures survive re-validation.
- **The session learner no longer discards its own diagnostics.** The node block ended in `2>/dev/null`, swallowing every message it emits — registry lock contention, failed upserts — and overriding the `SINAPSIS_DEBUG=1` redirect, so the debug switch produced nothing for the 95% of the script that runs inside that block. Diagnostics now append to `_session-learner.log`.
- **The cross-OS test suite could not run under Git Bash.** `MSYS_NO_PATHCONV=1` is needed suite-wide so posix fixtures survive argv conversion, but `newhome()` still returned a posix `mktemp -d` path, and node — a native Windows binary — resolves `/tmp/...` to a nonexistent `C:	mp...`. Every fixture write died with `ENOENT`: 0 of 10 tests actually ran on Windows while reporting green elsewhere. The suite now hands node a native path.

### Tests

- New `tests/test-crossos-registry.sh` — 13 hermetic tests (real hook driven via a sandbox `HOME`, `MSYS_NO_PATHCONV` exported for Git Bash): two-OS no-remote sighting collapses to one entry, both `roots.{posix,windows}` recorded, the second per-OS id registered as an alias, remote key beats name for same-named projects, idempotency on re-run, same-named same-family projects stay separate (anti-regression, both roots intact), pre-existing duplicate migration (merge + union semantics), Git Bash `/c/` roots classifying as the windows family, and — for the accepted name-key limit — that a name fusion is stamped `name_merged`, that both roots reach `name_merge_log` for audit, and that a *remote* fusion is **not** stamped, so the stamp means something. Registered in `.github/workflows/tests.yml`. Existing suites re-run clean: `test-install-upgrade` 21/21, `test-registry-isolation`, `test-eod-gather`, `test-bom-decay-python`, `test-v45-opus47`, `test-v46-opus48`.
- **Secret scrubbing is verified for the first time.** Test Group 4 of `test-security.sh` called `importlib.exec_module()` on `observe_v3.py` and then looked for a function named `scrub_secrets`. Both were wrong — the observer is a script (importing it runs `main()` and blocks on stdin) and the real function is `scrub`, nested inside `main` and unreachable from outside. Every assertion returned `LOAD_FAIL` and was reported as a SKIP, so a headline of "11/11 passed" covered scrubbing that had never been exercised. The group now drives the hook through the front door — a `PostToolUse` payload carrying a real secret — and asserts the secret is absent from what reached disk, across JWT, GitHub, AWS, Stripe and Slack formats, plus a control asserting non-secret output survives so an over-broad scrubber cannot pass by destroying everything.
- New `tests/test-error-detection.sh` (10 tests): successful `Read`/`Bash`/`Grep` whose content mentions errors stay unflagged, real `Bash`/`Edit`/`Read` failures are flagged, long payloads carrying a marker inside their content stay clean, and `isRealError()` remains tool-agnostic. Note for anyone extending it: the observer resolves its config dir with `expanduser("~")`, which on Windows reads `USERPROFILE`, not `HOME` — both must be redirected or the test writes into real learning data.
- Suite: **217 tests across 16 files**, green on ubuntu, macos and windows.

---

## v4.8.1 (2026-07-17)

### Fixed

- **Installers now wire hooks into an EXISTING `settings.json`** (external audit — iAmasters OS, finding #1): both installers used to print "merge hooks manually" and register nothing when the file already existed — which it almost always does — leaving a ghost install: files on disk, learning pipeline inert, no warning anywhere. New `core/_merge-hooks.js` (shared by install.sh and install.bat) creates the file when missing and otherwise deep-merges: only Sinapsis hooks whose `command` is not yet registered for that event are appended (dedup by trimmed command string), every existing entry — custom hooks, custom events, other plugins — is preserved untouched, a UTF-8 BOM is stripped (#16 family), a timestamped backup is written next to the file before modifying, and the write is atomic. A malformed `settings.json` aborts the merge with a warning and is left untouched; the install still completes.
- **Legacy cleanup archives instead of deleting** (finding #2, install.sh — install.bat never had a legacy-cleanup step): Step 5b did `rm -rf` over a hardcoded name list that can include a LIVE user directory (e.g. a still-active `synapis-learning` install). Legacy entries are now moved to `skills/_archived/legacy-<timestamp>/`, and only successful moves are counted/reported (an `mv` blocked by open handles warns and leaves the entry in place instead of claiming it was archived).
- **`install.bat` actually installs skill subdirectories** (finding #3): the skill copy loop used `xcopy` without `/E`, so `hooks/observe.sh` + `observe_v3.py` never reached disk on Windows — the observer recorded nothing even with hooks correctly wired. Also fixed: stale `%errorlevel%` reads inside parenthesised blocks (the `python` fallback always reported "Python 3 not found" on machines with `python` but no `python3`; the settings success message could report stale status) now use `!errorlevel!`, and the backup timestamp no longer depends on `wmic` (deprecated, removed in Windows 11 24H2+) — it uses PowerShell `Get-Date`.

- **Pre-merge adversarial review round (2026-07-18)** caught and fixed three more before release: (a) the `::` comments this PR initially added INSIDE `install.bat` parenthesised blocks aborted the whole batch at parse time on cmd.exe (exit 255 — Steps 1-6 ran, so hooks got wired to scripts that never reached disk; comments moved out of blocks and a new static assert forbids indented `::`); (b) `_merge-hooks.js` with `"hooks": []` (valid JSON, truthy) reported "merged" while `JSON.stringify` silently dropped the named properties set on the array — an empty array is now normalised to an object, any other non-object `hooks` is refused with the file left untouched; (c) `install.bat` python detection trusted `where python3`, which the Microsoft Store shim satisfies — it now mirrors install.sh (`py -3` first, then `python`, accepting only a `--version` that reports "Python 3.").

### Changed

- Version-consistency pass (finding #5): README title updated to v4.8; banners no longer pinned to stale versions ("v4.4 hooks" / "v4.5 hooks"); `/clone` no longer advertised by either installer (Step 5b archives it as legacy); `docs/quickstart.md` cleaned of the `synapis-*` era (skills listing, `/clone` section, `[SYNAPIS]` labels, uninstall paths).

### Tests

- New `tests/test-installer-hardening.sh` — 21 tests: `_merge-hooks.js` unit (create from template, merge into hook-less file, custom hooks/events preserved, idempotency, partial-wiring dedup, BOM strip, malformed file untouched, empty/non-empty `hooks` array), install.sh end-to-end over a pre-existing `settings.json` (wires all 7 hooks, double-install dedup, malformed file survives), legacy archiving (content intact under `_archived/legacy-*`), static installer asserts (xcopy `/E`, no `wmic`, `!errorlevel!` in block reads, no indented `::`), a version-consistency gate between CHANGELOG, installers and README, and — on Windows hosts — a smoke test that EXECUTES `install.bat` in a sandboxed `USERPROFILE` and asserts exit 0, `observe.sh` on disk, 7 hooks wired and commands installed (static greps cannot catch cmd.exe parse-time aborts). Registered in CI.

## v4.8.0 (2026-07-13)

### Changed — Sinapsis Plexus extracted to the private team edition

- **Sinapsis returns to individual-only autonomous learning.** The team layer (Plexus:
  shared knowledge over a private git repo, PM directives, metadata-only traceability,
  quarantine trust model) shipped here as v4.7.0 and now lives in the private team edition,
  where team-oriented development continues. Same clean-extraction pattern as the gstack
  separation in v4.3.2: `core/_plexus-sync.sh`, `commands/plexus.md`, `docs/PLEXUS.md` and
  `tests/test-plexus.sh` removed; installers and CI updated. v4.7.0 remains in the git
  history under MIT.
- **The public installer neither installs nor removes** `_plexus-sync.sh` / `plexus.md`:
  those files may belong to a team-edition install layered on top of this one, so the
  v4.8 upgrade never touches them (deliberately NOT added to the legacy-cleanup list).
- New `tests/test-plexus-separation.sh` guards the boundary: no plexus references in live
  code paths (core/, commands/, installers, CI); history and changelog references stay.

---

## v4.7.0 (2026-07-13)

### Added — Sinapsis Plexus (opt-in, OFF by default)

> A *plexus* is the anatomical level above the synapse: a network of nerves from multiple
> origins interweaving and redistributing signal with no center. Wire your team's synapses
> into one nervous system — peer-to-peer over git, no server, trust earned by your own use.

- **Team knowledge sharing over plain git** (`core/_plexus-sync.sh` + `/plexus`): a
  development team pools the instincts and project context each member's Sinapsis learned
  autonomously, through a private per-team git repo. `init/join/pull/share/review/directive/
  log/context/status/leave` subcommands, all deterministic bash + node — no LLM, no server,
  no accounts. Decision and trust model documented in `docs/PLEXUS.md` (same repo as an
  optional module, NOT a fork: the layer reuses the existing pipeline and touches **zero hooks**).
- **Trust rules**: shares require `confirmed`/`permanent` (your usage must validate what you
  publish); imports enter as `draft` (quarantine — never injected until the *importer's own
  usage* validates them via the existing occurrence tracking/auto-promote, or `/promote`);
  `permanent` is never importable; id collisions with personal instincts are skipped
  (personal wins); teammate revisions re-enter quarantine. `/plexus review` makes the
  quarantine actionable: pending imports, who shared them, distance to auto-promote.
- **PM directives** (`/plexus directive add|list|supersede`): project guidelines live as
  versioned frontmatter files in `directives/` in the team repo — human-readable,
  deterministically parseable, git history as audit trail. Deliberately **no code path**
  imports a directive into the instincts index: top-down curated content injected as
  instincts is the rejected seeds model (#8).
- **Traceability, not surveillance** (`/plexus log`): `activity/<member>.ndjson` records
  metadata of knowledge contributions only (author, action, id, revision) — never session
  text, never consumption. Written by share/directive/context-push inside the same commit.
- **Schema contract**: `sinapsis-plexus.json` carries `schema_version` with an additive-only
  policy, so external consumers (dashboards, audit engines) can build on the team repo
  without coupling to Sinapsis's release cadence.
- **Safety**: share, pull, directives and context push scrub with the same 8 secret patterns
  as `observe_v3.py` (defense in depth); imports validate id shape (path-traversal safe),
  reject ReDoS-prone triggers (same nested-quantifier guard as the passive activator) and cap
  inject length. An import ledger per team makes pull idempotent and prevents resurrection of
  instincts the operator deleted or downvoted.
- **Per-project agent context**: `/plexus context push` publishes the current project's
  `context.md` (scrubbed) keyed by git remote — the cross-machine-stable key; teammates get
  it on `/plexus pull` before their first session in that repo.

### Tests

- New `tests/test-plexus.sh` — 28 hermetic tests driving the real script against a local bare
  git remote with two sandboxed members: init/join/bootstrap, share gate + scrubbing +
  attribution + push, draft quarantine, origin provenance, idempotent pull, no-resurrection,
  personal-wins collision, permanent cap, hostile-payload rejection (ReDoS + traversal id),
  revision re-quarantine, directives (create/push/list/supersede/path-safety/never-imported),
  metadata-only activity ledger, log timeline, review queue, schema_version, leave `--purge`.
  Registered in CI.

---

## v4.6.2 (2026-06-10)

### Fixed

- **A UTF-8 BOM silently disabled the whole pipeline** (#16, reported by @juanparisma): `JSON.parse` throws on a UTF-8 BOM, and every JSON reader wrapped it in a catch that exits 0 — so an `_instincts-index.json` (or registry/rules/proposals file) saved by a Windows editor or a PowerShell redirect stopped occurrence tracking, learning, passive rules, dream, eod and the project-context bridge with no error anywhere. All readers now strip the BOM before parsing: `_instinct-activator.sh`, `_session-learner.sh` (5 read sites via a `readJson` helper), `_dream.sh`, `_eod-gather.sh`, `_passive-activator.sh`, `_project-context.sh`; `_generate-dashboard.py` reads with `encoding='utf-8-sig'`. Writers never emit a BOM, so the first atomic write after a read self-heals the file.
- **Confidence-decay demotions were discarded on the no-match path** (`_instinct-activator.sh`): the v4.4 decay pass demotes stale instincts (confirmed 60d inactive → draft, draft 90d inactive → archived) before matching, but the only index write sat after the no-match early-exit — on every tool use that matched nothing, demotions were recomputed and thrown away. In practice stale instincts never decayed unless some other instinct happened to match in the same invocation. The atomic write is now extracted into `persistIndex()` (dream-lock check and archived filtering preserved) and runs before the early-exit when decay demoted anything, logging the demotions to `_instinct.log` as the matched path already did.
- **Microsoft Store python3 shim aborted install.sh and silenced observe.sh** (aligned with #24, credit: @juanparisma): on Windows, `python3` commonly resolves to the Store alias shim — it answers `command -v` but does not execute. `install.sh` aborted under `set -e` at `PYTHON_VER=$(python3 --version)`, and `observe.sh` piped every observation into the shim, recording nothing. Both now iterate candidates (`py -3` first, the real Windows launcher) and only accept a command whose `--version` output reports `Python 3.` — any minor, deliberately not pinned to 3.9-3.13 as #24 proposed, which would silently reject Python 3.14+ (reproduced locally: 3.14.0 made observe.sh a no-op again). First word extracted with native expansion (no awk fork in the per-tool-use hot path). No behaviour change on macOS/Linux, where `py` does not exist and the loop falls through to the real `python3`.

### Tests

- New `tests/test-bom-decay-python.sh` — 12 tests: A/B BOM repros for the activator (injection + occurrence persistence), BOM-strip presence in all 6 core readers, `utf-8-sig` in the dashboard generator, a functional BOM-prefixed passive-rules run, decay demotion/archival on the no-match path, no spurious rewrites for fresh indexes, and Python detection (candidate loop asserted in both installers; functional run with a fake Store shim that answers `command -v` but fails `--version`, asserting the real interpreter is selected).

---

## v4.6.1 (2026-06-02)

### Fixed

- **Registry filename collision with skill-router / external launchers** (`_session-learner.sh`, `_eod-gather.sh`, `_generate-dashboard.py`, commands, installers): Sinapsis used `~/.claude/skills/_projects.json` as its canonical project registry, but that filename is also used by the bundled `skill-router` skill (and other launchers) with a different schema. On a machine where a launcher owns `_projects.json`, the session-learner upsert (added in v4.3.3) would append Sinapsis hash-entries into the launcher's registry on every Stop event, mixing two schemas in one file. Sinapsis now owns a dedicated `~/.claude/skills/_sinapsis-projects.json`; `_projects.json` is left entirely to skill-router. The learner re-populates the new registry automatically on Stop events (no migration needed), and `_eod-gather.sh` reads it with the legacy `homunculus/projects.json` fallback unchanged.
- Template `core/_projects.json` renamed to `core/_sinapsis-projects.json`; the installers seed/chmod/preserve the new name and no longer create or touch `_projects.json`.

### Tests

- New `tests/test-registry-isolation.sh`: asserts the learner and gather target `_sinapsis-projects.json` and that no `core/` file references the launcher's `_projects.json`. `tests/test-install-upgrade.sh` and `tests/test-eod-gather.sh` updated to the new filename.

---

## v4.6.0 (2026-06-01)

### Changed — Opus 4.8 alignment

- **Caps re-tuned for Claude Opus 4.8** (`_instinct-activator.sh`, `_session-learner.sh`): `MAX_INSTINCTS_INJECTED` 6 → 8, `TOKEN_BUDGET` 4000 → 6000, learner observation window 5000 → 8000 lines. Opus 4.8 keeps long context on-task with fewer compactions and better compaction recovery, so a richer per-turn instinct injection and a longer cross-session window for the learner carry no quality regression. The 1M context window is unchanged from Opus 4.7.
- **Prompt-cache fit improved, no code change.** Opus 4.8 lowers the minimum cacheable prompt to 1,024 tokens and adds mid-conversation `role: "system"` messages — the exact shape of Sinapsis's per-turn `systemMessage` injection — so the byte-stable instinct block introduced in v4.5 caches more readily (~90% read discount once warm).
- **Hot path remains model-free.** The activator and learner are still pure bash/node. Opus 4.8's `effort` parameter defaults to `high` in Claude Code; Sinapsis needs no change because it never calls the model directly.
- **RFC `docs/rfc-v5-adaptive-thinking.md` retargeted to `claude-opus-4-8`**: the opt-in `/analyze-session` SDK path now uses adaptive thinking with the `effort` parameter (`budget_tokens` is rejected on Opus 4.7+). Multi-agent blueprint Architect tier moved Opus 4.7 → 4.8.

### Tests

- New `tests/test-v46-opus48.sh`: asserts the re-tuned caps (`TOKEN_BUDGET` >= 6000, `MAX_INSTINCTS_INJECTED` = 8, learner window >= 8000) and that no stale `claude-opus-4-7` model ID remains in `docs/` or `core/`.
- Existing suites re-run clean, including `test-v45-opus47` (cap assertions use `>=`, so they still pass).

---

## v4.5.1 (2026-06-01)

### Fixed

- **`/eod` reported 0 projects for non-git folders** (`core/_eod-gather.sh`): `observe_v3.py` writes observations for a non-git `cwd` to the root `homunculus/observations.jsonl` with `project_id: "global"` (the `project_name` is still correct), but the gather only walked `homunculus/projects/<hash>/` and never read the root file. The writer and reader disagreed on where non-git projects live, so a full day of activity in any non-git folder surfaced as **0** in `/eod`. The gather now also reads the root file, grouping its observations by `project_name`. Reported by @NestorPVsf.
- **Cross-OS gather robustness** (`core/_eod-gather.sh`): for users syncing `observations.jsonl` between macOS and Windows (e.g. via Nextcloud), the file mixes `C:\…` and `/Users/…` paths. Node's `path.basename` is platform-specific (the POSIX build ignores `\`), so "files touched" came out mangled on the foreign OS, and the gather could try to `git` against the other machine's path. Added a `baseName()` that splits on both `/` and `\`; roots that don't exist on the current machine are skipped before any `git` call; `HOME || USERPROFILE` is resolved; and projects are merged by `project_name` so the same project from two machines collapses into one entry. Reported by @NestorPVsf.

### Tests

- New suite `tests/test-eod-gather.sh` — 8 hermetic tests (via `SINAPSIS_HOMUNCULUS` / `SINAPSIS_SKILLS` overrides) covering root-file detection, name grouping, cross-OS basename, subdir+root merge, today-only filtering, empty-dir graceful exit, the canonical `_projects.json` loader, and output shape.
- Existing suites re-run clean: `test-security` 11/11, `test-gstack-separation` 18/18.

---

## v4.5.0 (2026-04-21)

### Added — Opus 4.7 integration

- **Cache-stable instinct ordering** (`_instinct-activator.sh`): added alphabetical `id.localeCompare` tiebreaker after the priority + occurrences sort. The injected `systemMessage` prefix is now byte-stable across consecutive tool uses with the same match set, which is the prerequisite for prompt-cache hits on Opus 4.7's cached system block (~90% discount on input tokens once the cache warms).
- **`PreCompact` hook** (`core/_precompact-guard.sh`, new): fires right before Claude Code compacts the context in long-running sessions and re-invokes the session-learner so fresh observations are flushed to proposals before the transcript is rewritten. Uses `timeout 8` and a fire-and-forget pattern to never block the harness; relies on the existing advisory lock inside `_session-learner.sh` for parallel safety.
- **`settings.template.json`** now declares the new PreCompact hook (hooks 6 → 7). `install.sh` copies and chmods `_precompact-guard.sh`.
- **RFC `docs/rfc-v5-adaptive-thinking.md`**: design for an opt-in `SINAPSIS_LLM_ANALYZE=1` branch in `/analyze-session` that uses Opus 4.7 adaptive thinking via the Anthropic SDK. Not implemented in this release — ships as a design doc so the core stays fully deterministic until the approach is validated.

### Changed — Caps raised for 1M context

- `_instinct-activator.sh`: `TOKEN_BUDGET` 1500 → 4000, top-N per tool use 3 → 6 (`MAX_INSTINCTS_INJECTED`). With Opus 4.7's 1M window and prompt caching the cost of the extra injection is amortised, so we can surface more instincts per turn.
- `_session-learner.sh`: observation window 1000 → 5000 lines. Cross-session detectors (repetitions, agent patterns) now see a longer history without paging.
- `_operator-state.json` d017: Scout/Analyst blueprint switched from Haiku to Sonnet 4.6 per operator preference; Architect stays on Opus (now 4.7).

### Tests

- New suite `tests/test-v45-opus47.sh` — 11 TDD tests covering deterministic ordering (shuffled-index byte-identical output, alphabetical tiebreaker), PreCompact hook (file present, executable, wired in settings and install.sh), and raised caps.
- All existing suites re-run clean: `test-install-upgrade` 21/21, `test-dashboard` 12/12, `test-dream` 25/25, `test-gstack-separation` 18/18, `test-security` 11/11, `test-v433-hardening` 14/14.

### Rationale

Opus 4.7 brings three things Sinapsis can actually use: a stable 1-hour cache TTL that rewards byte-stable prefixes, a 1M context that removes pressure on per-turn caps, and the PreCompact hook Anthropic now ships in Claude Code. None of the "flashy" features (memory tool, context editing) are a natural fit: Sinapsis already *is* a memory system and the inject happens in a stable systemMessage. The v4.5 changes are purely about making the existing design richer and cheaper to run on top of Opus 4.7, without introducing a new LLM dependency in the hot path.

---

## v4.4.2 (2026-04-18)

### Fixed
- **`_generate-dashboard.py` crashed on `_catalog.json` dict schema** (regression from v4.4.0): `collect_skills()` iterated `cat` assuming a flat list, but the canonical catalog is `{globalSkills: [...], librarySkills: [...]}`. On any fresh v4.4.0/v4.4.1 install, the very first `/dashboard-sinapsis` run raised `AttributeError: 'str' object has no attribute 'get'`. Fix: detect dict vs list shape, concatenate `globalSkills + librarySkills`, derive real global count from the dict instead of hardcoding 5, and guard all `.get()` calls with `isinstance(s, dict)` so mixed content cannot crash. Reported in [#6](https://github.com/Luispitik/sinapsis/issues/6) by @fvayas, fixed in [#7](https://github.com/Luispitik/sinapsis/pull/7) by @NestorPVsf.

---

## v4.4.1 (2026-04-17)

### Fixed
- **`_session-learner.sh` line 277 — bash quoting bug (regression)**: the regex `["']?` inside `node -e '...'` closed the bash single-quoted string prematurely, causing every Stop event to crash with `syntax error near unexpected token (`. Pattern 4 (repetitions) and Pattern 5 (agent-patterns) never ran. Replaced literal `'` in the regex char class with the JS unicode escape `\u0027`. Added regression test (`bash -n` of all `core/*.sh`).
- **`_projects.json` was never populated**: every reader (`/projects`, `/eod`, `/instinct-status`, `/evolve`, `/backup`, `_session-learner.sh`, `_eod-gather.sh`) consulted `_projects.json` or `homunculus/projects.json` but no hook ever wrote to either. The registry stayed empty forever, so `_eod-gather.sh` could not resolve `hash → name` (showed raw 12-char hashes), `/projects` was always blank, and cross-project instinct search returned nothing. `_session-learner.sh` now upserts the canonical `~/.claude/skills/_projects.json` (array schema) on every Stop event with `{id, name, root, remote, created, last_seen}`. Project name is sourced from observation `project_name` (already written by `observe.sh`) with legacy `homunculus/projects.json` fallback. Atomic write via tmp + rename. Advisory lock file (`_projects.json.lock`) with `O_EXCL` + backoff + stale detection prevents lost updates when parallel Stop hooks fire concurrently. Idempotent.
- **`_eod-gather.sh` registry path**: switched primary source to canonical `~/.claude/skills/_projects.json` (array schema) so `/eod` resolves names correctly. Legacy `homunculus/projects.json` (map schema) kept as fallback for back-compat.
- **`_catalog.json` trailing comma**: invalid JSON. Python `json.load()` failed; Node tolerated but it is fragile. Removed the comma.
- **`_session-learner.sh` derives `root`/`remote` from observation `cwd`**: derive them via `git rev-parse --show-toplevel` + `git remote get-url origin` against the most recent observation `cwd`. POSIX `/c/foo` paths are normalized to `C:/foo` on Windows so native `git.exe` accepts them. Without this, `_projects.json` entries had blank `root`/`remote` even when upsert succeeded.
- **`observe_v3.py` now writes `cwd` into every observation**: the session-learner reads `lines[i].cwd` to run `git rev-parse`, but the hook never wrote that field — so root/remote stayed empty on fresh installs. Added `cwd` to the observation dict.

### Tests
- 4 new regression tests in `tests/test-install-upgrade.sh` (Test Group 6): bash syntax of all `core/*.sh`, `_projects.json` upsert detects `name`, idempotency on repeat run, and an end-to-end TEST 14 that pipes a real payload through `observe.sh` into a real git sandbox and verifies session-learner derives `root`/`remote` from observation `cwd` via `git rev-parse`.

---

## v4.4.0 (2026-04-16)

### Added — Observability Dashboard
- **`/dashboard-sinapsis`** command: regenerates `~/.claude/skills/_dashboard.html` — a self-contained visual dashboard with real data parsed from all pipeline files. Editorial design (Instrument Serif + warm accents on deep ink).
- **`core/_generate-dashboard.py`**: deterministic Python generator. Parses `_instincts-index.json`, `_passive-rules.json`, `_passive.log`, `_instinct-proposals.json`, `_instinct.log`, `_catalog.json`, `_projects.json`, `_operator-state.json` and `homunculus/projects/*/observations.jsonl`. Computes hero KPIs, velocity (new instincts per week), hour-of-day distribution, 21-day activity heatmap, maturation averages (add→first_triggered), funnel metrics, top-10 leaderboards and dead-instincts list. Portable: honors `$SINAPSIS_HOME` env var or falls back to `~/.claude/`.
- **`core/_dashboard-template.html`**: HTML template with `/*__SINAPSIS_DATA__*/null` injection marker. Chart.js + Google Fonts via CDN. Dark editorial theme with serif display + Inter + JetBrains Mono. Responsive.
- **12 TDD tests** (`tests/test-dashboard.sh`): portability, template substitution, metric computation, dead detection, level counting, domain aggregation, empty-state graceful handling.

### Changed
- `install.sh`: +2 files installed (`_generate-dashboard.py`, `_dashboard-template.html`)
- Test badge: 83 → 95 passing

### Rationale
Sinapsis already had `/instinct-status`, `/passive-status` and `/system-status` for terminal inspection. None gave a holistic, at-a-glance view of the learning system's health, velocity or maturation timings. The dashboard surfaces what the existing commands couldn't: **how fast you're learning, when the system fires, and where the dead weight is**.

---

## v4.3.3 (2026-04-13)

### Added — Hardening from Cortex Comparison (credit: Fernando Montero / fs-cortex v3.10)
- **`/downvote`** command: demote or archive instincts that give bad advice. Closes the feedback loop.
- **3 extra scrubbing patterns** in `observe_v3.py`: Stripe (`sk_live/sk_test`), Slack (`xoxb/xoxp`), SendGrid (`SG.*`). Now 8 patterns total (was 5).
- **Path traversal protection** in `_instinct-activator.sh`: blocks inject content containing `../`, `~/`, `/etc/`, `/proc/`.
- **Token budget cap** (`TOKEN_BUDGET=1500`): limits total chars injected per tool use. Prevents instinct loops.
- **Multi-session auto-promote**: drafts now require 5+ occurrences AND 3+ distinct sessions to promote. Tracks `sessions_seen[]` per instinct. (Was: 5+ occurrences in any number of sessions.)
- **2 new pattern detectors** in `_session-learner.sh`: repetitions (same error in 3+ sessions) and agent patterns (subagent error capture). Now 5 detectors total (was 3).
- **GitHub Actions CI**: test suite runs on push/PR across Ubuntu, macOS, Windows.
- **Pre-push hook**: `.githooks/pre-push` blocks push if any test suite fails. Enable: `git config core.hooksPath .githooks`
- **Legacy file cleanup** in `install.sh`: removes obsolete files from v3.2/v4.4 on upgrade (gstack skills, old skill names, clone.md).

### Changed
- `observe_v3.py`: 5 → 8 scrubbing patterns
- `_instinct-activator.sh`: path traversal check, budget cap, multi-session tracking
- `_session-learner.sh`: 3 → 5 pattern detectors (+ repetitions + agent patterns)
- `install.sh`: legacy cleanup step added

### Portability & Cleanup
- **`/backup [path]`** command: export full Sinapsis state to a portable folder for sync or migration between machines. Exports instincts, rules, operator state, commands, settings, CLAUDE.md + manifest.
- **`/restore [path]`** command: import Sinapsis state from a backup folder with intelligent merge (by ID, keeps local occurrence data, asks before overwriting machine-specific files).
- **`/cleanup`** command: clean homunculus directory — removes v1 legacy files (config.json, identity.json, instincts/, evolved/, exports/, root observations), orphan projects (30+ days inactive), and old archives (60+ days).

### Tests
- 14 new TDD tests (`tests/test-v433-hardening.sh`)

---

## v4.3.2 (2026-04-12)

### Removed — GStack Separation (focus: autonomous learning only)
- **`/review-army`**, **`/cso-audit`**, **`/investigate-pro`** skills moved out (engineering tools, not learning)
- **`/retro-semanal`** command moved out (reporting, not learning)
- **`_timeline-log.sh`** helper moved out (infrastructure for removed skills)
- **`__pycache__/observe_v3.cpython-314.pyc`** removed from git tracking
- All 5 components archived to `~/.claude/skills/_archived/sinapsis-gstack/` with recovery guide
- Version badges and references cleaned back to v4.3

### Kept from v4.4
- **Confidence decay** in `_instinct-activator.sh` (learning hygiene — confirmed 60d→draft, draft 90d→archived)
- **Cross-project search** in `/instinct-status --cross-project` (learning infrastructure)

---

## v4.4 (2026-04-09) — SUPERSEDED by v4.3.2

### Added — GStack Integration (garrytan/gstack) — MOVED OUT
- **Confidence decay** in `_instinct-activator.sh`: confirmed(60d inactive) -> draft, draft(90d inactive) -> archived. Permanent never decays. Credit: garrytan/gstack learnings confidence decay.
- **`/review-army`** skill: 5 specialist parallel code review (security, nextjs, supabase, performance, testing). Fix-First workflow, quality scoring. Tested live on mission-control (8.5/10, 3 findings, 0 false positives).
- **`/cso-audit`** skill: OWASP Top 10 + STRIDE + supply chain + LLM security audit. Daily mode (8/10 gate) and comprehensive mode (2/10 gate).
- **`/investigate-pro`** skill: 4-phase systematic debugging (investigate -> analyze -> hypothesize -> implement). Iron Law: no fix without confirmed root cause. Scope freeze via hooks.
- **Session timeline** (`_session-timeline.jsonl`): JSONL event log for skill usage tracking, context recovery, and retrospectives. Helper: `_timeline-log.sh`.
- **`/retro-semanal`** command: Weekly metrics across all projects — commits, skills used, instincts activated, health score trend, recommendations.
- **Cross-project instinct search** in `/instinct-status --cross-project`: search instincts across all registered projects in `_projects.json` without promoting.

### Changed
- `_catalog.json`: +3 skills (review-army, cso-audit, investigate-pro)
- `/instinct-status`: rewritten for v4.4 data model (draft/confirmed/permanent levels, occurrence tracking, cross-project search)

### Inspiration
- garrytan/gstack (23 YC engineering skills): confidence decay, review army, CSO audit, investigate, retro, session timeline, cross-project search
- Full analysis: `gstack-integration-analysis.md`

---

## v4.3.1 (2026-04-08)

### Fixed — Fersora Audit (22 bugs + 6 vulnerabilities)
- **#1-3**: install.sh preserves user data on upgrade (instincts, rules, projects, operator state)
- **#4/5A**: execFileSync replaces execSync (command injection prevention)
- **#5**: Auto-promote works correctly (drafts track occurrences without injecting)
- **#6**: Race condition fix (dream lock check before index write)
- **#7/5E**: fcntl.flock on JSONL writes
- **#8**: Token catalog corrected (9,995 → 6,915 after cleanup)
- **#9**: install.bat synced to v4.3.1
- **#10-11**: Command schemas match reality
- **#12/5C**: ReDoS protection on trigger patterns
- **#13**: Jaccard Unicode support
- **#14**: Contradiction false positive reduction
- **#15**: session-end/eod documented
- **#16**: tmpdir cleanup
- **#17**: session-learner selects by recency not hash
- **#18**: operator-state schema flag
- **#19**: KNOWLEDGE_FILE dead code removed
- **#20**: synapis → sinapsis rename
- **#22**: SINAPSIS_DEBUG mode
- **5B**: +4 secret patterns (GitHub, JWT, AWS, Stripe)
- **5D**: chmod 600 on data files
- **5F**: Inject sanitization (500 char limit + blocked patterns)

### Directory Audit Cleanup
- **Removed**: `skills/sinapsis-researcher/` (contradicts d011 — moved to on-demand)
- **Removed**: `skills/sinapsis-optimizer/` (90% duplicated by `commands/skill-audit.md`)
- **Removed**: `commands/clone.md` (100% duplicated by skill-router Section 4)
- **Removed**: `docs/synapis-technical-docs.docx` (typo + obsolete v3.2 content)
- **Fixed**: Portable find in `_session-learner.sh` (stat fallback for macOS)
- **Fixed**: fcntl Windows compatibility in `observe_v3.py` (try/except fallback)
- **Fixed**: install.bat now creates `.last-learn` marker
- **Fixed**: `_catalog.json` reduced to 3 global skills (was 5)
- **Fixed**: `.gitignore` expanded from 1 line to 12 patterns
- **Token savings**: ~4,080 tokens/session (~41% reduction)

### Tests
- 52/52 GREEN (25 dream + 11 security + 16 orchestrator)

---

## v4.3.0 (2026-04-08)

### Added
- **Dream Cycle** (`core/_dream.sh`): 5-module index hygiene system inspired by Anthropic's AutoDream
  - Module 1: Duplicate detection (Jaccard word tokens, threshold 0.80)
  - Module 2: Contradiction detection (7 opposing keyword pairs, EN+ES)
  - Module 3: Staleness scoring (fresh/stale/archive_candidate/never_activated)
  - Module 4: Trigger pattern validation (regex validity, overly broad, cross-domain overlap)
  - Module 5: Index health metrics and score (0-100)
- `/dream` command (`commands/dream.md`): Interactive dream cycle with merge/archive actions
- Auto-archive: drafts with 0 occurrences and >90 days old
- `archived` array in `_instincts-index.json` for non-destructive archival
- `_dream-report.md`: Human-readable report with executive summary and findings
- `_dream.log`: Audit trail for dream cycle actions
- Lock file (`_dream.lock`) with 1-hour stale detection

### Tests
- 25 TDD unit tests (`tests/test-dream.sh`)
- 15 E2E integration tests (`tests/test-e2e-dream.sh`)
- Total: 40 new tests (was 78, now 118)

### Improved
- Health score formula now penalizes `never_activated` instincts (-5 each)
- Empty index generates minimal report instead of silently exiting

---

## v4.2.2 — 2026-04-06

### Added
- **Multi-project /eod**: `_eod-gather.sh` deterministic script scans ALL projects worked today via homunculus, aggregates git data per project root, outputs structured JSON for consolidated EOD summary
- **`_eod-gather.sh`**: new helper script in `core/` — reads homunculus/projects/ for today's observations, cross-references projects.json for names/roots, runs git log/status/branch per project
- **`/session-end` command**: added to `commands/` — was missing from installer, users couldn't see the command
- **E2E pipeline test**: 25 tests across 6 stages (observe → learn → activate → gather → bridge → integrity) in isolated sandbox
- **12 TDD tests** for `_eod-gather.sh`: multi-project detection, stale skip, hash fallback, observation counts, schema validation

### Fixed
- **`projectName` scope bug in `_session-learner.sh`**: variable was declared inside JOB 1 try/catch but used in JOB 2 outside it → `ReferenceError` silenced by `2>/dev/null` — proposals were never written since v4.2.0. Discovered by E2E test.
- **`eod.md` single-project limitation**: now uses `_eod-gather.sh` instead of running git commands against current directory only

### Changed
- Test count: 37 → 78 (21 unit + 12 TDD + 25 E2E + 20 security)
- `install.sh` version bumped to v4.2.2, now copies `_eod-gather.sh`

---

## v4.2.1 — 2026-04-06

### Added
- **Occurrences tiebreaker** in domain dedup: when two instincts share the same domain and level, the one with more occurrences wins (inspired by fs-cortex confidence granularity — credit: Fernando Montero)
- **Domain pre-filter by project stack**: reads `context.md` to detect project tech, skips instincts from irrelevant domains before regex matching

### Changed
- Instinct activator sort: level priority preserved, occurrences used as secondary sort key
- Domain dedup: `ALWAYS_DOMAINS` set (general, git, security, operations, quality) always passes pre-filter

---

## v4.2.0 — 2026-04-05

### Added
- **3 pattern detectors** in `_session-learner.sh`: error-fix (improved), user-corrections, workflow-chains
- **Occurrence tracking** in `_instinct-activator.sh`: each instinct match increments `occurrences`, `first_triggered`, `last_triggered`
- **Auto-promote**: draft instincts with 5+ occurrences automatically promoted to confirmed
- **Atomic writes**: instinct-activator uses tmp + rename to prevent index corruption
- **Enriched proposals**: `project_name`, `sample_input`, `sample_output` in every proposal
- **13 TDD tests** covering all 3 patterns + occurrence tracking + auto-promote + atomic writes

### Changed
- Session learner window: 100 → 1000 lines (covers parallel sessions)
- Instincts index schema v4.2: added `occurrences`, `first_triggered`, `last_triggered` fields

### Fixed
- 97% of observations were silently discarded per session (100/~3000+)
- Proposals were generic — now include project context and samples

---

## v4.1.1 — 2026-04-01

### Fixed: Critical — Auto-resume between sessions was broken
`_project-context.sh` had a stray `break` (line 57) outside the conditional block. If today's EOD summary didn't exist, the loop would exit immediately without checking yesterday's file. The flagship auto-resume feature was completely non-functional.

### Fixed: `/analyze-session` command didn't exist
README, CHANGELOG, install output, and multiple SKILL.md files all referenced `/analyze-session`, but the actual command file was named `analyze-observations.md`. Renamed to `analyze-session.md` and rewrote content for v4.1 proposals workflow.

### Fixed: `install.bat` parity with `install.sh`
- Added `_daily-summaries` directory creation (missing — `/eod` would fail on Windows)
- Added Python 3 detection with warning (was silent)
- Fixed Node.js path quoting using `process.argv` (paths with spaces would break)

### Fixed: `.last-learn` marker created at install time
`_session-learner.sh` uses `find -newer .last-learn` which would fail noisily on first run. Installer now creates the marker file.

### Fixed: 11 files referenced non-existent v3.2 paths
- `_instincts.json` → `_instincts-index.json` (8 files)
- `_observations.json` → `~/.claude/homunculus/projects/{hash}/observations.jsonl` (3 files)
- Fixed `skills/homunculus` path → `homunculus` (no `skills/` prefix)
- Fixed `lastSeen` field reference → v4.1 schema fields

### Fixed: Version and naming inconsistencies
- Bumped version 3.2 → 4.1 in `_catalog.json`, `_projects.json`, `_operator-state.template.json`
- Renamed "Synapis" → "Sinapsis" across all `.md` and `.json` files
- Skill Router header: v3.0 → v4.1
- `settings.template.json`: corrected hook count 7/Stop(2) → 6/Stop(1)

### Updated: Command and skill files to v4.1 data model
- Rewrote `synapis-instincts/SKILL.md`: replaced 0.0-1.0 lifecycle model with draft/confirmed/permanent
- Rewrote `instinct-status.md`: dashboard now shows levels and domain dedup
- Rewrote `promote.md`: promotes confirmed → permanent (not project → global)
- Updated `evolve.md`: filter criteria uses levels, not confidence decimals

### Improved: Error detection in `observe_v3.py`
Replaced substring matching (`"error" in output`) with word-boundary regex patterns. Prevents false positives like "0 errors found" from being flagged as errors.

### Improved: Removed orphan directory creation in `observe_v3.py`
Removed creation of unused directories (`instincts/personal`, `evolved/skills`, etc.) per project. Only creates the project directory itself.

---

## v4.1 — 2026-03-31

### New: Closed Learning Pipeline
The observation→learning→injection pipeline is now fully connected end-to-end:

1. `observe.sh` (PreToolUse + PostToolUse): writes `observations.jsonl` per project
2. `_session-learner.sh` (Stop hook): reads observations, detects error patterns, writes `_instinct-proposals.json`
3. `/analyze-session`: review proposals, accept → add to `_instincts-index.json`
4. `_instinct-activator.sh` (PreToolUse): reads index, injects matched instincts as `systemMessage`

### New: Project Context Bridge
`_session-learner.sh` writes `context.md` per project at session end (project name, last session date, files touched, gotcha count hint).
`_project-context.sh` reads it at the first PreToolUse of the next session — fires once per session via session_id flag.

### New: Domain Deduplication in Instinct Activator
`_instinct-activator.sh` groups instincts by domain. One instinct per domain is injected, max 3 total.
Prevents multiple contradictory instincts from the same area firing simultaneously.
Priority: `permanent` > `confirmed`.

### New: 3-Level Confidence Model
Replaces the 0.0–1.0 decimal scoring with 3 explicit levels:
- `draft`: proposed by session-learner, not injected. Review with `/analyze-session`.
- `confirmed`: validated by user. Injected silently when trigger matches.
- `permanent`: explicitly promoted via `/promote`. Highest priority in domain dedup.

### New: `_instincts-index.json`
Central instinct registry. Replaces scattered YAML files.
Fields: `id`, `domain`, `level`, `trigger_pattern`, `inject`, `origin`, `added`.
Origin values: `manual` (curated) or `learned` (from session-learner).

### New: `core/settings.template.json`
Documents the 6-hook architecture with comments. Copy/merge into `~/.claude/settings.json`.

### Changed: Honest Observation Model
v3.2 claimed Sinapsis "observes passively in real-time." This was inaccurate.
v4.1 is explicit: hooks are deterministic bash scripts. Claude does NOT analyze observations during a session.
Analysis happens at Stop (deterministic) or on demand (`/analyze-session`).

### Changed: Token Architecture
- 2 global skills always active (was 5): skill-router + sinapsis-learning
- Instinct injection: ~50–200 tokens per matching tool use (only matched instincts)
- Passive rules: ~20–80 tokens per matching tool use (only matched rules)
- Full `_instincts-index.json` and `_passive-rules.json` read by hooks, not loaded into LLM context

### Fixed: Noise in Proposals
v3.2 session-learner generated 80+ noise proposals per day (workflow sequences, tool preferences).
v4.1 only detects `error_resolution` patterns (error → same tool success within 5 events), with dedup per tool per day.

---

## v3.2 — Initial public release

Skills on Demand architecture. Passive rules, skill router, operator state, 5 global always-on skills.
