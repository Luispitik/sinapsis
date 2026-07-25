#!/usr/bin/env python3
"""Sinapsis Observer v3 - Single-invocation Python script.
Appends one JSONL observation per tool use to homunculus/projects/{hash}/observations.jsonl
Scrubs secrets from input/output before writing.
Sets is_error=True only on structural harness failures or hard failure markers
in execution (Bash) output — never on keywords inside read file content (v4.8.1)."""

import json, sys, os, re, hashlib, stat
try:
    import fcntl
except ImportError:
    fcntl = None  # Windows: fallback to no-lock (single-user safe)
from datetime import datetime, timezone


def main():
    hook_phase = sys.argv[1] if len(sys.argv) > 1 else "post"

    raw = sys.stdin.read().strip()
    if not raw:
        return

    try:
        data = json.loads(raw)
    except Exception:
        return

    # Skip subagents
    if data.get("agent_id"):
        return

    config_dir = os.path.expanduser("~/.claude/homunculus")
    projects_dir = os.path.join(config_dir, "projects")

    if os.path.exists(os.path.join(config_dir, "disabled")):
        return

    entrypoint = os.environ.get("CLAUDE_CODE_ENTRYPOINT", "cli")
    if entrypoint not in ("cli", "sdk", "api", "claude-desktop", ""):
        return
    if os.environ.get("ECC_HOOK_PROFILE") == "minimal":
        return
    if os.environ.get("ECC_SKIP_OBSERVE") == "1":
        return

    # Detect project via git
    cwd = data.get("cwd", "")
    project_id = "global"
    project_name = "global"
    project_dir = config_dir

    if cwd and os.path.isdir(cwd):
        project_name = os.path.basename(cwd)
        import subprocess
        try:
            root = subprocess.check_output(
                ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
                stderr=subprocess.DEVNULL, text=True
            ).strip()
            if root:
                project_name = os.path.basename(root)
                try:
                    remote = subprocess.check_output(
                        ["git", "-C", root, "remote", "get-url", "origin"],
                        stderr=subprocess.DEVNULL, text=True
                    ).strip()
                except Exception:
                    remote = ""
                hash_input = remote or root
                project_id = hashlib.sha256(hash_input.encode()).hexdigest()[:12]
                project_dir = os.path.join(projects_dir, project_id)

                # Create project directory (archive dir created on demand)
                os.makedirs(project_dir, exist_ok=True)
        except Exception:
            pass

    # Parse hook event
    event = "tool_start" if hook_phase == "pre" else "tool_complete"
    tool_name = data.get("tool_name", data.get("tool", "unknown"))
    tool_input = data.get("tool_input", data.get("input", {}))
    tool_output = data.get("tool_response", data.get("tool_output", data.get("output", "")))
    session_id = data.get("session_id", "unknown")

    input_str = json.dumps(tool_input)[:5000] if isinstance(tool_input, dict) else str(tool_input)[:5000]
    output_str = json.dumps(tool_output)[:10000] if isinstance(tool_output, dict) else str(tool_output)[:10000]

    # Scrub secrets — 8 patterns (v4.3.3: added Stripe, Slack, SendGrid)
    SECRET_RE = re.compile(
        r"(?i)(api[_-]?key|token|secret|password|authorization|credentials?|auth)"
        r"([\"'\s:=]+)"
        r"([A-Za-z]+\s+)?"
        r"([A-Za-z0-9_\-/.+=]{8,})"
    )
    JWT_RE = re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")
    GITHUB_RE = re.compile(r"gh[ps]_[A-Za-z0-9]{36,}")
    AWS_RE = re.compile(r"AKIA[A-Z0-9]{16}")
    PEM_RE = re.compile(r"-----BEGIN [A-Z ]+-----[\s\S]*?-----END [A-Z ]+-----")
    # v4.3.3: 3 extra patterns (inspired by Cortex v3.10 — 12 patterns)
    STRIPE_RE = re.compile(r"(?:sk_live|sk_test|rk_live|rk_test)_[A-Za-z0-9]{20,}")
    SLACK_RE = re.compile(r"xox[bpras]-[A-Za-z0-9\-]{10,}")
    SENDGRID_RE = re.compile(r"SG\.[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{20,}")

    def scrub(val):
        if val is None:
            return None
        s = str(val)
        s = SECRET_RE.sub(
            lambda m: m.group(1) + m.group(2) + (m.group(3) or "") + "[REDACTED]",
            s
        )
        s = JWT_RE.sub("[JWT_REDACTED]", s)
        s = GITHUB_RE.sub("[GITHUB_TOKEN_REDACTED]", s)
        s = AWS_RE.sub("[AWS_KEY_REDACTED]", s)
        s = PEM_RE.sub("[PEM_REDACTED]", s)
        s = STRIPE_RE.sub("[STRIPE_KEY_REDACTED]", s)
        s = SLACK_RE.sub("[SLACK_TOKEN_REDACTED]", s)
        s = SENDGRID_RE.sub("[SENDGRID_KEY_REDACTED]", s)
        return s

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    observation = {
        "timestamp": now,
        "event": event,
        "tool": tool_name,
        "session": session_id,
        "project_id": project_id,
        "project_name": project_name,
        "cwd": cwd,
    }

    if event == "tool_start":
        observation["input"] = scrub(input_str)
        # Extract file_path for Edit/Write (used by session-learner for correction detection)
        if tool_name in ("Edit", "Write") and isinstance(tool_input, dict):
            fp = tool_input.get("file_path", "")
            if fp:
                observation["file_path"] = fp

    if event == "tool_complete" and tool_output is not None:
        observation["output"] = scrub(output_str)
        # Also capture input for tool_complete (enables full context analysis)
        observation["input"] = scrub(input_str)
        # Flag errors — session-learner uses this to detect error→resolution patterns.
        # v4.8.1 fix: substring matching on the whole output flagged successful Reads
        # whose CONTENT mentioned "error" (e.g. source code with `throw new Error`).
        # Now: (a) structural error signals from the harness for every tool,
        # (b) hard failure markers only for execution tools (Bash), whose output is
        # a run result, not arbitrary file content.
        is_error = False
        err_line = ""

        # (a) Structural: harness-reported failure shapes (any tool)
        if isinstance(tool_output, dict) and (
            tool_output.get("is_error") or tool_output.get("error")
        ):
            is_error = True
            err_line = str(tool_output.get("error") or tool_output.get("is_error"))[:500]
        elif "tool_use_error" in output_str:
            is_error = True
        elif re.match(r'^\s*"?(Error|InputValidationError)\b', output_str):
            # Failed calls return an error string; successful content tools return
            # JSON like {"type": "text", "file": ...} — start-of-output only.
            is_error = True

        # (b) Hard markers for execution output (Bash/PowerShell) — never scanned over
        # content-bearing tools at full length, whose output is data, not a verdict.
        hard_markers = [
            r"Permission denied", r"command not found", r"No such file or directory",
            r"Traceback \(most recent call last\)", r"\bfatal: ", r"npm ERR!",
            r"\bEPERM\b", r"\bENOENT\b", r"\bEACCES\b", r"UnicodeEncodeError",
            r"exit code [1-9]", r"syntax error", r"was blocked",
        ]
        if not is_error and tool_name in ("Bash", "PowerShell"):
            for pat in hard_markers:
                if re.search(pat, output_str):
                    is_error = True
                    break

        # (c) v4.9.0: closes the gap where a genuine Edit/Read failure was flagged by
        # nobody — (a) only catches harness-shaped errors and (b) is execution-only.
        #
        # What separates a failure from a success here is SHAPE, not wording. A non-Bash
        # tool that fails returns a bare verdict string ("File does not exist.", "Error:
        # String to replace not found"); one that succeeds returns a payload, which
        # json.dumps renders starting with { or [. Scanning a payload for marker words is
        # precisely the bug this whole fix exists to kill — a Read of source code that
        # mentions EPERM is not an EPERM. So: bare strings only, and short enough to be a
        # verdict rather than prose.
        stripped = output_str.lstrip()
        looks_like_payload = stripped.startswith("{") or stripped.startswith("[")
        if (not is_error and tool_name not in ("Bash", "PowerShell")
                and not looks_like_payload and len(output_str) < 500):
            for pat in hard_markers + [r"String to replace not found",
                                       r"File does not exist",
                                       r"has not been read yet"]:
                if re.search(pat, output_str):
                    is_error = True
                    break

        if is_error:
            observation["is_error"] = True
            if not err_line:
                # Extract first line carrying a failure marker (best effort)
                fail_re = re.compile(
                    r"(tool_use_error|Permission denied|command not found|No such file"
                    r"|Traceback|fatal: |npm ERR!|EPERM|ENOENT|EACCES|UnicodeEncodeError"
                    r"|exit code [1-9]|syntax error|was blocked|^\s*\"?Error)"
                )
                for line in output_str.split('\n'):
                    if fail_re.search(line):
                        err_line = line.strip()[:500]
                        break
            if err_line:
                observation["err_msg"] = scrub(err_line)

    obs_file = os.path.join(project_dir, "observations.jsonl")

    # Auto-archive if file exceeds 10MB (with lock to prevent concurrent rotation)
    if os.path.exists(obs_file):
        try:
            if os.path.getsize(obs_file) >= 10 * 1024 * 1024:
                lock_path = obs_file + ".lock"
                try:
                    lock_fd = open(lock_path, "w")
                    if fcntl:
                        fcntl.flock(lock_fd.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                    if os.path.exists(obs_file) and os.path.getsize(obs_file) >= 10 * 1024 * 1024:
                        archive_dir = os.path.join(project_dir, "observations.archive")
                        os.makedirs(archive_dir, exist_ok=True)
                        archive_name = "observations-" + datetime.now().strftime("%Y%m%d-%H%M%S") + ".jsonl"
                        os.rename(obs_file, os.path.join(archive_dir, archive_name))
                    if fcntl:
                        fcntl.flock(lock_fd.fileno(), fcntl.LOCK_UN)
                    lock_fd.close()
                except (IOError, OSError):
                    pass
        except Exception:
            pass

    try:
        with open(obs_file, "a", encoding="utf-8") as f:
            if fcntl:
                fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            f.write(json.dumps(observation) + "\n")
            if fcntl:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
        # v4.3.1: restrictive permissions on data files (#5D)
        try:
            os.chmod(obs_file, stat.S_IRUSR | stat.S_IWUSR)
        except Exception:
            pass
    except Exception:
        pass


if __name__ == "__main__":
    main()
