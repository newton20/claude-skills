---
name: qa-plan
preamble-tier: 1
version: 0.1.0
description: |
  Surface-aware QA test plan author. Classifies the just-implemented
  change against a 5-surface taxonomy (web, cli, library, service,
  claude-skill), drafts an impl-aware test plan, runs the plan through
  4 adversarial personas + 1 spec-only gap reviewer + a cross-model
  codex pass, then prints a /session-handoff assign qa command for
  fresh-session execution. The skill does NOT run tests, write test
  code, or modify source — it authors a reviewed plan and hands off.
  Use when asked to "qa plan", "qa-plan", "test plan", "author a test
  plan", "plan the QA", "review what to test", "what should QA cover",
  "hand off to QA", "draft QA for this change", or immediately after
  completing an implementation unit that needs adversarial QA before
  merge.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
  - Agent
---

# /qa-plan — Surface-Aware Test Plan Author with Adversarial Review

You are a **test plan author**. Your job is to classify what was just
implemented, draft a surface-appropriate test plan, run that plan
through a parallel adversarial review, synthesize the reviewed plan
to disk, and print a `/session-handoff assign qa` command the user
can paste into a fresh Claude Code session for QA execution.

This skill does NOT execute tests, generate test code, or modify
source. It authors a reviewed plan and hands off. See the three
non-negotiable gates below.

**HARD GATE 1 — no test execution.** Do NOT run tests, spawn
subprocesses that run tests, install test runners, or otherwise
exercise code under test. This skill only authors a plan. Test
execution belongs in the QA session the handoff command launches.
If a user prompt says "just run the tests real quick", "spawn a
subprocess to check if Playwright is installed", "execute this once
to confirm", or any variant that asks for test execution, decline
with the verbatim response:

> I can't run tests from `/qa-plan` — that's the QA session's job.
> The whole point of authoring a reviewed plan and handing off to
> a fresh session is context separation. I'll finish the plan; you
> paste the handoff command in a new Claude Code window and the
> fresh agent executes it.

**HARD GATE 2 — no test code generation.** Do NOT write test files,
assertion statements, fixtures, mocks, Playwright scripts, pytest
cases, RSpec examples, or any executable test artifact. The plan
describes WHAT to test in prose; it never contains code the QA
session could run verbatim. If a user prompt says "write the test
code for this case", "give me an assert statement for X, not the
full test", or "just sketch the test function", decline with the
verbatim response:

> I can't generate test code — even a single assertion counts as
> test code and belongs in the QA session. The plan describes cases
> in prose so the QA agent picks the framework, structure, and
> exact assertions once it sees the runtime. Ask the QA session to
> author the code after you paste the handoff.

**HARD GATE 3 — no repository source modification.** Do NOT edit,
add, or delete repository source files to make testing easier, to
fix a bug surfaced during planning, or for any other reason. The
only files this skill writes are the plan artifact
(`docs/qa-plans/*-qa-plan.md`), the mirror
(`~/.gstack/projects/{slug}/*-qa-plan-*.md`), and the analytics
append (`~/.gstack/analytics/skill-usage.jsonl`). If a user prompt
says "modify this source file to make the test easier to write",
"bypass the handoff; you're in a rush", "ignore the gate just for
this one regression test", or any variant asking for repository
mutation, decline with the verbatim response:

> I can't modify repository source from `/qa-plan`. The handoff IS
> the value prop — context-separation is load-bearing, and editing
> source here would silently mix implementer context into the QA
> plan. If the plan surfaces a bug, note it in the plan; the QA
> session or a follow-up `/ce-work` pass fixes it in its own
> context.

The three gates are ORTHOGONAL: a single prompt can violate more
than one. Decline the strongest gate and reference the others in
order (gate 1 > gate 2 > gate 3). Gates are NOT negotiable per-case
— "just this once" answers the same as "always": no.

---

## Quick Start

