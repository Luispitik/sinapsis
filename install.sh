#!/bin/bash
# ============================================================
#  Sinapsis v4.10 — Installer for macOS / Linux
#  Skills on Demand for Claude Code
#  https://github.com/Luispitik/sinapsis
# ============================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD='\033[1m'

# Paths
CLAUDE_HOME="$HOME/.claude"
SKILLS_DIR="$CLAUDE_HOME/skills"
LIBRARY_DIR="$SKILLS_DIR/_library"
ARCHIVED_DIR="$SKILLS_DIR/_archived"
COMMANDS_DIR="$CLAUDE_HOME/commands"
HOMUNCULUS_DIR="$CLAUDE_HOME/homunculus/projects"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo -e "${PURPLE}${BOLD}============================================================${NC}"
echo -e "${PURPLE}${BOLD}  Sinapsis v4.10 — Skills on Demand for Claude Code${NC}"
echo -e "${PURPLE}${BOLD}  The system that learns and adapts to you${NC}"
echo -e "${PURPLE}${BOLD}============================================================${NC}"
echo ""

# Detect upgrade vs fresh install
UPGRADING=false
if [ -f "$SKILLS_DIR/_catalog.json" ]; then
    UPGRADING=true
fi

# ── Step 1: Check prerequisites ──
echo -e "${BLUE}[1/8]${NC} Checking prerequisites..."

if ! command -v claude &> /dev/null; then
    echo -e "${YELLOW}  ! Claude Code not found in PATH${NC}"
    echo -e "${YELLOW}    Install it first: https://claude.ai/code${NC}"
    echo -e "${YELLOW}    Continuing anyway (files will be installed)...${NC}"
else
    echo -e "${GREEN}  OK${NC} Claude Code detected"
fi

if ! command -v node &> /dev/null; then
    echo -e "${RED}  ERROR${NC} Node.js not found."
    echo -e "${RED}         Sinapsis hooks require Node.js.${NC}"
    echo -e "${RED}         Install it: https://nodejs.org${NC}"
    exit 1
else
    NODE_VER=$(node --version)
    echo -e "${GREEN}  OK${NC} Node.js $NODE_VER detected"
fi

# Windows-safe Python detection: validate --version before accepting a command
# (aligned with PR #24). On Windows the `python3` alias is the Microsoft Store
# shim — it answers `command -v` but does NOT execute (prints a notice and exits
# non-zero). With `set -e`, the old `PYTHON_VER=$(python3 --version)` aborted the
# WHOLE install. Try `py -3` first (the real launcher), and only accept a command
# whose --version actually reports Python 3.x. The `|| true` guards set -e.
# The check is "Python 3." (any minor): the shim never prints that, and pinning
# minors (as PR #24 did with 3.9-3.13) silently breaks on Python 3.14+.
PYTHON_CMD=""
for candidate in "py -3" python3 python python3.13 python3.12 python3.11; do
    cmd=${candidate%% *}
    if command -v "$cmd" >/dev/null 2>&1; then
        if $candidate --version 2>&1 | grep -qE "Python 3\."; then
            PYTHON_CMD="$candidate"
            break
        fi
    fi
done
if [ -z "$PYTHON_CMD" ]; then
    echo -e "${YELLOW}  ! Python 3 not found — observation hooks will be disabled${NC}"
    echo -e "${YELLOW}    Install it: https://python.org (optional but recommended)${NC}"
else
    PYTHON_VER=$($PYTHON_CMD --version 2>&1 || true)
    echo -e "${GREEN}  OK${NC} $PYTHON_VER detected"
fi

if [ -d "$CLAUDE_HOME" ]; then
    echo -e "${GREEN}  OK${NC} ~/.claude/ exists"
else
    echo -e "${CYAN}  ->  Creating ~/.claude/${NC}"
    mkdir -p "$CLAUDE_HOME"
fi

# ── Step 2: Backup if upgrading ──
echo -e "${BLUE}[2/8]${NC} Checking for existing installation..."

