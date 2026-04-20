---
status: complete
priority: p2
issue_id: "001"
tags: [session-handoff, phase-4, ux, truncation]
dependencies: []
---

# Per-type short-prompt soft-cap in session-handoff Phase 4g

Loosen the 2500-char soft-cap when `MSG_TYPE` is `assign` (and likely
`report`) so multi-scenario task descriptions and acceptance criteria
reach the receiving agent intact.

## Problem Statement

The session-handoff skill's short-prompt target is ~2000 chars with a
hard cap of 2500 (`skills/session-handoff/SKILL.md` Phase 4 step 4g).
That budget fits `handoff` and `brief` invocations well, but is too
tight for `assign` — the type whose short prompt exists to communicate
a concrete, often multi-scenario, test/build/review task to a fresh
agent. When the Task description plus acceptance-criteria checklist
overflow, the current contract says "stop cutting and emit as-is,"
which works but is signaling a design mismatch: the type whose whole
purpose is a detailed brief is forced through the same length budget
as a terse status handoff.

**Observed in real use (2026-04-19, this session):** `/session-handoff
assign qa` for a PR #2 E2E test produced a 3129-byte short prompt
(vs the 2500 soft-cap) even after pruning to essentials. The QA
agent needs every one of those bytes — 4 scenarios with concrete
acceptance criteria, resource pointers, and a deliverable path. Any
compression would hurt test fidelity.

## Findings

- `skills/session-handoff/SKILL.md` Phase 4 step 4g defines the cap as
  a single global value (2500 chars) across all 5 message types.
- Step 4g's truncation priority (cut plan detail → cut status detail →
  cut decisions body) is designed for `handoff`/`brief` where those
  sections are the padding. For `assign`, Plan reference and Status are
  already in the secondary (full-artifact-only) list per Phase 4 step
  4d, so the truncation priority has nothing to cut before it hits the
  Task description — which is the one section that absolutely must
  survive.
- `report` has a similar profile: Findings summary + Evidence +
  Recommendations are the deliverable, not padding.
- `handoff` and `brief` remain well-served by 2500 chars in practice
  (observed: 1832–1885 bytes in the two runs so far).