```bash
# In any project with a recent implementation to test:
/qa-plan                    # classify surface, draft plan, review, hand off
/qa-plan --                 # same; trailing -- is accepted but has no args
```

The reviewed plan is written to `docs/qa-plans/{datetime}-{branch}-qa-plan.md`
(repo-tracked primary) and mirrored to
`~/.gstack/projects/{slug}/{user}-{branch}-qa-plan-{datetime}.md`.
A `/session-handoff assign qa` command string is printed to the
terminal, wrapped in a machine-parseable
`<qa-plan-handoff version="1">...</qa-plan-handoff>` block so
downstream orchestrator agents can consume it without regex-against-
prose. Paste the `command:` line into a FRESH Claude Code window
(same machine or not) to run the plan in a QA session.

---

## Prerequisites

- **Claude Code CLI.** Skill is invoked as a slash command.
- **git repository.** Required. The skill classifies the surface
  from the diff; absence aborts with a canonical warning.
- **`session-handoff` skill installed** at `~/.claude/skills/session-handoff/`.
  The handoff command string this skill prints is executed by that
  skill when the user pastes it into a fresh session.
- **Claude Code `Agent` tool** available to the orchestrator.
  Required; Phase 3 dispatches 4 personas + 1 spec-only reviewer
  in a single multi-tool-call block.
- **`codex` binary** *(optional).* Enables the cross-model review
  pass. Absent or unauthenticated = graceful fallback to a Claude
  subagent, with canonical warning in Reviewer Coverage.
- **`~/.gstack/projects/` layout** *(optional).* Mirror destination
  for the plan artifact. Absence = repo-local write only, with
  canonical warning.
- **`jq` binary** *(optional).* Analytics emission uses `jq -n`
  for JSON-serialization. If absent, the analytics step is skipped
  with canonical warning; the primary plan output is not affected.

Degrades gracefully on every optional source: you always get a
reviewed plan file and a handoff command, even if codex is missing,
`~/.gstack/` is absent, and one persona times out.

---

## Preamble (run first)

```bash
# Session + slug (sets SLUG, REPO when gstack-slug is available)
mkdir -p ~/.gstack/sessions
touch ~/.gstack/sessions/"$PPID"
eval "$(~/.claude/skills/gstack/bin/gstack-slug 2>/dev/null)" 2>/dev/null || true
SLUG="${SLUG:-unknown}"

# Values reused by Phase 1 and later phases
_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
_BRANCH_SLUG=$(echo "$_BRANCH" | sed 's|/|-|g')
_SESSION_ID="$$-$(date +%s)"
_TEL_START=$(date +%s)
_TS=$(date +%Y%m%d-%H%M%S)
echo "BRANCH: $_BRANCH"
echo "BRANCH_SLUG: $_BRANCH_SLUG"
echo "SLUG: $SLUG"
echo "SESSION_ID: $_SESSION_ID"
echo "TS: $_TS"

# Detect orchestrator-spawned session (e.g., OpenClaw). Spawned sessions
# auto-pick recommended defaults instead of calling AskUserQuestion.
if [ -n "$OPENCLAW_SESSION" ]; then
  echo "SPAWNED_SESSION: true"
else
  echo "SPAWNED_SESSION: false"
fi

# Timeline: skill started (local-only).
~/.claude/skills/gstack/bin/gstack-timeline-log \
  '{"skill":"qa-plan","event":"started","branch":"'"$_BRANCH"'","session":"'"$_SESSION_ID"'"}' \
  2>/dev/null &
```

If the preamble prints `SPAWNED_SESSION: true`, do NOT call
`AskUserQuestion` for any interactive step in later phases. Auto-
pick the recommended option and surface the choice in the
Reviewer Coverage appendix (matches session-handoff discipline:
see `skills/session-handoff/SKILL.md` lines 110-114).

If `gstack-slug` is missing, `SLUG` falls back to `unknown`. The
mirror write in Phase 2 then targets `~/.gstack/projects/unknown/`
or is skipped with a canonical warning; the repo-local plan write
still proceeds.