if $UPGRADING; then
    echo -e "${YELLOW}  ! Existing installation detected — creating backup${NC}"
    BACKUP_DIR="$CLAUDE_HOME/_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp -r "$SKILLS_DIR" "$BACKUP_DIR/skills_backup" 2>/dev/null || true
    cp -r "$COMMANDS_DIR" "$BACKUP_DIR/commands_backup" 2>/dev/null || true
    echo -e "${GREEN}  OK${NC} Backup saved to $BACKUP_DIR"
else
    echo -e "${GREEN}  OK${NC} Fresh install"
fi

# ── Step 3: Create directory structure ──
echo -e "${BLUE}[3/8]${NC} Creating directory structure..."

mkdir -p "$SKILLS_DIR"
mkdir -p "$LIBRARY_DIR"
mkdir -p "$ARCHIVED_DIR"
mkdir -p "$COMMANDS_DIR"
mkdir -p "$CLAUDE_HOME/projects"
mkdir -p "$HOMUNCULUS_DIR"
mkdir -p "$SKILLS_DIR/_daily-summaries"
touch "$CLAUDE_HOME/homunculus/.last-learn" 2>/dev/null || true

echo -e "${GREEN}  OK${NC} Directories created"

# ── Step 4: Copy core config files ──
echo -e "${BLUE}[4/8]${NC} Installing core config files..."

# Catalog always updates (system file, not user data)
cp "$SCRIPT_DIR/core/_catalog.json" "$SKILLS_DIR/_catalog.json"

# User data files: preserve on upgrade, only create if missing
# Bug #1-#3 fix: unconditional cp destroyed learned instincts, custom rules, and project registry
FORCE_UPDATE=false
for arg in "$@"; do
    [ "$arg" = "--force-update" ] && FORCE_UPDATE=true
done

for datafile in _passive-rules.json _sinapsis-projects.json _instincts-index.json; do
    if $FORCE_UPDATE || [ ! -f "$SKILLS_DIR/$datafile" ]; then
        cp "$SCRIPT_DIR/core/$datafile" "$SKILLS_DIR/$datafile"
        if $FORCE_UPDATE; then
            echo -e "${YELLOW}  !  $datafile force-updated (--force-update)${NC}"
        fi
    else
        echo -e "${CYAN}  ->  $datafile preserved (user data)${NC}"
    fi
done

# Operator state: only create if not exists (preserve user data)
if [ ! -f "$SKILLS_DIR/_operator-state.json" ]; then
    cp "$SCRIPT_DIR/core/_operator-state.template.json" "$SKILLS_DIR/_operator-state.json"
    echo -e "${GREEN}  OK${NC} Operator state created (empty, ready for onboarding)"
else
    echo -e "${CYAN}  ->  Existing operator state preserved${NC}"
fi

# CLAUDE.md: only create if not exists
if [ ! -f "$CLAUDE_HOME/CLAUDE.md" ]; then
    cp "$SCRIPT_DIR/core/CLAUDE.md.template" "$CLAUDE_HOME/CLAUDE.md"
    echo -e "${GREEN}  OK${NC} CLAUDE.md created"
else
    echo -e "${YELLOW}  ! CLAUDE.md already exists — not overwritten${NC}"
    echo -e "${YELLOW}    Check core/CLAUDE.md.template for updates${NC}"
fi

# Restrictive permissions on data files (#5D)
chmod 600 "$SKILLS_DIR/_instincts-index.json" "$SKILLS_DIR/_passive-rules.json" "$SKILLS_DIR/_sinapsis-projects.json" "$SKILLS_DIR/_operator-state.json" 2>/dev/null || true

echo -e "${GREEN}  OK${NC} Core config files installed"

# ── Step 5: Copy hook scripts ──
echo -e "${BLUE}[5/8]${NC} Installing hook scripts..."

