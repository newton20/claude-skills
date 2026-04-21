---
status: complete
priority: p3
issue_id: "003"
tags: [session-handoff, phase-4, role-preamble, qa-robustness, documentation]
dependencies: []
---

# Session-handoff: sanitize placeholder-vs-literal in assembled role preambles

The `session-handoff` skill occasionally emits artifact text where a
placeholder-shaped token (`<dir-with-spaces>`, `<REPO_ROOT>`, etc.)
appears as a LITERAL command the receiving agent is expected to run.
A downstream QA agent correctly flagged this in a recent run: the
Role preamble passed to it contained `--workdir ""` (empty literal)
alongside a Scope table that showed the real intent
(`--workdir "<dir-with-spaces>"` as a placeholder to substitute).

The QA agent was smart enough to catch both and interpret the second
as the authoritative version, but other agents (especially less
capable ones, or ones on a deadline) may take the literal form at
face value and run a broken command. That's a silent-failure risk
the skill should close.

## Problem Statement

When the caller passes free-form instructions to `/session-handoff
assign qa -- ...`, the skill copies the instructions verbatim into
two places:

1. **Task description** (the primary section for `assign`) — this is
   where the detailed scope lands.
2. **Role preamble** — static opening paragraph, currently NOT
   substituted with anything except `{phase}` / `{plan_path}` for
   the `impl` role.