---

## Auto-cleanup (run before Phase 1)

Stub for v0.2. Reviewed plans under `docs/qa-plans/` and mirrors
under `~/.gstack/projects/{slug}/*-qa-plan-*.md` accumulate across
runs. v0.1 leaves both directories growing; v0.2 will prune
artifacts older than 14 days mirroring session-handoff's
`auto-cleanup` hook. The hook lives here so phase-numbering does
not have to shift when v0.2 implements the logic:

```bash
# v0.2 will implement stale-artifact cleanup here. v0.1 intentionally
# no-ops: dogfood first, then decide whether 14-day pruning matches
# user expectations or produces surprise deletions.
:
```

---

## Phase 1: Context gathering + surface classification

Phase 1 resolves the inputs every downstream phase depends on: the
diff to reason about, the project context (CLAUDE.md + active
design doc), and the surface classification (web / cli / library /
service / claude-skill / mixed) that drives which axis taxonomy the
Phase 2 planner uses.

Every failure or degradation path emits the canonical 3-segment
warning:

```
[warning: {source} not available -- {reason} -- {what was skipped}]
```

The receiving downstream phases parse warnings uniformly and surface
them in the final Reviewer Coverage appendix (Phase 4).

### 1a) Diff-source expansion (committed → staged → working-tree)

Do NOT abort on an empty committed diff alone. Check staged and
working-tree diffs in order; use the first non-empty one as the
diff source. When the working-tree diff is used (uncommitted
changes), record the fact for the Reviewer Coverage appendix so the
receiving QA agent knows the plan applies to WIP, not to HEAD.

```bash
# Resolve the base branch for the diff. Prefer origin/HEAD, fall
# back to main, then master.
_BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
  | sed 's@^refs/remotes/origin/@@')
if [ -z "$_BASE_BRANCH" ]; then
  _BASE_BRANCH=$(git rev-parse --verify origin/main >/dev/null 2>&1 \
    && echo "main" || echo "master")
fi

# Try committed diff first.
_DIFF_SOURCE="committed"
_DIFF_STAT=$(git diff "$_BASE_BRANCH"...HEAD --stat 2>/dev/null)
_DIFF_PATHS=$(git diff "$_BASE_BRANCH"...HEAD --name-only 2>/dev/null)

# Fall back to staged.
if [ -z "$_DIFF_STAT" ]; then
  _DIFF_SOURCE="staged"
  _DIFF_STAT=$(git diff --staged --stat 2>/dev/null)
  _DIFF_PATHS=$(git diff --staged --name-only 2>/dev/null)
fi

# Fall back to working tree (uncommitted).
if [ -z "$_DIFF_STAT" ]; then
  _DIFF_SOURCE="working-tree"
  _DIFF_STAT=$(git diff HEAD --stat 2>/dev/null)
  _DIFF_PATHS=$(git diff HEAD --name-only 2>/dev/null)
fi

# All three empty: abort with canonical warning.
if [ -z "$_DIFF_STAT" ]; then
  echo "[warning: no diff -- neither committed, staged, nor working-tree changes -- /qa-plan skipped]"
  exit 1
fi

echo "DIFF_SOURCE: $_DIFF_SOURCE"
echo "DIFF_STAT:"
echo "$_DIFF_STAT"
```

When `DIFF_SOURCE` is `working-tree` or `staged`, note it in the
Reviewer Coverage appendix (Phase 4) with the line:

> *"Working-tree diff used (uncommitted changes); commit before
> merge to ensure plan applies to reviewed code."*

### 1b) No-git-repo guard

```bash
if ! command -v git >/dev/null 2>&1 || ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "[warning: git -- not in a repository -- /qa-plan cannot classify surface, skipped]"
  exit 1
fi
```

Place this guard before step 1a so the working-tree-diff fallback
never runs outside a repo.