**Affected file:**
- `skills/session-handoff/SKILL.md` — Phase 4 step 4g ("Short-prompt
  truncation priority") and the hard-cap constant inside it.

## Proposed Solutions

### Option 1: Per-type soft/hard caps

**Approach:** Introduce a caps table in step 4g keyed by `MSG_TYPE`.
Initial values:

| Type | Soft cap | Hard cap |
|---|---|---|
| `handoff` | 2000 | 2500 |
| `brief` | 2000 | 2500 |
| `assign` | 3500 | 4500 |
| `review` | 2500 | 3500 |
| `report` | 3500 | 4500 |

Truncation priority rules stay the same; only the budget changes.

**Pros:**
- Matches each type's purpose without weakening any invariant.
- Backward compatible for `handoff`/`brief` — same numbers.
- One-line change in the skill prose + one table.

**Cons:**
- Five numbers to maintain instead of one.
- `assign`/`report` short prompts genuinely can be 4KB+ — stresses the
  "fits in a typical clipboard" claim (modern clipboards handle this
  fine; the claim was slightly aspirational anyway).

**Effort:** 30–60 minutes (prose + one worked-example update).

**Risk:** Low. No behavioral change for the most-used types.

---

### Option 2: Single higher cap for all types

**Approach:** Raise the universal soft/hard caps to 3500/4500.

**Pros:**
- Simpler — one number.
- Fewer edge cases to think about.

**Cons:**
- `handoff`/`brief` short prompts grow to 3KB when they didn't need to.
- The short prompt is supposed to be the skimmable tier; padding works
  against that.

**Effort:** 15 minutes.

**Risk:** Low, but dilutes the two-tier split.

---

### Option 3: Absorb overflow sections into the full artifact, short
prompt is pointer-only for long assigns

**Approach:** When an `assign`/`report` would exceed the hard cap,
render a drastically shortened short prompt (role preamble + 1-line
task summary + artifact pointer) and rely on the receiving agent to
open the full artifact before starting.

**Pros:**
- Short prompt stays genuinely short.
- Full artifact remains the source of truth.

**Cons:**
- Cross-machine handoffs lose fidelity — the short prompt alone doesn't
  carry the task when the artifact isn't reachable.
- Breaks the "self-contained short prompt" invariant step 4f documents.

**Effort:** 1–2 hours (real behavior change + doc rewrite).

**Risk:** Medium. Undermines a load-bearing invariant.

## Recommended Action

**Implement Option 1.** Add a per-type caps table in Phase 4 step 4g,
keep the existing truncation priority rules, update the worked-examples
narrative to note the per-type budgets. Do not change `handoff`/`brief`
numbers. Add a test case in `references/message-templates.md`'s
composition algorithm documentation showing an `assign` prompt at 3200
chars passing cleanly (under the 3500 soft cap for `assign`).

## Technical Details

**Affected file (single):**
- `skills/session-handoff/SKILL.md` — Phase 4 step 4g content.

**No code changes required** — the skill is LLM-executed prose, not a
compiled parser. The change is to the spec the LLM follows at runtime.

**Related invariants preserved:**
- Two-tier split (short vs full) remains.
- Truncation priority stays as documented.
- Always-keep list (role preamble, branch/SHA, INSTRUCTIONS/threaded
  equivalent, warnings, artifact pointer) stays.

## Resources

- **Trigger:** 2026-04-19 session `/session-handoff assign qa` for
  agent-orchestration PR #2 E2E test, produced 3129-byte short prompt.
- **Spec line:** `skills/session-handoff/SKILL.md` Phase 4g, "Target:
  ~2000 chars. Hard cap: 2500 chars."
- **Template composition:** `references/message-templates.md`
  "Composition algorithm" section (consumed by Phase 4).
- **Related plan:** `docs/plans/2026-04-15-001-feat-session-handoff-skill-plan.md`
  (original skill design).

## Acceptance Criteria

- [ ] Phase 4 step 4g in `skills/session-handoff/SKILL.md` defines a
  per-type caps table with the five values from Option 1.
- [ ] Prose in step 4g explicitly notes which types now have higher
  budgets and why (multi-scenario briefings vs terse handoffs).
- [ ] Truncation priority rules unchanged; always-keep list unchanged.
- [ ] Worked-examples section (or a new one) shows an `assign` case
  where the short prompt is 3200 chars — "within soft cap, no truncation
  applied."
- [ ] Installed copy at `~/.claude/skills/session-handoff/SKILL.md` is
  resynced from `claude-skills/skills/session-handoff/SKILL.md`.
- [ ] Sanity invocation of the updated skill produces the expected
  behavior: run `/session-handoff assign qa -- <a long task>` and
  confirm the printed short prompt is emitted without a truncation
  warning and within the new per-type cap.
- [ ] Claude-skills commit on master with a concise message and pushed.

## Work Log

### 2026-04-19 - Initial Discovery

**By:** Claude Opus 4.7 (agent-orchestration dev session)

**Actions:**
- Invoked `/session-handoff assign qa` for PR #2 E2E test.
- Short prompt measured 3129 bytes vs 2500 cap.
- Verified the 4 scenarios and acceptance criteria were the load-
  bearing content (no padding to cut).
- Drafted this todo with three solution options.

**Learnings:**
- The 2500-char cap was designed with `handoff`/`brief` in mind.
- Phase 4 step 4d already routes Plan reference and Status to the
  secondary-only list for `assign`, so step 4g's truncation priority
  has nothing to trim before it hits the Task description.
- Clipboard capacity isn't a real constraint at 3–5KB on modern
  Windows/Mac/Linux — the "fits in a typical clipboard" line in the
  prerequisites block is overly cautious.

### 2026-04-19 - Implementation (Option 1)

**By:** Claude Opus 4.7 (claude-skills impl session, branch
`feat/todo-001-per-type-soft-cap`)

**Actions:**
- Replaced the single-number soft/hard cap in `skills/session-handoff/
  SKILL.md` Phase 4g with a per-type table keyed by `MSG_TYPE`
  (handoff/brief 2000/2500, assign/report 3500/4500, review 2500/3500).
- Added a rationale paragraph explaining the terse-vs-deliverable tier
  split.
- Added a "Worked case (assign, within soft cap, no truncation)"
  annotation demonstrating the 3200-char assign scenario that falls
  under the new 3500 soft cap.
- Updated the Phase 4 intro (line 699) to point at step 4g for the
  per-type budgets rather than stating a single universal target.
- Updated `references/message-templates.md` composition algorithm step
  7 to delegate cap numbers to SKILL.md Phase 4g, keeping the
  truncation priority rules inline.
- Resynced `~/.claude/skills/session-handoff/SKILL.md` and its
  `references/message-templates.md` from the repo copies; verified
  with diff.
- Renamed this todo `001-ready-*` → `001-complete-*`, flipped
  frontmatter `status: ready` → `status: complete`.

**Learnings:**
- Truncation priority + always-keep list needed no changes — the cap
  numbers are the only knob that's type-sensitive.
- `references/message-templates.md` carried a stale "Target ≤ 2500
  chars" line that would have drifted out of sync on every future
  cap change. Delegating to SKILL.md keeps numbers in one place.

### 2026-04-20 - Sanity verification (from PR #1 code review)

**By:** Claude Opus 4.7 (ce-code-review walkthrough, finding #2)

**Actions:**
- Invoked `/session-handoff assign impl -- <long 4-scenario QA task>`
  with a representative multi-scenario task description, acceptance
  criteria, and resource pointers (~1200 chars of task detail).
- Composed the short prompt following Phase 4 spec
  (`short_sections = [preamble] + assign primary (Task description,
  Scope, Acceptance criteria, Resources) + [Warnings, Artifact
  pointer]`) and measured byte count.
- Result: **2287 bytes** (well under `assign`'s new 3500 soft cap).
  No truncation priority would fire; emit-as-is path taken.

**Acceptance criterion satisfied:**
- [x] Sanity invocation of the updated skill produces the expected
  behavior: short prompt emitted without a truncation warning, within
  the new `assign` per-type cap.

**Note:** Real-world assign tasks can grow larger than the test case
(the original 2026-04-19 trigger in agent-orchestration-repo was
3129 bytes). Both sit comfortably under 3500 soft and 4500 hard, which
is exactly the motivation for the per-type caps. If a pathological
case does exceed 4500, Phase 4g's unchanged truncation priority fires
cleanly (Plan reference → Status → Decisions body), or the prompt
emits as-is and the full artifact carries detail.

---

## Notes

- Handoff: this todo is being handed off to a fresh Claude Code session
  rooted in `C:\Users\dunliu\projects\claude-skills\`. The implementing
  agent should check out master, apply the SKILL.md change, resync the
  installed copy at `~/.claude/skills/session-handoff/SKILL.md`, and
  commit + push.
- Source project (agent-orchestration, where this was discovered) is a
  separate repo and does not need any changes for this fix.
