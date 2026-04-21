---
name: session-handoff
preamble-tier: 1
version: 0.1.0
description: |
  Generates role-aware, structured handoff prompts between agent sessions.
  Captures git state (branch, HEAD SHA, worktree dirty flag), active plans,
  the latest checkpoint, and project context into a self-contained prompt a
  fresh agent session can act on without re-discovery. Supports message
  types (brief, assign, review, report, handoff) and target roles (coord,
  impl, qa, reviewer, general).
  Use when asked to "handoff", "session handoff", "fresh context", "new
  session", "brief the coordinator", "create a playbook prompt", "pass
  this to another session", "hand off to {role}", or when the user is
  preparing to spawn a new agent for a distinct phase or role.
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - AskUserQuestion
---

# /session-handoff — Inter-Agent Handoff Generator

You are a **structured message author** for multi-session agent workflows.
Your job is to capture the current working state and package it as a
role-aware, self-contained prompt the receiving session can execute
without re-discovery.

**HARD GATE:** Do NOT modify project source code, plan files, CLAUDE.md,
checkpoint files, or any repository content. This skill only reads state
and writes a handoff artifact to `~/.claude/handoffs/{slug}/` (artifact
writing is implemented in Unit 4).

---

## Quick Start

```bash
git clone <repo> ~/.claude/skills/session-handoff
# Then in any project:
/session-handoff                    # default: handoff for general role
/session-handoff brief coord        # briefing for coordinator
/session-handoff assign qa -- test the booking flow
```

The short prompt is copied to your clipboard; the full artifact is
written to `~/.claude/handoffs/{slug}/`. Paste the short prompt into
any fresh session (same machine or not) to continue the work.

---

## Prerequisites

- **Claude Code CLI.** Skill is invoked as a slash command.
- **git repository** *(optional).* Branch / HEAD SHA / worktree status
  are captured when a git repo is present; absence emits a warning and
  the skill continues.
- **`docs/plans/` directory** *(optional).* Active plans are discovered
  via `status: active` in YAML frontmatter; absence emits a warning and
  the handoff omits the Plan reference section.
- **Write access to `~/.claude/handoffs/`.** Required. The directory is
  created on first run; a permission failure emits a canonical warning
  and the short prompt still prints so nothing is lost.

Degrades gracefully on every optional source: you always get a short
prompt, even if git is missing, no plan exists, and the clipboard tool
is absent.

---

## Pre-resolved context

Claude Code resolves the inline commands below at skill-load time, giving
you ground-truth branch/SHA/slug before Phase 1 runs.

- **Repo slug (pre-resolved):** !`eval "$(~/.claude/skills/gstack/bin/gstack-slug 2>/dev/null)" && echo "${SLUG:-unknown}"`
- **Branch (pre-resolved):** !`git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"`
- **HEAD SHA (pre-resolved):** !`git rev-parse --short HEAD 2>/dev/null || echo "unknown"`
- **Worktree (pre-resolved):** !`if [ -n "$(git status --porcelain 2>/dev/null)" ]; then echo "dirty"; else echo "clean"; fi`

If any value above is empty or still contains the literal backtick command
string, resolution failed. Treat it as unknown and make sure Phase 1 emits
the corresponding `[warning: ...]` entry so the receiving agent knows the
state is missing rather than silently absent.

---

## Preamble (run first)

```bash
# Session + slug (sets SLUG, REPO when gstack-slug is available)
mkdir -p ~/.gstack/sessions
touch ~/.gstack/sessions/"$PPID"
eval "$(~/.claude/skills/gstack/bin/gstack-slug 2>/dev/null)" 2>/dev/null || true
SLUG="${SLUG:-unknown}"

# Values reused by Phase 1 and the final timeline event
_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
_SESSION_ID="$$-$(date +%s)"
_TEL_START=$(date +%s)
echo "BRANCH: $_BRANCH"
echo "SLUG: $SLUG"
echo "SESSION_ID: $_SESSION_ID"

# Detect orchestrator-spawned session (e.g., OpenClaw). Spawned sessions
# should auto-pick sensible defaults instead of calling AskUserQuestion.
if [ -n "$OPENCLAW_SESSION" ]; then
  echo "SPAWNED_SESSION: true"
else
  echo "SPAWNED_SESSION: false"
fi

# Timeline: skill started. Local-only, never transmitted anywhere.
~/.claude/skills/gstack/bin/gstack-timeline-log \
  '{"skill":"session-handoff","event":"started","branch":"'"$_BRANCH"'","session":"'"$_SESSION_ID"'"}' \
  2>/dev/null &
```

If the preamble prints `SPAWNED_SESSION: true`, do NOT use AskUserQuestion
for any interactive step in later phases. Auto-pick the recommended option
and surface the choice in the output artifact.

If `gstack-slug` is missing (for example on a machine without gstack
installed), `SLUG` falls back to `unknown`. The checkpoint lookup in
Phase 1c will then skip silently with a warning; this is expected behavior.

---

## Auto-cleanup (run before Phase 1)

Handoff artifacts older than 14 days are deleted at the start of every
invocation, BEFORE Phase 1 gathers state. Keeping this tight to skill
start (rather than after output) means a failed run still cleans up
history from prior successful runs, and a stale directory never grows
past the 14-day window.

```bash
CLEANUP_DIR="$HOME/.claude/handoffs/$SLUG"
if [ -d "$CLEANUP_DIR" ]; then
  if ! find "$CLEANUP_DIR" -maxdepth 1 -name "*.md" -type f -mtime +14 -delete 2>/dev/null; then
    echo "[warning: handoff cleanup -- find could not delete stale artifacts under $CLEANUP_DIR -- stale artifacts not removed]"
  fi
fi
```

Design notes:

- **First-run is a no-op.** On the very first invocation the artifact
  directory does not exist. The `[ -d "$CLEANUP_DIR" ]` guard short-
  circuits silently; no warning is emitted because nothing was missing.
  Phase 5 creates the directory when it writes the first artifact.
- **Warning shape.** Cleanup errors use the canonical 3-segment warning
  shape Phase 1 / Phase 2 / Phase 3 established:
  `[warning: handoff cleanup -- {reason} -- stale artifacts not removed]`.
  The warning lands in the same `warnings:` block as all other
  warnings and renders in both output tiers (Phase 4).
- **Slug fallback.** When `SLUG=unknown` (gstack-slug absent), cleanup
  targets `~/.claude/handoffs/unknown/`. That directory accumulates
  handoffs from every project that could not resolve a slug and is
  still subject to the 14-day window — which is the whole point.
- **Cleanup never blocks the skill.** A cleanup failure emits a warning
  and keeps running. The receiving agent treats the stale-artifact
  risk as cosmetic; the current handoff is still valid.

---

## Phase 1: Gather state

Each data source below is gathered independently. A single-source failure
emits a structured warning and does NOT block the remaining sources. The
order of sources matches the source precedence model (see below): git ->
plans -> checkpoint -> CLAUDE.md -> conversation.

### Warning format

Every missing or unavailable source produces a warning line in this exact
shape:

```
[warning: {source} not available -- {reason} -- {what was skipped}]
```

- `{source}`: the short name of the data source (for example `git`,
  `active plan`, `checkpoint`, `CLAUDE.md`, `conversation context`).
- `{reason}`: a one-phrase explanation of *why* the source was missing
  (for example `git command not on PATH`, `docs/plans/ contains no
  *-plan.md with status: active`, `~/.gstack/projects/$SLUG/checkpoints/
  does not exist`).
- `{what was skipped}`: the field or section that would have appeared
  in the artifact (for example `branch/HEAD SHA/status context omitted`,
  `plan reference omitted`, `checkpoint pointer omitted`).

Do NOT silently omit a missing source. Silent omission kills trust. Every
warning is emitted into a `warnings:` section of the final artifact so
the receiving agent can see exactly which sources were unavailable.