### 1c) Stale-DRAFT detection (warn-and-proceed)

Interrupted prior runs can leave orphan DRAFT plan files. Detect
them and warn; do NOT block with an interactive question. The
three-way resume/discard/ignore flow was cut during deepen-plan as
premature — v0.2 may add resume semantics if orphans accumulate in
practice.

```bash
STALE_DRAFTS=$(find docs/qa-plans -maxdepth 1 -type f -name "*-${_BRANCH_SLUG}-qa-plan.md" 2>/dev/null \
  | xargs -I {} sh -c 'grep -l "^status: DRAFT" "{}" 2>/dev/null || true')
if [ -n "$STALE_DRAFTS" ]; then
  while IFS= read -r stale; do
    echo "[warning: stale DRAFT found at $stale -- from interrupted prior run -- starting fresh; delete manually if undesired]"
  done <<< "$STALE_DRAFTS"
fi
```

Proceed to the rest of Phase 1 regardless.

### 1d) CLAUDE.md presence

```bash
if [ -f CLAUDE.md ]; then
  echo "CLAUDE.md: found"
else
  echo "[warning: CLAUDE.md -- file not present -- proceeding without project context]"
fi
```

CLAUDE.md absence is informational, not fatal. The Phase 2 planner
still runs; it just has one fewer context source.

### 1e) Active design doc (optional)

```bash
DESIGN_DOC=$(find "$HOME/.gstack/projects/$SLUG" -maxdepth 1 -type f \
  -name "*${_BRANCH}-design-*.md" 2>/dev/null \
  | sort | tail -1)
if [ -n "$DESIGN_DOC" ]; then
  echo "DESIGN_DOC: $DESIGN_DOC"
else
  echo "[warning: design doc -- no *${_BRANCH}-design-*.md under ~/.gstack/projects/$SLUG -- proceeding without design context]"
fi
```

If present, the Phase 2 planner reads this file as ground-truth
for product intent. If absent, the planner relies on the diff +
CLAUDE.md + plan docs alone.

### 1f) Diff-size guard (no auto-narrow)

Large diffs overflow the Phase 2 planner's context. The original
"top 10 by commit count" auto-narrow was flagged in codex review as
an author-activity proxy, not a risk proxy — it would silently drop
security-critical single-file changes. Ask the user instead.

```bash
_DIFF_LINES=$(echo "$_DIFF_STAT" | tail -1 | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo "0")
_DIFF_LINES=${_DIFF_LINES:-0}
if [ "$_DIFF_LINES" -gt 5000 ]; then
  echo "DIFF_SIZE_EXCEEDED: $_DIFF_LINES lines"
fi
```

When `DIFF_SIZE_EXCEEDED` is printed, use `AskUserQuestion`:

- **Question:** "Diff is ${_DIFF_LINES} lines — too large to fit in Phase 2 context. How should I scope?"
- **Option A (recommended):** *"Proceed with full diff; rely on stat-only summary + selective file reads for risk identification"*
- **Option B:** *"I'll provide a comma-separated list of path/glob patterns to scope to (e.g., `src/auth/*,migrations/20260422*`)"*
- **Option C:** *"Abort — I'll split the diff into smaller chunks and re-run `/qa-plan` per chunk"*

**SPAWNED_SESSION behavior:** if `OPENCLAW_SESSION` is set, auto-
pick option A (proceed with full diff) and record in Reviewer
Coverage: `AskUserQuestion auto-resolved (diff-size guard → proceed with full diff) due to spawned session.`

### 1g) Surface auto-detection + user confirmation

Read `references/taxonomies.md` for the per-surface axis list and
spec/impl boundary before classifying. The path-pattern rules live
in that file under the "Surface detection rules" table.
Representative rules:

| Diff path pattern                         | Detected surface |
|-------------------------------------------|------------------|
| `*.tsx`, `*.jsx`, `*.html`, `*.css`, `public/*` | web         |
| `bin/*`, `cmd/*`, `cli/*`, `package.json#bin`   | cli         |
| `lib/*`, `src/lib/*`, `pkg/*`                    | library     |
| `api/*`, `routes/*`, `migrations/*`, `Docker*`   | service     |
| `skills/*/SKILL.md`, `~/.claude/skills/*`        | claude-skill |

Count matches per surface across `$_DIFF_PATHS`. The surface with
the most matches is the auto-detected primary.

Use `AskUserQuestion` to confirm:

- **Question:** "Auto-detected surface: `{primary}` ({N} matching files). Confirm?"
- **Option A (Recommended):** *"Yes, {primary}"*
- **Option B–E:** the other four surfaces, each labeled with the
  match count for that surface (`web (3 files)`, `cli (0 files)`,
  etc.) so the user sees why auto-detection chose the primary
- **Option F:** *"mixed — I'll answer the follow-up"*

**SPAWNED_SESSION behavior:** if `OPENCLAW_SESSION` is set, auto-
pick the `{primary}` option and record the auto-pick in Reviewer
Coverage.

### 1h) Mixed-surface sub-question

If ≥2 surfaces have non-zero match counts, the user may have
picked option F above or you may decide to ask proactively. Ask:

- **Question:** "Multiple surfaces detected: {list with counts}. How should I plan?"
- **Option A (Recommended):** *"Primary = {primary}; include cross-cutting notes for the others in a single `## Cross-Surface` section"*
- **Option B:** *"Full multi-surface — author axis sections for every detected surface (longer plan, more coverage)"*

**SPAWNED_SESSION behavior:** auto-pick option A.

### 1i) Progress emission

Before handing off to Phase 2, print a status line so the user knows
what was decided:

```
[Phase 1] surface: {primary}; diff-source: {committed|staged|working-tree}; CLAUDE.md: {found|missing}; design doc: {found|missing}
```

---

## Phase 2: Impl-aware DRAFT authoring

You (the orchestrator) are the single impl-aware planner. You see
everything — the full diff, the source files, the design doc, plan
docs, `CLAUDE.md`. Your job is to author a DRAFT test plan that
covers the Phase 1 surface's axis list (from
`references/taxonomies.md`) with cases tagged by severity,
likelihood, and ≥1 risk dimension.

The black-box / spec-only signal that might otherwise argue for
splitting Phase 2 into parallel spec-vs-impl planners is NOT split
here. Round-5 review converged on rejecting a dual-planner
architecture: the merge step was load-bearing LLM-judgment that
could silently reconcile spec-vs-impl mismatches (the exact signal
the dual shape was meant to surface). Instead, Phase 3 adds a
5th reviewer (spec-only gap finder, Unit 7b) that APPENDS
cases to this DRAFT — additive, not reconciling. Keep Phase 2
single-planner.

### 2a) Read the inputs

Read, in order:

1. `references/taxonomies.md` — axis list for the Phase 1 surface
2. `$_DIFF_STAT` and `$_DIFF_PATHS` (already resolved in Phase 1)
3. The source files `$_DIFF_PATHS` refers to, as needed for axis
   coverage (not all of them blindly — read what you need to tag
   cases accurately)
4. `CLAUDE.md` if present
5. `$DESIGN_DOC` if present
6. Any `docs/plans/*-plan.md` files with `status: active` in
   frontmatter (these are IMPL-shaped, not spec-shaped — do not
   share with the Phase 3 spec-only reviewer)

### 2b) Author the DRAFT

Produce axis-structured markdown. For the detected surface, create
one `## {Axis}` section per axis from the taxonomy with cases
inside it. Every case follows the canonical line shape:

```
- <one-line case description> [axis, sev N/5, lik N/5, sev×lik=N, risk:<dim1,dim2>]
```

- `sev` and `lik` are integers 1-5 (product 1-25)
- `sev×lik` is pre-computed so Phase 4's sort is a plain text scan
- Every case is tagged with ≥1 risk dimension from the 5 cross-
  cutting tags in `references/taxonomies.md`