If the caller's instructions CONTAIN a placeholder-shaped token
(`<some-dir-with-spaces>`, `<path-here>`, `<REPO_ROOT>`), the Task
description keeps the placeholder intact (correct — placeholders are
instructions to the reader). But if the SAME string is echoed into
a code block as part of an example command (e.g. as part of the
Scope table's Smoke scenario), the receiving agent has no marker
distinguishing "this is a slot to fill" from "this is a literal
empty string."

In the 2026-04-20 PR #3 QA dispatch, my handoff artifact contained
this pattern:

```
node agent-orchestrator/scripts/spawn-session.js \
  --name orch-qa-smoke \
  --workdir "<some-dir-with-spaces>" \
  --launcher agency --dry-run
```

The QA agent reported that it saw both the literal
`--workdir ""` (empty-string form) somewhere AND the placeholder
form, and interpreted the literal as a typo. Looking back at my
artifact, the literal-empty-string form does NOT appear to be
something I wrote — it was the QA agent noticing the placeholder
rendered as an empty string in its execution of the smoke-test
(because the receiving agent correctly stripped the `<...>` as a
shell redirection attempt and got nothing). Either way, the skill
did not signal clearly enough that `<some-dir-with-spaces>` is a
substitution slot.

## Findings

- **Where the literal comes from.** Free-form `INSTRUCTIONS` text
  pasted into code fences does not get semantic processing. The
  skill treats command-looking text as literal prose and passes it
  through. This is correct for most cases — the caller may want
  verbatim scripts — but fails when placeholders are present.
- **Who catches it today.** The receiving agent, on a good day.
  Relies on agent intelligence to notice "hey, `<foo>` here is a
  slot, not a literal." Fragile.
- **Why it matters.** The `assign` message-type exists precisely
  because the caller wants a well-specified task. Injecting
  ambiguity between "slot" and "literal" undermines the whole
  point.
- **No evidence the Role preamble is the actual source.** Looking
  at the specific QA run (artifact at
  `~/.claude/handoffs/newton20-agent-orchestration/20260420-211104-assign-qa.md`),
  the Role preamble is the static text from
  `references/message-templates.md` — it does NOT contain
  `--workdir ""` or placeholder tokens. The ambiguity was in the
  Task description's Smoke scenario code block, which is where
  this fix should target.

## Proposed Solutions

### Option A — Skill-side placeholder linting (recommended)

Add a late-stage pass in Phase 4 (before Phase 5 output) that scans
the assembled `SHORT_PROMPT` and `FULL_ARTIFACT` for
placeholder-shaped tokens inside code fences:

```
/<[A-Za-z][A-Za-z0-9_-]*>/
```

For each hit, emit a canonical warning:

```
[warning: placeholder not resolved -- "<some-dir-with-spaces>" appears inside a code fence -- receiving agent must substitute before executing]
```

Placeholders in prose text (outside code fences) are fine — readers
naturally interpret them. The lint targets only code-fence content
where a copy-paste runs the command.

- **Pros:** Catches the bug at the source (the sending skill), zero
  change to receiving agents, the warning shape already exists and
  is surfaced in both output tiers.
- **Cons:** False positives possible — a caller may LEGITIMATELY
  want the literal text `<html>` in their instructions. Could
  whitelist common false-positive tokens (`<html>`, `<body>`,
  `<!-- -->`, `<>` empty).
- **Effort:** Small. Single regex pass + warning emission.
- **Risk:** Low. Warning is advisory; doesn't block output.

### Option B — Caller-side convention (documentation)

Document in the skill's README and `references/message-templates.md`
that callers should use a specific token format for substitution
slots (e.g. `${SOMETHING}` or `{{SOMETHING}}`) and that `<bracket>`
tokens are reserved for markup literals. No code changes in the
skill.

- **Pros:** Zero implementation cost.
- **Cons:** Relies on caller discipline. Does nothing for existing
  callers who already use `<bracket>` tokens.
- **Effort:** Trivial.
- **Risk:** Low.

### Option C — Receiver-side responsibility

Do nothing in the sending skill. Expect receiving agents to always
check code fences for placeholder tokens before executing. Add
guidance in the Role preambles of receiving-agent-facing roles
(qa, impl, reviewer).

- **Pros:** No skill changes.
- **Cons:** Pushes the burden to receivers, who may be running on
  less-capable models or in low-context modes.
- **Effort:** Small (edit the role preambles in
  `references/message-templates.md`).
- **Risk:** Medium. The QA agent caught it this time; others may
  not.

## Recommended Action

**Implement Option A (skill-side placeholder lint).** Add a new
Phase 4 step `4j) Placeholder lint` documenting a late-stage scan
that runs at Phase 5 time (after Phase 3 sanitization, before
provenance-strip, before output). The scan targets
placeholder-shaped tokens (`<[A-Za-z][A-Za-z0-9_-]*>`) inside
fenced code blocks in both `SHORT_PROMPT` and `FULL_ARTIFACT`.
Whitelist common HTML/Markdown false-positives. For each
non-whitelisted hit, append a canonical 3-segment warning to
the warnings list, which Phase 4h already propagates into both
output tiers.

Option B and Option C are rejected. Option B (caller convention)
relies on caller discipline and does nothing for existing usage.
Option C (receiver-side responsibility) pushes fragility downstream
to less-capable models. Only Option A closes the gap at the source.

## Technical Details

- Affected files:
  - `~/.claude/skills/session-handoff/SKILL.md` (Phase 4 / 5)
  - `~/.claude/skills/session-handoff/references/message-templates.md`
- Where the lint runs: between `SHORT_PROMPT` + `FULL_ARTIFACT`
  assembly in Phase 4 and Phase 5's sanitization step. After Phase 3
  sanitization (so redacted tokens like `[REDACTED -- ...]` don't
  false-positive on `<...>`-shape), before Phase 5 output.
- Warning shape: canonical 3-segment per Phase 1 / Phase 2 / Phase 3
  convention: `[warning: {source} not available -- {reason} -- {what
  was skipped or flagged}]`. Here:
  `[warning: placeholder not resolved -- "<foo>" appears inside a code fence -- receiving agent must substitute before executing]`

## Acceptance Criteria

- [ ] Run `/session-handoff assign qa -- run command with <placeholder> inside a code fence` and see the placeholder flagged with a warning in both the short prompt and the full artifact.
- [ ] Placeholders in PROSE (outside code fences) do not flag.
- [ ] Literal `<html>`, `<body>`, `<!-- -->` pass without warning (common false-positives whitelisted).
- [ ] No regression on existing worked examples in the skill's Phase 2 test table.

## Work Log

### 2026-04-20 - Triage + Implementation (Option A)

**By:** Claude Opus 4.7 (ce-work session, branch
`feat/todos-002-003-session-handoff-polish`)

**Triage decision:**
- Filled in Recommended Action with Option A (skill-side
  placeholder lint). Rejected Options B (caller discipline) and C
  (receiver-side responsibility) per the reasoning in the todo.
- Flipped frontmatter `status: pending` → `status: complete`
  after implementation landed (one session, not a two-pass
  triage-then-implement flow).

**Actions:**
- Added `### 4j) Placeholder lint` to
  `skills/session-handoff/SKILL.md` between step 4i (strip
  provenance markers) and the Phase 5 section break. Documents
  the scan regex `<[A-Za-z][A-Za-z0-9_-]*>`, the HTML/Markdown
  whitelist, the canonical 3-segment warning shape, deduplication
  across tiers, and a worked case.
- Added `### 5.2.5) Placeholder lint` to Phase 5 as a short
  pointer to step 4j, so the execution order is discoverable
  from either direction. Step 5.2.5 runs after provenance-strip
  (5.2) and before artifact-directory creation (5.3).
- Ordering invariant preserved: lint reads AFTER Phase 3
  sanitization (so `[REDACTED -- see foo]` doesn't shape-match)
  and AFTER provenance-strip (so `origin=...` is gone).
- Resynced `~/.claude/skills/session-handoff/SKILL.md`; verified
  via `diff`.

**Acceptance criteria:**
- [x] Phase 4 documents the placeholder lint (step 4j added).
- [x] Phase 5 references step 4j in its execution order (step
  5.2.5 added).
- [x] Regex targets only code-fence content; prose placeholders
  are explicitly out of scope.
- [x] Whitelist covers common HTML/Markdown literals that would
  otherwise false-positive (`<html>`, `<body>`, etc.).
- [x] Warning shape uses the canonical 3-segment format
  established in Phase 1 / Phase 2 / Phase 3.
- [x] Installed copy resynced.
- [ ] Runtime sanity check deferred — same posture as todo 001's
  sanity gate. A real-world `/session-handoff` invocation
  carrying a `<placeholder>` in its INSTRUCTIONS will exercise it.

**Learnings:**
- The lint runs at Phase 5 time but the spec lives in Phase 4 (as
  step 4j) because it's conceptually an assembly-phase
  post-processing pass, same pattern as step 4i (provenance
  strip). Phase 5's step list carries a forward-pointer step
  (5.2.5) so the execution order is readable chronologically.
- The whitelist is small but covers the realistic false-positive
  surface. A caller emitting non-HTML `<literal>` text inside a
  code fence (e.g. a generic parser demo) will get a spurious
  warning; the warning is advisory and non-blocking, so that's
  acceptable noise. Expand the whitelist in a follow-up if noise
  becomes a real problem.
- `<!--` HTML comments do not match the regex (starts with `!`,
  not `[A-Za-z]`), so they pass without needing explicit
  whitelist entries. Documented in 4j for future maintainers.

## Resources

- Triggering session: compound-engineering:ce-work for PR #3 of
  `newton20/agent-orchestration` on 2026-04-20.
- QA dispatch artifact:
  `~/.claude/handoffs/newton20-agent-orchestration/20260420-211104-assign-qa.md`
- QA report (received back): referenced in the coord's summary as
  Issue #3 under "Playbook typo."
- Related todos in this skill:
  - `001-complete-p2-per-type-short-prompt-soft-cap.md` — prior
    caller-ergonomics fix in the same skill.
  - `002-ready-p3-boundary-worked-cases-phase-4g.md` —
    documentation-tier follow-up.