### 1a) Git state (branch, HEAD SHA, worktree dirty, status, log, diff)

```bash
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  echo "=== BRANCH ==="
  git rev-parse --abbrev-ref HEAD 2>/dev/null

  echo "=== HEAD SHA ==="
  git rev-parse --short HEAD 2>/dev/null

  echo "=== WORKTREE ==="
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    echo "dirty"
  else
    echo "clean"
  fi

  echo "=== STATUS ==="
  git status --short 2>/dev/null

  echo "=== RECENT LOG ==="
  git log --oneline -5 2>/dev/null

  echo "=== DIFF STAT ==="
  git diff --stat 2>/dev/null
else
  echo "[warning: git not available -- git command missing from PATH or CWD is not a git repository -- branch/HEAD SHA/status/log/diff context omitted]"
fi
```

All six git fields must appear in the final artifact when git is available:

1. Branch name (`git rev-parse --abbrev-ref HEAD`)
2. HEAD SHA, short form (`git rev-parse --short HEAD`)
3. Worktree dirty flag (`dirty` if `git status --porcelain` has any output,
   else `clean`)
4. Short status (`git status --short`)
5. Recent 5 commits (`git log --oneline -5`)
6. Diff stat against index (`git diff --stat`)

Parallel sessions on the same worktree can diverge between invocations.
Branch name alone does not identify exact working state, which is why the
HEAD SHA and worktree dirty flag are mandatory — they let the receiving
agent verify it is looking at the same snapshot.

### 1b) Active plans

Plans under `docs/plans/` are authoritative for in-flight work. Match only
YAML frontmatter lines that start with `status: active` — grep anchors to
line start so prose mentions of "status: active" do not false-positive.

```bash
if [ -d docs/plans ]; then
  ACTIVE_PLANS=$(find docs/plans -name "*-plan.md" -type f \
    -exec grep -l "^status: active" {} \; 2>/dev/null)
  if [ -n "$ACTIVE_PLANS" ]; then
    echo "=== ACTIVE PLANS ==="
    echo "$ACTIVE_PLANS"
  else
    echo "[warning: active plan not found -- docs/plans/ has no *-plan.md with status: active in YAML frontmatter -- plan reference omitted]"
  fi
else
  echo "[warning: plan directory not present -- docs/plans/ does not exist in repo -- plan reference omitted]"
fi
```

If multiple plans match, list ALL of them with their full repo-relative
paths. Do not try to pick "the most recent" — git mtime is unreliable
across clones and branches, and there can legitimately be several active
plans (phased work). The receiving agent decides which one applies.

### 1c) Latest checkpoint

The checkpoint skill writes to `~/.gstack/projects/{slug}/checkpoints/`.
Record the path to the most recent checkpoint if one exists; do not inline
its contents (the artifact stays small, and the receiving agent can read
the file when on the same machine).

```bash
CHECKPOINT_DIR="$HOME/.gstack/projects/$SLUG/checkpoints"
if [ -d "$CHECKPOINT_DIR" ]; then
  LATEST_CP=$(find "$CHECKPOINT_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null \
    | xargs ls -t 2>/dev/null | head -1)
  if [ -n "$LATEST_CP" ]; then
    echo "=== LATEST CHECKPOINT ==="
    echo "$LATEST_CP"
  else
    echo "[warning: checkpoint not found -- $CHECKPOINT_DIR exists but contains no *.md files -- checkpoint pointer omitted]"
  fi
else
  echo "[warning: checkpoint not found -- $CHECKPOINT_DIR does not exist -- checkpoint pointer omitted]"
fi
```

Checkpoint discovery scans across branches (a checkpoint saved on one
branch can be resumed from another — this matches the `/checkpoint resume`
behavior). The single newest checkpoint is sufficient for handoff
orientation; the receiving agent can run `/checkpoint list` if it wants
more.

### 1d) CLAUDE.md presence

```bash
if [ -f CLAUDE.md ]; then
  echo "CLAUDE.md: found (path: ./CLAUDE.md)"
else
  echo "[warning: CLAUDE.md not found -- no CLAUDE.md in repo root -- project guidance reference omitted]"
fi
```

Unit 1 records presence only. Unit 3 (sanitization) determines which parts,
if any, can be inlined into the artifact. Unit 4 (output) decides whether
the full artifact references the path or pulls excerpts.

### 1e) Conversation synthesis (lossy, mark as inferred)

Conversation context is the least reliable source. Mark every line derived
from conversation with `[inferred from session]` so the receiving agent
knows the confidence level. Do this synthesis yourself, using the
conversation you just had with the user as input:

> Review this conversation. List key decisions made in this session, each
> prefixed with `[inferred from session]`. List open questions or
> unresolved items. If you cannot recall specific decisions, write
> `[no session decisions captured -- conversation context unavailable]`.
> Do not fabricate decisions that were not discussed.