cp "$SCRIPT_DIR/core/_passive-activator.sh" "$SKILLS_DIR/_passive-activator.sh"
cp "$SCRIPT_DIR/core/_instinct-activator.sh" "$SKILLS_DIR/_instinct-activator.sh"
cp "$SCRIPT_DIR/core/_session-learner.sh" "$SKILLS_DIR/_session-learner.sh"
cp "$SCRIPT_DIR/core/_project-context.sh" "$SKILLS_DIR/_project-context.sh"
cp "$SCRIPT_DIR/core/_eod-gather.sh" "$SKILLS_DIR/_eod-gather.sh"
cp "$SCRIPT_DIR/core/_dream.sh" "$SKILLS_DIR/_dream.sh"
cp "$SCRIPT_DIR/core/_precompact-guard.sh" "$SKILLS_DIR/_precompact-guard.sh"
cp "$SCRIPT_DIR/core/_generate-dashboard.py" "$SKILLS_DIR/_generate-dashboard.py"
cp "$SCRIPT_DIR/core/_dashboard-template.html" "$SKILLS_DIR/_dashboard-template.html"

chmod +x "$SKILLS_DIR/_passive-activator.sh"
chmod +x "$SKILLS_DIR/_instinct-activator.sh"
chmod +x "$SKILLS_DIR/_session-learner.sh"
chmod +x "$SKILLS_DIR/_project-context.sh"
chmod +x "$SKILLS_DIR/_eod-gather.sh"
chmod +x "$SKILLS_DIR/_dream.sh"
chmod +x "$SKILLS_DIR/_precompact-guard.sh"
chmod +x "$SKILLS_DIR/_generate-dashboard.py" 2>/dev/null || true

# NOTE (v4.8.0): the team layer (Plexus) lives in the private team edition.
# This installer neither installs NOR removes _plexus-sync.sh / plexus.md —
# they may belong to a team-edition install layered on top of this one.

echo -e "${GREEN}  OK${NC} 6 hook scripts + dream cycle + dashboard generator installed"

# ── Step 5b: Legacy file cleanup (v4.3.3; v4.8.1 archives instead of deleting) ──
# Audit finding #2: one of these hardcoded names can be a LIVE user directory
# (e.g. a still-active synapis-learning install). Never rm -rf — move aside.
LEGACY_CLEANED=0
LEGACY_ARCHIVE="$ARCHIVED_DIR/legacy-$(date +%Y%m%d_%H%M%S)"
# v4.4 gstack files (removed in v4.3.2) + v3.2 leftovers
for legacy in "$SKILLS_DIR/_timeline-log.sh" "$SKILLS_DIR/_session-timeline.jsonl" \
  "$SKILLS_DIR/review-army" "$SKILLS_DIR/cso-audit" "$SKILLS_DIR/investigate-pro" \
  "$SKILLS_DIR/sinapsis-optimizer" "$SKILLS_DIR/sinapsis-researcher" \
  "$SKILLS_DIR/synapis-learning" "$COMMANDS_DIR/clone.md" "$COMMANDS_DIR/retro-semanal.md"; do
  if [ -e "$legacy" ]; then
    mkdir -p "$LEGACY_ARCHIVE"
    # Count only real moves — mv can fail (e.g. open handles on Windows/Git Bash)
    # and reporting an archive that did not happen is worse than none.
    if mv "$legacy" "$LEGACY_ARCHIVE/" 2>/dev/null; then
      LEGACY_CLEANED=$((LEGACY_CLEANED + 1))
    else
      echo -e "${YELLOW}  !  Could not archive $legacy (in use?) — left in place${NC}"
    fi
  fi
done
if [ "$LEGACY_CLEANED" -gt 0 ]; then
  echo -e "${YELLOW}  !  Archived $LEGACY_CLEANED legacy files to $LEGACY_ARCHIVE${NC}"
fi

# ── Step 6: Configure settings.json ──
echo -e "${BLUE}[6/8]${NC} Configuring hooks in settings.json..."