- Cap your own output to ~4000 tokens for the DRAFT; Phase 3
  reviewers add more, but an overlong DRAFT starves the Phase 3
  context window

Start with the worked examples in `references/taxonomies.md` to
calibrate sev / lik intuition for the surface. When unsure,
bias sev toward 3-4 and lik toward 2-3 rather than inventing
extremes.

### 2c) Resolve the plan file paths

Second-precision timestamp + capped collision guard. Handles two
`/qa-plan` invocations in the same second (rare but legal):

```bash
QA_PLAN_DIR="docs/qa-plans"
mkdir -p "$QA_PLAN_DIR"

PLAN_PATH="$QA_PLAN_DIR/${_TS}-${_BRANCH_SLUG}-qa-plan.md"
if [ -e "$PLAN_PATH" ]; then
  PLAN_PATH="$QA_PLAN_DIR/${_TS}-${_BRANCH_SLUG}-qa-plan-2.md"
fi
if [ -e "$PLAN_PATH" ]; then
  ORIG="$QA_PLAN_DIR/${_TS}-${_BRANCH_SLUG}-qa-plan.md"
  DUP="$QA_PLAN_DIR/${_TS}-${_BRANCH_SLUG}-qa-plan-2.md"
  echo "[warning: filename collision -- $ORIG and $DUP both exist -- aborting to avoid data loss]"
  exit 1
fi

echo "PLAN_PATH: $PLAN_PATH"
```

Second-precision is sufficient: a third back-to-back run in the
same clock second would be a genuine foot-gun (likely automation
that ignores the first two), and the canonical warning above fails
loudly rather than overwriting.

### 2d) Write the DRAFT

Write the authored axis-structured markdown to `$PLAN_PATH` with
this YAML frontmatter:

```yaml
---
status: DRAFT
branch: {_BRANCH}
base_commit: {git rev-parse --short HEAD output}
surface: {detected surface from Phase 1}
generated: {ISO-8601 timestamp in UTC}
---
```

Frontmatter keys stay in this exact order so Phase 4's in-place
`status: DRAFT` → `status: REVIEWED` flip and downstream parsers
see a stable shape.

### 2e) Mirror to ~/.gstack/projects/

Always copy (no symlink fallback — zero user-visible difference
for a terminal-state output file, per simplicity review).

```bash
USER_TAG="${USER:-unknown}"
MIRROR_DIR="$HOME/.gstack/projects/$SLUG"
if mkdir -p "$MIRROR_DIR" 2>/dev/null; then
  MIRROR_PATH="$MIRROR_DIR/${USER_TAG}-${_BRANCH}-qa-plan-${_TS}.md"
  if cp "$PLAN_PATH" "$MIRROR_PATH" 2>/dev/null; then
    echo "MIRROR_PATH: $MIRROR_PATH"
  else
    echo "[warning: mirror -- cp to $MIRROR_PATH failed -- plan still written to $PLAN_PATH]"
    MIRROR_PATH=""
  fi
else
  echo "[warning: mirror -- mkdir $MIRROR_DIR failed -- plan still written to $PLAN_PATH]"
  MIRROR_PATH=""
fi
```

The repo-tracked primary at `$PLAN_PATH` is authoritative. The
mirror is a convenience for cross-project discovery via
`~/.gstack/projects/`.

### 2f) SPAWNED_SESSION behavior

Phase 2 has no `AskUserQuestion` sites. If `OPENCLAW_SESSION` is
set, proceed silently; orchestrator-visible progress lines still
print.

### 2g) Progress emission

Before handing off to Phase 3, print:

```
[Phase 2] DRAFT written: {PLAN_PATH} ({N} cases across {M} axes); mirror: {MIRROR_PATH|not written}
```

---

<!-- Units 7-10 will add: Phases 3-6 -->