Output format (emit both sections even when empty — an empty section
signals "looked and found nothing," which is different from "did not
look"):

```
=== SESSION DECISIONS ===
- [inferred from session] {decision one, one per line}
- [inferred from session] {decision two}
(or, if nothing to report)
[no session decisions captured -- conversation context unavailable]

=== OPEN QUESTIONS ===
- [inferred from session] {open question one}
- [inferred from session] {open question two}
(or, if nothing to report)
[no open questions captured -- conversation context unavailable]
```

Do not fabricate. If the session did not discuss a decision, do not
invent one to fill space. Over-reporting is worse than under-reporting —
the receiving agent will act on these lines.

---

## Phase 2: Parse command

Determine four values from the user's invocation line:

- `MSG_TYPE` — one of `handoff` (default), `brief`, `assign`, `review`,
  `report`
- `TARGET_ROLE` — one of `general` (default), `coord`, `impl`, `qa`,
  `reviewer`
- `PHASE_OVERRIDE` — optional string used only by the `impl` role
  preamble's `{phase}` substitution (see Phase 4 step 4a)
- `INSTRUCTIONS` — free-form user text, everything after `--` (may be
  empty)

### Grammar

```
/session-handoff [message-type] [target-role] [--phase="..."] [-- additional instructions]
```

Both positional slots are optional. `--phase="..."` is optional and may
appear anywhere on the line before `--`. Everything after the first
literal `--` token (bordered by whitespace) is the free-form
instructions string.

### Known tokens (exact literal match — no aliases, no prefix matching)

- **Message types:** `handoff`, `brief`, `assign`, `review`, `report`
- **Target roles:** `coord`, `impl`, `qa`, `reviewer`, `general`

`review` is ALWAYS a message type. `reviewer` is ALWAYS a target role.
The tokens are distinct strings; the parser compares tokens literally
and NEVER shortens `reviewer` to `review` or treats `review` as a prefix
of `reviewer`. Alias collision is prevented by construction.

### Parsing algorithm

Find the user's `/session-handoff ...` invocation line in the
conversation (the message that triggered this skill) and apply these
steps in order. Initialize `MSG_TYPE`, `TARGET_ROLE`, `PHASE_OVERRIDE`,
and `INSTRUCTIONS` as unset.

1. **Split on `--`.** Take the first occurrence of `--` (surrounded by
   whitespace, or at end-of-line) as the delimiter. Everything after it
   becomes `INSTRUCTIONS` — trim leading and trailing whitespace, but
   preserve internal formatting verbatim. Everything before becomes the
   pre-delimiter segment.

2. **Optional `--phase="..."` flag — pre-delimiter only.** Scan the
   pre-delimiter segment (NEVER the INSTRUCTIONS segment after `--`)
   for `--phase=<value>` tokens. A literal `--phase=...` that appears
   inside the free-form instructions is user text, not a flag, and
   must pass through to `INSTRUCTIONS` unchanged.

   Token shape:
   - Quoted value: `--phase="<value>"`. The value starts immediately
     after the `=`, opens with a literal `"`, and terminates at the
     next literal `"`. Backslash escapes are NOT supported; the value
     itself cannot contain a literal `"` character. Multi-word and
     Unicode content (em-dashes, parens) are supported.
   - Unquoted value: `--phase=<value>`. The value starts immediately
     after the `=` and terminates at the next whitespace character
     or end-of-segment. No spaces.

   Extraction rules:
   - When a `--phase=<value>` token is found, set `PHASE_OVERRIDE` to
     `<value>` (quotes stripped, content preserved verbatim). Remove
     the entire `--phase=<value>` token from the pre-delimiter
     segment (collapsing adjacent whitespace) before step 3 runs so
     the positional parser does not see it.
   - The flag may appear anywhere in the pre-delimiter segment —
     before, between, or after the two positional slots.

   Empty and malformed values:
   - `--phase=""` (empty quoted) → treated as not-set, no warning.
   - `--phase=` immediately followed by whitespace or end-of-segment
     (unquoted empty) → treated as not-set, no warning.
   - `--phase` without an `=` sign → NOT recognized as this flag. The
     token falls through to step 3 as an unknown positional token
     and produces the standard unknown-first-token warning.

   Multiple occurrences (first non-empty wins):
   - If multiple `--phase=` tokens appear in the pre-delimiter segment,
     scan left-to-right and use the value of the first token whose
     value is non-empty. Earlier empty tokens are skipped silently.
   - For every `--phase=` token AFTER the winner (regardless of its
     value), emit one warning:
     `[warning: command argument not available -- duplicate --phase= token "<value>" -- first non-empty occurrence wins, extras ignored]`.
   - If every `--phase=` token has an empty value, `PHASE_OVERRIDE`
     stays unset and no duplicate warnings are emitted.

   Role-applicability warning:
   - If `PHASE_OVERRIDE` ends up set AND the resolved `TARGET_ROLE`
     (after step 3) is anything other than `impl`, emit:
     `[warning: command argument not available -- --phase= is only consumed by the impl role, got role "<role>" -- phase override ignored for this handoff]`.
   - `PHASE_OVERRIDE` remains stored (future roles may consume it),
     but Phase 4 step 4a only substitutes it for `impl`.

   Examples:
   - `--phase="Unit 3 — file-protocol scaffolding"` →
     `PHASE_OVERRIDE="Unit 3 — file-protocol scaffolding"`.
   - `--phase=Unit-3` → `PHASE_OVERRIDE="Unit-3"`.
   - `--phase=""` → `PHASE_OVERRIDE` unset.
   - `--phase= --phase="Unit 4"` → `PHASE_OVERRIDE="Unit 4"` (first
     empty skipped; second non-empty wins).
   - `/session-handoff qa --phase="Unit 4"` → `PHASE_OVERRIDE="Unit 4"`
     but emits the role-applicability warning because role is `qa`.
3. **First positional token.**
   - If it matches a known message type exactly, set `MSG_TYPE` to that
     value and pop it.
   - Else if it matches a known role exactly, set `MSG_TYPE` to
     `handoff`, set `TARGET_ROLE` to that role, and pop the token.
     **Backward compatibility:** `/session-handoff qa` →
     `handoff` + `qa`; `/session-handoff impl` → `handoff` + `impl`.
   - Else emit the unknown-first-token warning (see below), default
     `MSG_TYPE` to `handoff`, default `TARGET_ROLE` to `general`, and
     pop the unknown token.
4. **Second positional token (only if `TARGET_ROLE` is still unset).**
   - If it matches a known role exactly, set `TARGET_ROLE` to it and pop
     the token.
   - Else emit the unknown-role warning, default `TARGET_ROLE` to
     `general`, and pop the token.
5. **Extras.** Emit one extra-argument warning per remaining positional
   token and discard them.
6. **Defaults.** If `MSG_TYPE` is still unset, set it to `handoff`. If
   `TARGET_ROLE` is still unset, set it to `general`. `INSTRUCTIONS` may
   remain empty.

The parser never calls `AskUserQuestion`. Every ambiguity resolves to a
warning plus a default. This keeps behavior uniform for interactive
sessions and for sessions where the preamble printed
`SPAWNED_SESSION: true`.

### Warnings

All Phase 2 warnings use the canonical Phase 1 shape:

```
[warning: {source} not available -- {reason} -- {what was skipped}]
```

with `{source}` = `command argument`. The receiving agent parses these
uniformly alongside Phase 1 warnings. Exact templates:

- **Unknown first token:**
  `[warning: command argument not available -- "<token>" is neither a known message type nor a known target role -- defaulting to message type "handoff" and role "general"]`
- **Unknown role in the role slot:**
  `[warning: command argument not available -- "<token>" is not a known target role -- defaulting to role "general"]`
- **Extra positional argument:**
  `[warning: command argument not available -- "<token>" is an unexpected extra argument -- ignored]`

Phase 2 warnings are emitted into the same `warnings:` section of the
final artifact that Phase 1 uses. Unit 4 surfaces them in both the short
prompt and the full artifact.

### Result

After parsing, hold these four values for downstream phases:

```
MSG_TYPE=<resolved>          # handoff | brief | assign | review | report
TARGET_ROLE=<resolved>       # coord | impl | qa | reviewer | general
PHASE_OVERRIDE=<resolved>    # optional string, used only by impl preamble
INSTRUCTIONS=<resolved>      # free-form string, possibly empty
```

### Load template fragments

Read `references/message-templates.md`. The file is organized into three
composable sections:

- `## Base Template` — the canonical section list every assembled message
  draws from.
- `## Role Preambles` — five role-specific opening paragraphs (one each
  for `coord`, `impl`, `qa`, `reviewer`, `general`).
- `## Message Type Overrides` — five section-ordering and emphasis rules
  (one each for `handoff`, `brief`, `assign`, `review`, `report`).

Phase 2 only identifies WHICH preamble and WHICH override apply, based
on `TARGET_ROLE` and `MSG_TYPE`. Phase 2 does NOT substitute Phase 1
state into the template — that is Unit 4's assembly phase. The reason
for the split is simple: command parsing is stable and cheap; assembly
depends on sanitization (Unit 3) and artifact output (Unit 4) being
wired up first.

### Worked examples (all 9 plan test scenarios)

| Invocation | `MSG_TYPE` | `TARGET_ROLE` | `PHASE_OVERRIDE` | `INSTRUCTIONS` | Warnings |
|---|---|---|---|---|---|
| `/session-handoff` | `handoff` | `general` | — | `` | — |
| `/session-handoff brief coord` | `brief` | `coord` | — | `` | — |
| `/session-handoff assign qa -- test the booking flow` | `assign` | `qa` | — | `test the booking flow` | — |
| `/session-handoff report coord -- phase 0 done` | `report` | `coord` | — | `phase 0 done` | — |
| `/session-handoff impl` | `handoff` | `impl` | — | `` | — (backward-compat) |
| `/session-handoff unknown-thing` | `handoff` | `general` | — | `` | unknown-first-token |
| `/session-handoff review` | `review` | `general` | — | `` | — |
| `/session-handoff handoff reviewer -- check auth` | `handoff` | `reviewer` | — | `check auth` | — |
| `/session-handoff review reviewer -- check the PR` | `review` | `reviewer` | — | `check the PR` | — |
| `/session-handoff impl --phase="Unit 3 — file-protocol scaffolding" -- start Unit 3 of foo plugin` | `handoff` | `impl` | `Unit 3 — file-protocol scaffolding` | `start Unit 3 of foo plugin` | — |
| `/session-handoff --phase=Unit-3 impl` | `handoff` | `impl` | `Unit-3` | `` | — (flag before positional slots) |

---

## Phase 3: Sanitize

Phase 3 defines the sanitization contract and loads the regex library.
The library is loaded EARLY (here, right after command parsing) so it is
available when Unit 4 assembly completes and is ready to emit output.
The actual sanitization pass runs LATE — after Phase 4 has assembled
both the short prompt and the full artifact but BEFORE Phase 5 writes
anything to disk, clipboard, or stdout. In one sentence:

> Load the pattern library now (Phase 3). Apply it to every assembled
> output string later (between Phase 4 assembly and Phase 5 output).
> Nothing leaves this skill unsanitized.

### Load the pattern library

Read `references/sanitization-patterns.md`. It is organized into four
labelled categories:

1. **API key shapes** — prefixes like `sk-`, `key-`, `token-`, and
   long base64 blocks (> 20 characters of `[A-Za-z0-9+/_-]` with optional
   trailing `=` padding).
2. **Env-var values** — lines of the form `NAME=VALUE` where `NAME`
   contains any of `KEY`, `SECRET`, `TOKEN`, `PASSWORD`, `CREDENTIAL`
   (case-insensitive). The entire `VALUE` side is replaced.
3. **Known service patterns** — Supabase (`sb_`), Vercel tokens
   (`vercel_`, deployment webhook URLs), AWS access keys (`AKIA...`),
   Anthropic (`sk-ant-...`), OpenAI (`sk-proj-...` / `sk-...`),
   GitHub (`ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`).
4. **URLs with embedded credentials** — anything matching
   `scheme://user:pass@host...`. The `user:pass` segment is replaced
   with `REDACTED:REDACTED`; the host and path are preserved.

The file documents each category with the literal regex, a labelled
example input, and the expected replacement. Phase 3 treats that file
as the source of truth for what counts as a secret.

### Verify the library loaded cleanly

Before applying any pattern, confirm every regex in
`references/sanitization-patterns.md` compiles. If the file is missing,
unreadable, or any regex in it is malformed, SKIP the sanitization pass,
emit the canonical Unit 1 warning shape, and STILL produce the output.
Better a warned, unredacted output than silent data loss or silent
leakage — the warning tells the receiving agent exactly what to check.

Exact warning template (uses the Phase 1 / Phase 2 3-segment contract):

```
[warning: sanitization skipped -- malformed pattern in references/sanitization-patterns.md -- output emitted without redaction]
```

Alternate reasons use the same shape:

```
[warning: sanitization skipped -- references/sanitization-patterns.md not found -- output emitted without redaction]
[warning: sanitization skipped -- references/sanitization-patterns.md unreadable -- output emitted without redaction]
```

Warnings are appended to the same `warnings:` block Phase 1 and Phase 2
populate; Unit 4 renders them in both output tiers.

### Apply the library (runs between Phase 4 assembly and Phase 5 output)

For every assembled output string (short prompt AND full artifact),
iterate through the four categories and replace each match with one of
two replacement templates:

| Source of the match is known | Template |
|---|---|
| Yes — the secret came from an identifiable source file (for example, `CLAUDE.md`, `docs/plans/foo-plan.md`, a checkpoint path) | `[REDACTED -- see {original_filepath}]` |
| No — the secret came from conversation context, synthesized prose, or an unattributable line | `[REDACTED -- potential secret removed]` |

The filepath in the first template is the file the secret was READ FROM,
not a file that contains instructions about the secret. Paths themselves
are NOT secrets; keep them verbatim. The receiving agent uses the path
to fetch the real value locally if needed.

When Unit 4 assembles output, it tracks provenance per-section (for
example, the CLAUDE.md inlined preview carries `origin=CLAUDE.md`, the
checkpoint pointer carries `origin={checkpoint_path}`, and conversation
synthesis carries no origin). Phase 3 reads that provenance when
choosing the replacement template. If provenance is missing or
ambiguous, fall back to `[REDACTED -- potential secret removed]`.

### Over-redaction is preferred to under-redaction

A false positive wastes a few characters and produces a visible
`[REDACTED -- ...]` marker the receiving agent can ask about. A false
negative leaks a credential. Always err toward redacting.

**Acceptable false-positive cases:**

- Short git commit SHAs (7–40 hex chars) that visually resemble an API
  key. The base64-block pattern may catch them. This is acceptable —
  the receiving agent can re-read the git state for real SHAs.
- Random-looking identifiers (UUIDs, build hashes, trace IDs) that
  happen to fit a secret shape. Same treatment.
- Arbitrary base64 content (diff stats, small attached files) that
  exceeds 20 characters. Acceptable.

Do NOT narrow the patterns to avoid these false positives. Narrower
patterns leak secrets. Wider patterns produce extra `[REDACTED -- ...]`
markers, which are cheap and visible.

### What sanitization must NOT touch

- **Phase 2 warning quoted tokens.** Phase 2 warnings contain strings
  like `"<token>"` (e.g. `"unknown-thing"`, `"qa"`). These are user
  input echoed back for diagnosis — NOT secrets. The sanitizer targets
  known secret SHAPES (prefixes like `sk-`, `AKIA`; base64 blocks;
  `NAME=VALUE` pairs with secret-like names). Quoted strings in warning
  lines do not match any of those shapes and must pass through
  unchanged. Do NOT add "anything inside quotes" as a pattern.
- **File paths.** Paths are not secrets. Preserve them verbatim in
  replacement templates (`[REDACTED -- see docs/foo.md]`) and in any
  section that references a file location.
- **Warning strings themselves.** The canonical warning template
  `[warning: ... -- ... -- ...]` carries diagnostic metadata. Do not
  redact inside warning lines. (Secrets should never appear in warning
  text in the first place — Phase 1 emits warnings describing what was
  missing, not its contents.)
- **Template fragments loaded from `references/message-templates.md`**
  at template-selection time. Those fragments are static, committed
  content that Unit 2 loads verbatim. Sanitization applies to the
  FINAL assembled output, not to template source files.
- **Pre-resolved context values** (slug, branch, HEAD SHA, worktree
  flag) from the top of this file. They are not secrets; short SHAs
  that fit the base64 pattern are covered by the acceptable-false-
  positive rules above.

### Silent on a clean pass

If zero matches are found, Phase 3 emits NO warnings. Silence means
"sanitizer ran, nothing flagged." The malformed-pattern warning is the
ONLY signal the sanitizer itself emits; match-level redactions appear
inline in the output as `[REDACTED -- ...]` markers.

---

## Phase 4: Assemble

Phase 4 is the composition step: merge the parsed command (`MSG_TYPE`,
`TARGET_ROLE`, `INSTRUCTIONS`) with the gathered state (Phase 1a–1e) and
the template fragments from `references/message-templates.md` into two
strings:

1. `SHORT_PROMPT` — length budget varies by `MSG_TYPE` (see step 4g
   for per-type soft/hard caps). Self-contained: works as a standalone
   prompt in a fresh session on any machine, even one that cannot read
   the full artifact on disk.
2. `FULL_ARTIFACT` — complete structured document with YAML frontmatter
   and every applicable Base Template section, written to disk in
   Phase 5.

Unit 2's composition algorithm at the end of
`references/message-templates.md` is authoritative for which sections
appear and in what order. Phase 4 extends that algorithm with
provenance tagging (for Phase 3 sanitization), short-prompt truncation
priority, frontmatter assembly, and artifact path derivation.

### 4a) Substitute state into the role preamble

Look up `ROLE_PREAMBLES[TARGET_ROLE]` from
`references/message-templates.md`. For the `impl` preamble only,
substitute two placeholders. `PHASE_OVERRIDE` (Phase 2 step 0) takes
precedence over plan-derived values.

- `{phase}` — precedence order:
  1. If `PHASE_OVERRIDE` was set in Phase 2 (via `--phase="..."`), use
     it verbatim. This is the caller's explicit choice and is the
     correct path for single-unit handoffs inside a multi-unit plan.
  2. Else use the `title:` field in the first active plan's YAML
     frontmatter from Phase 1b.
  3. Else fall back to the first `# ` heading in the active plan.
  4. Else (no override, no active plan) substitute
     `the current phase (no active plan — see warnings)`.
- `{plan_path}` — the repo-relative path of the first active plan. If
  Phase 1b found multiple plans, substitute the first path and append
  the sentence `Multiple active plans — see Plan reference for the
  full list.` to the end of the preamble. If no plan was found,
  substitute `(no active plan — see warnings)`.

Roles other than `impl` have no substitutions. `PHASE_OVERRIDE` is
silently ignored for non-`impl` roles (it is not an error to pass
`--phase=` for `coord`, `qa`, `reviewer`, or `general` — future roles
may use it, and silent-ignore keeps the flag future-proof).

**Why the override exists.** A multi-unit plan's `title:` frontmatter
usually names the whole plan, not the specific unit being worked on.
When handing off a single unit inside a larger plan, the receiving
agent wants `Unit 3 — file-protocol scaffolding` in the preamble's
first sentence, not `feat: Agent Orchestration Plugin for Claude
Code`. Callers pass the unit-specific name via `--phase=`.

### 4b) Render each Base Template section with provenance

For each section name in the chosen section list (step 4d), pull
content from Phase 1 state per the rules in the Base Template. Tag
each rendered section with an internal `origin=...` marker that
Phase 3 reads when choosing a replacement template:

| Section | `origin` tag |
|---|---|
| Role preamble | none (static text + plan-derived substitutions) |
| Project context (branch/SHA/worktree) | `origin=git` |
| Project context (checkpoint pointer) | `origin={checkpoint_path}` |
| Project context (CLAUDE.md pointer) | `origin=CLAUDE.md` |
| Status summary | `origin=git+plan` |
| Git details | `origin=git` |
| Plan reference | `origin={plan_path}` per line |
| Decisions | none — conversation-sourced |
| Open questions | none — conversation-sourced |
| Task description | `origin=instructions` when seeded from `INSTRUCTIONS`; `origin={plan_path}` when derived from a plan |
| Scope / Acceptance criteria / Resources | `origin={plan_path}` when seeded from a plan; none for the generic placeholder |
| Artifact to review | `origin=instructions` when seeded from `INSTRUCTIONS`; `origin=git` when derived from the current branch diff |
| Review criteria | none when using the generic checklist |
| Specific questions | `origin=instructions` for appended `INSTRUCTIONS` |
| Findings summary / Pass/Fail / Evidence / Recommendations | `origin=instructions` for `INSTRUCTIONS`-sourced content; none otherwise |
| Instructions (user-provided) | `origin=instructions` |
| Warnings | none — diagnostic metadata |
| Artifact pointer | none |

Provenance markers are INTERNAL metadata. They are consumed by Phase 3
and MUST be stripped (step 4i) before any content reaches stdout,
clipboard, or disk.

### 4c) Always-rendered sections

Decisions, Open questions, and Warnings render even when empty, using
the canonical empty-state placeholders from Phase 1 and the Base
Template. This preserves the Unit 1 invariant: "looked and found
nothing" is different from "we forgot to look." Every other section is
omitted when empty.

### 4d) Select sections per message-type override

Look up `TYPE_OVERRIDES[MSG_TYPE]` from
`references/message-templates.md`. Compose:

```
short_sections = [preamble] + override.primary
                 + ["Warnings", "Artifact pointer"]
full_sections  = [preamble] + override.primary + override.secondary
                 + ["Warnings", "Artifact pointer"]
```

`handoff` and `brief` include `Instructions (user-provided)` in their
primary list, so it appears in the short prompt. `assign`, `review`,
and `report` absorb `INSTRUCTIONS` into type-specific sections (step
4e) — they have no dedicated Instructions section.

### 4e) Thread `INSTRUCTIONS`

Per Unit 2's override contract:

| Type | Where `INSTRUCTIONS` lands |
|---|---|
| `handoff` | Dedicated `## Instructions` section, verbatim. Section omitted when `INSTRUCTIONS` is empty. |
| `brief` | Dedicated `## Instructions` section, verbatim. Section omitted when `INSTRUCTIONS` is empty. |
| `assign` | Seeds `Task description` verbatim. Empty `INSTRUCTIONS` renders `[to be defined by assigning agent]` so the worker sees the gap. |
| `review` | Placed under `Specific questions` as "Additional reviewer instructions:". If the string names an artifact (e.g. `check PR #123`, `review file/path.ts`), ALSO seeds `Artifact to review` with the named identifier. |
| `report` | `INSTRUCTIONS` ≤ 80 chars seeds `Findings summary` headline verbatim. Longer strings (or surplus text after the headline slot) append to `Recommendations`. Empty `INSTRUCTIONS` leaves Findings summary to be synthesized from Evidence. |

### 4f) Assemble the short prompt

Render `short_sections` in order. The short prompt is plain markdown —
no YAML frontmatter, H2 headings only. The end of the prompt is
always the artifact-pointer line, rendered exactly:

```
If on the same machine, read `{artifact_path}` for additional detail.
```

`{artifact_path}` is the path computed in step 4h. The line is load-
bearing: it gives the receiving agent a cross-machine fallback when
the short prompt is paste-transferred.

### 4g) Short-prompt truncation priority

Per-type soft/hard caps, keyed by `MSG_TYPE`:

| `MSG_TYPE` | Soft cap | Hard cap |
|---|---|---|
| `handoff` | 2000 | 2500 |
| `brief` | 2000 | 2500 |
| `assign` | 3500 | 4500 |
| `review` | 2500 | 3500 |
| `report` | 3500 | 4500 |

`handoff` and `brief` are terse status tiers — the short prompt is a
skim; detail lives in the full artifact. `assign` and `report` are
deliverable tiers — the short prompt IS the detailed task brief
(multi-scenario acceptance criteria) or findings brief (evidence +
recommendations), so it gets a larger budget. `review` sits between
them. Soft caps are the targeted body length; hard caps are the
ceiling at which truncation priority kicks in.

If the rendered short prompt exceeds the type's hard cap, reduce
content in this order:

1. **Cut Plan reference detail first.** Keep the path(s) only; drop
   any inlined plan excerpts, title lines, or multi-plan notes.
2. **Cut Status details next.** Keep the one-line status summary; drop
   the worked details (worktree dirty rationale, "multiple active
   plans — see Plan reference" note, etc.).
3. **Cut Decisions / Open questions body next.** Keep the canonical
   empty-state placeholder or a single-line summary; drop the bullet
   list.

Always keep, in every truncation state:

- Role preamble, including `{phase}` / `{plan_path}` substitutions.
- Project context: branch and HEAD SHA at minimum.
- The `INSTRUCTIONS` section (or the type-specific section where
  `INSTRUCTIONS` has been threaded).
- Warnings section.
- The artifact-pointer line.

If after all three cuts the prompt still exceeds the type's hard cap,
stop cutting and emit the prompt as-is. The receiving agent can read
the full artifact on disk. Do NOT silently truncate mid-sentence.

**Worked case 1 (assign, within soft cap, no truncation).** A 3200-
char `/session-handoff assign qa` short prompt carrying a 4-scenario
acceptance checklist and resource pointers sits under `assign`'s 3500
soft cap — emit as-is. The same 3200 chars under the old universal
2500 cap would have tripped truncation even though every byte is
load-bearing task detail (Plan reference and Status are already in
the secondary-only list for `assign` per step 4d, so there's nothing
below the Task description to cut). Per-type caps resolve this.

**Worked case 2 (assign, exceeds hard cap, truncation + emit-as-is).**
A 4700-char `/session-handoff assign impl` short prompt (large
INSTRUCTIONS seeded into Task description, plus auto-derived Scope,
Acceptance criteria, and Resources from a linked plan) exceeds the
4500 hard cap. Tier 1 (cut Plan reference detail) and tier 2 (cut
Status details) are no-ops because both sections are secondary-only
for `assign` per step 4d. Tier 3 (cut Decisions / Open questions
body) is also a no-op for the same reason. Every cut tier hits a
section that is not in `assign`'s primary list, so the prompt body
does not shrink. Per the rule above, stop cutting and emit as-is —
do NOT silently truncate the Task description mid-sentence. The
full artifact on disk carries the complete detail; the receiving
agent reads it via the artifact-pointer line.

**Worked case 3 (review, exceeds hard cap, tier 3 fires directly).**
A 3600-char `/session-handoff review reviewer -- check PR #42` short
prompt (large Artifact-to-review block + extensive Review criteria +
appended Specific questions) exceeds the 3500 `review` hard cap.
Tier 1 (Plan reference) and tier 2 (Status details) are both no-ops
because `review`'s primary sections are Artifact to review → Review
criteria → Specific questions (Plan reference and Status are
secondary per step 4d). Tier 3 (cut Decisions / Open questions
body) also has no body for `review` because those sections are not
in its primary list. Result: no cuts apply, emit as-is.

**Worked case 4 (report, between soft and hard, emit as-is).** A
3800-char `/session-handoff report coord` short prompt carrying a
PASS/FAIL verdict, an Evidence block quoting CI log excerpts, and
detailed Recommendations sits between `report`'s 3500 soft cap and
4500 hard cap. No truncation fires — soft caps are the targeted
length, not the enforcement threshold. Emit as-is. This is the
transition-zone behavior: soft-cap overages are diagnostic (the
prompt is longer than ideal) but not corrective (no cuts applied).

Summary: across all five `MSG_TYPE` values, the three truncation
tiers cut from sections that are either primary for `handoff` / `brief`
(where truncation works as designed) or secondary-only for `assign`
/ `review` / `report` (where tiers are no-ops by construction). This
is the load-bearing invariant of the per-type caps: raising the cap
for deliverable types works because there is nothing below the
load-bearing content to cut.

### 4h) Assemble the full artifact

Compose YAML frontmatter in this exact field order:

```yaml
---
schema_version: 1
type: <MSG_TYPE>
role: <TARGET_ROLE>
branch: <branch or "unknown">
sha: <short HEAD SHA or "unknown">
timestamp: <ISO 8601, e.g. 2026-04-18T15:04:05Z>
source_session_id: <_SESSION_ID from preamble>
warnings:
  - <warning 1>
  - <warning 2>
---
```

If no warnings were emitted, render `warnings: []` so downstream
tooling always sees the key. Every warning from Phase 1, the auto-
cleanup step, Phase 2, and Phase 3 appears in this block. The visible
`## Warnings` section in the body renders the same list; keeping the
frontmatter copy makes future tooling that parses handoffs (V2) cheap.

Immediately after frontmatter, render `full_sections` in order using
H2 headings (`## Project context`, `## Status summary`, `## Plan
reference`, etc.). Use the section names from the Base Template
verbatim for heading text.

Compute `artifact_path`:

```
$HOME/.claude/handoffs/$SLUG/{TIMESTAMP}-{MSG_TYPE}-{TARGET_ROLE}.md
```

- `$SLUG` is the preamble-resolved slug. If `SLUG=unknown` (gstack-
  slug absent), the artifact lives under `~/.claude/handoffs/unknown/`.
  This matches the Unit 1 fallback contract.
- `{TIMESTAMP}` is `YYYYMMDD-HHMMSS` local time, matching the
  checkpoint skill's naming convention so handoffs and checkpoints
  sort consistently.
- `{MSG_TYPE}` and `{TARGET_ROLE}` are the parsed tokens (never
  `unknown` — parser always resolves them).

Example path:
`~/.claude/handoffs/claude-skills/20260418-150405-handoff-impl.md`

### 4i) Strip provenance markers

After Phase 3 sanitization runs in Phase 5 and before anything is
written to disk, clipboard, or stdout, remove every internal
`origin=...` marker from both `SHORT_PROMPT` and `FULL_ARTIFACT`.
Provenance tracking is a Phase 3/4 implementation detail, not part of
the emitted output.

### 4j) Placeholder lint

Callers pass free-form text into `INSTRUCTIONS`. That text can
contain placeholder-shaped tokens (`<dir-with-spaces>`,
`<REPO_ROOT>`, `<path-here>`) meant to be substituted by the
receiving agent. When such tokens land inside a fenced code block
in the assembled output, a receiving agent copying the command
verbatim will either run it with the literal text (usually failing)
or strip the `<...>` as a shell redirection and run it empty
(silently broken). Neither is the caller's intent. The lint
catches these at send-time and emits a canonical warning so the
receiving agent sees explicit instruction to substitute.

This step runs at Phase 5 time, AFTER Phase 3 sanitization (so
`[REDACTED -- see foo]` tokens do not shape-match a placeholder)
and AFTER step 4i provenance-strip (so `origin=...` markers are
already gone), and BEFORE Phase 5 output. In other words, the lint
reads the final, shipping text and flags what the receiver will
actually see.

**Scan pattern.** Apply the regex `<[A-Za-z][A-Za-z0-9_-]*>` to
the CONTENT of every code segment in both `SHORT_PROMPT` and
`FULL_ARTIFACT`. A code segment is any of:

- A fenced code block delimited by triple backticks (` ``` `) or
  triple tildes (`~~~`).
- An inline code span delimited by a run of one or more backticks
  of matching length (Markdown: `` `code` ``, `` ``code`` ``, etc.).
  Inline spans are where single-line command examples most often
  live when threaded into Task description or Specific questions
  — they are the exact case the lint exists to catch.

Do NOT scan prose text outside code segments — placeholders in
prose are natural and readable (readers interpret `<some-path>`
as a slot automatically). The lint only targets the
copy-paste-execute path.

**Whitelist (pass without warning).** The following tokens are
common literal HTML/Markdown that legitimately appear inside code
fences and are not placeholder slots:

- HTML tags: `<html>`, `<body>`, `<head>`, `<title>`, `<br>`,
  `<hr>`, `<p>`, `<div>`, `<span>`, `<a>`, `<img>`, `<ul>`,
  `<ol>`, `<li>`, `<code>`, `<pre>`, `<em>`, `<strong>`.
- Self-closing variants of the same set (e.g. `<br/>`, `<img/>`)
  match the same regex and are whitelisted alongside.

Match the whitelist case-insensitively. Tokens inside SGML/HTML
comments `<!-- ... -->` are also ignored — a `<!--` open tag does
not match the regex anyway (starts with `!`, not `[A-Za-z]`), but
document the intent for future maintainers.

**Warning shape.** For every non-whitelisted hit, append one
warning to the `warnings:` list using the canonical 3-segment
shape Phase 1 / Phase 2 / Phase 3 established:

```
[warning: placeholder not resolved -- "<token>" appears inside a code segment -- receiving agent must substitute before executing]
```

Replace `<token>` with the exact matched text (keep the angle
brackets). Deduplicate: if the same token appears multiple times
in the same output tier, emit a single warning for it and do not
repeat. If the same token appears in BOTH `SHORT_PROMPT` and
`FULL_ARTIFACT`, emit only one warning — the two tiers share a
warnings list.

**Re-render the warnings sections after appending.** Step 4h
renders the YAML `warnings:` frontmatter block (in
`FULL_ARTIFACT`) and the body `## Warnings` section (in both
tiers) at assembly time, BEFORE the lint runs. A warning
appended here does NOT automatically propagate to those already-
rendered strings. To close that gap, the lint MUST re-render
the warnings sections in both output strings after appending
any new warning:

1. Rebuild the YAML `warnings:` block in `FULL_ARTIFACT` per
   the field order and empty-state rule in step 4h — replace
   the existing block inline (between the `---` fences)
   rather than emitting a second block.
2. Rebuild the body `## Warnings` section in BOTH `SHORT_PROMPT`
   and `FULL_ARTIFACT` — render every current warning as a
   bullet in the canonical list.

If the lint appends zero warnings, SKIP the re-render (no state
changed; avoid rewriting identical bytes). If the lint appends
one or more, ALWAYS re-render, even if only one tier contained
the matching placeholder — the warnings list is shared across
tiers (see the deduplication rule above), so both tiers need the
updated section to stay consistent.

**Invariant.** The placeholder text ITSELF passes through
unchanged — the caller's intent is preserved and the receiving
agent can act on the warning. Only the `warnings:` frontmatter
and body `## Warnings` section are rebuilt, and only to reflect
the updated list.

**Worked case.** Caller runs:

```
/session-handoff assign impl -- Run the smoke test: `node spawn.js --workdir "<dir-with-spaces>"`
```

The assembled `SHORT_PROMPT` contains the command inside a
single-backtick inline span (`` `node spawn.js --workdir
"<dir-with-spaces>"` ``). The lint scans the inline span's
content, matches `<dir-with-spaces>` against the regex, does
not match the whitelist, and appends:

```
[warning: placeholder not resolved -- "<dir-with-spaces>" appears inside a code segment -- receiving agent must substitute before executing]
```

The lint then re-renders the `warnings:` frontmatter block and
the body `## Warnings` section in both output tiers so the new
warning reaches the emitted artifact. The receiving agent now
sees both the command and the warning, knows the placeholder is
a slot (not a typo or an empty string), and substitutes before
executing.

---

## Phase 5: Output

Phase 5 applies the Phase 3 sanitizer, writes the full artifact to
disk, copies the short prompt to the clipboard, and prints the short
prompt + artifact path to stdout. The steps run in the order below.
Failures at any step emit a canonical warning but NEVER hide the short
prompt from the user.

### 5.1) Sanitize both strings

Call the Phase 3 sanitizer on `SHORT_PROMPT` and `FULL_ARTIFACT`
independently. Apply all four pattern categories. Replace matches with
`[REDACTED -- see {origin}]` when the containing section carries a
provenance tag and `[REDACTED -- potential secret removed]` otherwise.
The over-redaction rule is preserved — when Phase 3 would redact, we
redact, even when the match looks like a false positive.

Do NOT bypass or weaken Phase 3. If Phase 3 emitted a
`[warning: sanitization skipped -- ...]` earlier (malformed pattern,
missing file, unreadable file), Phase 5 still writes, copies, and
prints the output, but the warning remains in the `warnings:` block
so the receiving agent knows the output was not scrubbed.

### 5.2) Strip provenance markers

Apply step 4i to both sanitized strings. Nothing that reaches the
user should contain `origin=...` text.

### 5.2.5) Placeholder lint

Apply step 4j to both sanitized, provenance-stripped strings.
Scan every code segment (fenced code blocks AND inline code
spans) for placeholder-shaped tokens, skip the whitelist, and
append a canonical warning per non-whitelisted hit. If any
warnings were appended, re-render the YAML `warnings:`
frontmatter block in `FULL_ARTIFACT` and the body `## Warnings`
section in BOTH tiers so the newly-added warnings reach the
emitted output. Placeholder tokens themselves pass through
unchanged. See step 4j for the full regex, whitelist, warning
shape, and re-render contract.

### 5.3) Ensure the artifact directory exists

```bash
ARTIFACT_DIR="$HOME/.claude/handoffs/$SLUG"
mkdir -p "$ARTIFACT_DIR" 2>/dev/null || \
  echo "[warning: artifact write failed -- could not create $ARTIFACT_DIR -- full artifact not saved to disk]"
```

`mkdir -p` is idempotent and creates parent directories; success is
silent. If it fails (read-only home, quota, permissions), emit the
canonical warning and skip the write step. Clipboard copy and stdout
print still run.

### 5.4) Write the full artifact

Use the `Write` tool to create the file at the path computed in
step 4h. If the write fails for any reason other than a missing
directory (step 5.3 handles that), emit the same canonical warning
with the appropriate reason segment:

```
[warning: artifact write failed -- {reason} -- full artifact not saved to disk]
```

Common `{reason}` values: `permission denied`, `disk full`,
`$ARTIFACT_PATH is a directory`.

### 5.5) Copy the short prompt to the clipboard

Try the platform-specific commands in this order, stopping at the
first one that succeeds:

```bash
if command -v clip.exe >/dev/null 2>&1; then
  printf '%s' "$SHORT_PROMPT" | clip.exe && CLIP_CMD="clip.exe"
elif command -v pbcopy >/dev/null 2>&1; then
  printf '%s' "$SHORT_PROMPT" | pbcopy && CLIP_CMD="pbcopy"
elif command -v xclip >/dev/null 2>&1; then
  printf '%s' "$SHORT_PROMPT" | xclip -selection clipboard && CLIP_CMD="xclip"
else
  CLIP_CMD=""
fi
```

If none of the commands exists (or all three fail), emit:

```
[warning: clipboard copy failed -- clip.exe/pbcopy/xclip not found -- copy the prompt above manually]
```

If a single command was tried and failed for an unrelated reason
(e.g. `xclip` exists but there is no X display), use the same shape
with the specific command name in the reason segment:

```
[warning: clipboard copy failed -- xclip returned non-zero exit status -- copy the prompt above manually]
```

The short prompt is ALWAYS printed to stdout regardless of clipboard
success (step 5.6). The warning tells the user to copy by hand; it
does not suppress the prompt.

### 5.6) Print the short prompt and confirmation

Print exactly this structure to stdout:

````
## Handoff Prompt (copy this)

```
{SHORT_PROMPT}
```

Full artifact saved to: {artifact_path}
````

If the clipboard-failure warning fired in step 5.5, print it on its
own line between the closing fence and the "Full artifact saved to"
line so the user sees it immediately next to the prompt.

If the artifact-write warning fired in step 5.3 or 5.4, replace the
"Full artifact saved to: {artifact_path}" line with the warning line,
so the user does not chase a nonexistent file.

### 5.7) Set `OUTCOME` for the finalize block

- `OUTCOME=success` — `SHORT_PROMPT` was assembled and printed. This
  is the default: clipboard or artifact-write failures emit warnings,
  not errors.
- `OUTCOME=error` — Phase 4 assembly itself failed and no
  `SHORT_PROMPT` is available.
- `OUTCOME=abort` — user aborted mid-run.

The finalize block below emits the timeline event using this value.

---

## Source precedence (when sources conflict)

1. **Git state** — ground truth, deterministic. Branch, HEAD SHA,
   worktree dirty flag.
2. **Plan files** with `status: active` in YAML frontmatter — structured,
   versioned.
3. **Checkpoint files** under `~/.gstack/projects/{slug}/checkpoints/` —
   recent but may be stale.
4. **CLAUDE.md** — project context, may be outdated.
5. **Conversation context** — best-effort, lossy, explicitly marked
   `[inferred from session]`.

If a higher-precedence source disagrees with a lower one (for example
CLAUDE.md claims the branch is `main` but `git` says `feat/foo`), trust
the higher-precedence source and emit a warning that names the
disagreement.

---

## Finalize (timeline complete)

When the workflow ends (success, error, or abort), log the completion
event. This is a local-only timeline entry, not telemetry; it is never
transmitted anywhere.

```bash
_TEL_END=$(date +%s)
_TEL_DUR=$(( _TEL_END - _TEL_START ))
~/.claude/skills/gstack/bin/gstack-timeline-log \
  '{"skill":"session-handoff","event":"completed","branch":"'"$_BRANCH"'","outcome":"'"${OUTCOME:-success}"'","duration_s":"'"$_TEL_DUR"'","session":"'"$_SESSION_ID"'"}' \
  2>/dev/null || true
```

Replace `OUTCOME` with one of `success`, `error`, or `abort` based on how
the workflow concluded. If you cannot determine the outcome, use `unknown`.

---

## Important rules

- **Never modify source code, plan files, checkpoint files, or CLAUDE.md.**
  This skill reads state and writes only to `~/.claude/handoffs/` (the
  artifact write itself is implemented in Unit 4).
- **Always capture HEAD SHA and worktree dirty flag.** Branch name alone
  does not identify exact working state; parallel sessions on a shared
  worktree can diverge between invocations.
- **Structured warnings, not silent omission.** Every missing source
  emits a `[warning: ...]` line naming the source, the reason, and what
  was skipped.
- **Mark conversation-sourced content as inferred.** The receiving agent
  treats git state, plan files, and checkpoints as facts; conversation
  content is best-effort and must be tagged `[inferred from session]`.
- **Do not fabricate.** If a decision was not discussed or a plan does
  not exist, emit the corresponding warning instead of guessing.

---

## Example Output

A synthetic scenario — the `yoga-house` website rebuild, Phase 2 handoff
to an implementation agent. Data below is fabricated for illustration;
no real secrets or real file paths are included.

**Command invoked:**

```
/session-handoff impl -- start phase 2: email confirmation + server-side validation
```

**Parses to:** `MSG_TYPE=handoff`, `TARGET_ROLE=impl` (via backward-
compatible role-in-first-slot), `INSTRUCTIONS="start phase 2: email
confirmation + server-side validation"`.

### Short prompt (copied to clipboard, printed to stdout)

What the clipboard receives after Phase 5. Opens with the `impl` role
preamble (with `{phase}` and `{plan_path}` substituted from Phase 1b),
ends with the artifact-pointer line.

```
You are the implementation agent for Rebuild booking flow with email confirmation. Read the plan at docs/plans/2026-04-15-001-feat-rebuild-booking-flow-plan.md, start with /ce:work. If the plan references a checkpoint, resume from it with /checkpoint resume before editing any files. Do not re-scope the work — the plan is the contract. If you need to deviate, surface it in Open questions and pause for the coordinator; do not silently change direction.

## Project context

- Repo: `yoga-house`
- Branch: `feat/booking-rebuild`
- HEAD SHA: `a1b2c3d`
- Worktree: dirty

## Status summary

Implementing Phase 2 of the booking-flow rebuild on `feat/booking-rebuild` (worktree dirty). Phase 1 (form scaffolding) landed; Phase 2 wires email confirmation and server-side validation.

## Plan reference

- `docs/plans/2026-04-15-001-feat-rebuild-booking-flow-plan.md`

## Instructions

start phase 2: email confirmation + server-side validation. Load the SendGrid key from `[REDACTED -- see CLAUDE.md]` at runtime; do not inline the value.

## Warnings

- [warning: checkpoint not found -- ~/.gstack/projects/yoga-house/checkpoints does not exist -- checkpoint pointer omitted]

If on the same machine, read `~/.claude/handoffs/yoga-house/20260418-151530-handoff-impl.md` for additional detail.
```

The `[REDACTED -- see CLAUDE.md]` token was inserted by Phase 3
sanitization: a raw `SG.xxxxx…` value was scanned out and replaced with
a reference to the source file so the receiving agent knows where to
re-read it. The checkpoint warning uses the canonical 3-segment shape
(`{source} not available -- {reason} -- {what was skipped}`).

### Full artifact (saved to disk)

Written to `~/.claude/handoffs/yoga-house/20260418-151530-handoff-impl.md`.
Frontmatter fields appear in the exact order downstream tooling
(future `/session-receive`) will parse; `schema_version: 1` anchors
forward compatibility.

````
---
schema_version: 1
type: handoff
role: impl
branch: feat/booking-rebuild
sha: a1b2c3d
timestamp: 2026-04-18T15:15:30Z
source_session_id: 48291-1713453330
warnings:
  - "[warning: checkpoint not found -- ~/.gstack/projects/yoga-house/checkpoints does not exist -- checkpoint pointer omitted]"
---

## Role preamble

You are the implementation agent for Rebuild booking flow with email confirmation. Read the plan at docs/plans/2026-04-15-001-feat-rebuild-booking-flow-plan.md, start with /ce:work. If the plan references a checkpoint, resume from it with /checkpoint resume before editing any files. Do not re-scope the work — the plan is the contract. If you need to deviate, surface it in Open questions and pause for the coordinator; do not silently change direction.

## Project context

- Repo: `yoga-house`
- Branch: `feat/booking-rebuild`
- HEAD SHA: `a1b2c3d`
- Worktree: dirty
- CLAUDE.md: found (path: ./CLAUDE.md)

## Status summary

Implementing Phase 2 of the booking-flow rebuild on `feat/booking-rebuild` (worktree dirty). Phase 1 (form scaffolding) landed; Phase 2 wires email confirmation and server-side validation.

## Plan reference

- `docs/plans/2026-04-15-001-feat-rebuild-booking-flow-plan.md`

## Instructions

start phase 2: email confirmation + server-side validation. Load the SendGrid key from `[REDACTED -- see CLAUDE.md]` at runtime; do not inline the value.

## Decisions

- [inferred from session] Phase 1 (form scaffolding) is closed on `feat/booking-rebuild`; Phase 2 continues on the same branch rather than forking.
- [inferred from session] Email delivery goes through SendGrid, not SMTP — the key lives in `CLAUDE.md` and is loaded via env var at runtime.

## Open questions

- [inferred from session] Is the confirmation email template owned by this phase, or does marketing provide the copy?

## Git details

```
 M app/booking/page.tsx
 M app/booking/form.tsx
A  app/booking/confirm-email.ts

a1b2c3d feat(booking): scaffold confirmation form
94fe201 feat(booking): add client-side validation
77ab3f0 chore: seed booking tests
c10ba44 feat(booking): initial form route
e8d21f9 docs: capture rebuild plan

 app/booking/confirm-email.ts | 42 ++++++++++++++++++++++++
 app/booking/form.tsx         |  6 ++--
 app/booking/page.tsx         |  4 +-
 3 files changed, 48 insertions(+), 4 deletions(-)
```

## Warnings

- [warning: checkpoint not found -- ~/.gstack/projects/yoga-house/checkpoints does not exist -- checkpoint pointer omitted]

## Artifact pointer

If on the same machine, read `~/.claude/handoffs/yoga-house/20260418-151530-handoff-impl.md` for additional detail.
````

Notes on what this example teaches:

- **Role preamble substitution.** `{phase}` resolved to the plan's
  `title:` frontmatter value; `{plan_path}` resolved to the plan file's
  repo-relative path. Both appear inline in the opening paragraph.
- **Two-tier split.** The short prompt carries only `handoff`'s primary
  sections (Project context, Status summary, Plan reference,
  Instructions). Decisions, Open questions, and Git details are
  secondary — they appear in the full artifact only.
- **Warnings propagation.** The single `checkpoint not found` warning
  from Phase 1c appears in both the frontmatter `warnings:` block and
  the body `## Warnings` section. Missing-source lines are verbatim
  across tiers.
- **Sanitization replacement.** `[REDACTED -- see CLAUDE.md]` replaces
  what was originally a raw API key value, preserving the source file
  path so the receiving agent can fetch the real value locally.
- **`[inferred from session]` tags.** Every line under Decisions and
  Open questions is conversation-sourced — not git, not plan, not
  checkpoint — so each carries the `[inferred from session]` tag per
  the source-precedence rules.
- **Artifact path shape.** `~/.claude/handoffs/{slug}/{YYYYMMDD-HHMMSS}-{type}-{role}.md`
  matches the checkpoint skill's naming convention, so handoffs and
  checkpoints sort consistently in listings.

When `gstack-slug` is absent, the `{slug}` segment falls back to
`unknown` and the artifact lands under `~/.claude/handoffs/unknown/`.
The skill still works; the receiving agent sees the fallback path
verbatim.