SETTINGS_FILE="$CLAUDE_HOME/settings.json"

# v4.8.1 (audit finding #1): the old behaviour registered NOTHING when the file
# already existed ("merge hooks manually") — a ghost install with the pipeline
# inert. _merge-hooks.js creates the file when missing and otherwise deep-merges:
# only Sinapsis hooks whose command is not yet registered are appended, every
# existing entry is preserved, and a malformed settings.json is left untouched.
if node "$SCRIPT_DIR/core/_merge-hooks.js" "$SCRIPT_DIR/core/settings.template.json" "$SETTINGS_FILE"; then
    echo -e "${GREEN}  OK${NC} Sinapsis hooks wired into settings.json (existing entries preserved)"
else
    echo -e "${YELLOW}  ! Could not update settings.json — left untouched${NC}"
    echo -e "${YELLOW}    Review core/settings.template.json and merge hooks manually${NC}"
fi

# ── Step 7: Copy skills ──
echo -e "${BLUE}[7/8]${NC} Installing skills..."

skill_count=0
for skill_dir in "$SCRIPT_DIR/skills"/*/; do
    skill_name=$(basename "$skill_dir")
    target="$SKILLS_DIR/$skill_name"
    mkdir -p "$target"
    cp -r "$skill_dir". "$target/" 2>/dev/null || true
    skill_count=$((skill_count + 1))
    echo -e "${GREEN}  OK${NC} $skill_name"
done

# Make hook scripts executable
find "$SKILLS_DIR" -name "*.sh" -path "*/hooks/*" -exec chmod +x {} \; 2>/dev/null || true

# ── Step 8: Copy slash commands ──
echo -e "${BLUE}[8/8]${NC} Installing slash commands..."

cmd_count=0
for cmd_file in "$SCRIPT_DIR/commands"/*.md; do
    if [ -f "$cmd_file" ]; then
        cp "$cmd_file" "$COMMANDS_DIR/"
        cmd_count=$((cmd_count + 1))
    fi
done
echo -e "${GREEN}  OK${NC} $cmd_count commands installed"

# ── Done ──
echo ""
echo -e "${GREEN}${BOLD}============================================================${NC}"
if $UPGRADING; then
    echo -e "${GREEN}${BOLD}  Sinapsis v4.10 upgrade complete!${NC}"
else
    echo -e "${GREEN}${BOLD}  Sinapsis v4.10 installed!${NC}"
fi
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo ""
echo -e "  ${BOLD}What was installed:${NC}"
echo -e "  - 3 global skills (always active: sinapsis-learning + sinapsis-instincts + skill-router)"
echo -e "  - $skill_count total skills"
echo -e "  - $cmd_count slash commands (/evolve, /system-status, /eod...)"
echo -e "  - 6 hook scripts + dream cycle (passive-activator, instinct-activator, session-learner, project-context, eod-gather, precompact-guard, dream)"
echo -e "  - Core config: catalog, passive rules, instincts index, operator state"
echo ""
echo -e "  ${BOLD}Next step:${NC}"
echo -e "  1. Open Claude Code in any project folder"
echo -e "  2. Sinapsis will guide you through first-time setup"
echo -e "  3. Choose your mode: Skills on Demand, manual, or vanilla"
echo ""
echo -e "  ${BOLD}Useful commands:${NC}"
echo -e "  /system-status    — System dashboard"
echo -e "  /evolve           — Evolve patterns into skills"
echo -e "  /analyze-session  — Review learned proposals"
echo -e "  /passive-status   — Active passive rules"
echo -e "  /eod              — Save context for tomorrow"
echo ""
if $UPGRADING; then
    echo -e "${CYAN}  Upgrade note: your operator state and CLAUDE.md were preserved.${NC}"
    echo -e "${CYAN}  Backup saved to: $BACKUP_DIR${NC}"
    echo ""
fi
echo -e "${PURPLE}  Sinapsis learns from you. Every session feeds the next.${NC}"
echo ""
