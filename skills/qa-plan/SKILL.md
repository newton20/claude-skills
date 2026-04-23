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

<!-- Unit 3 will add: Phase 1 context gathering + surface classification -->
<!-- Units 6-10 will add: Phases 2-6 -->

