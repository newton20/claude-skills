---
status: ready
priority: p3
issue_id: "002"
tags: [session-handoff, phase-4, worked-examples, documentation]
dependencies: ["001"]
---

# Boundary worked cases for Phase 4g per-type caps

Add worked cases covering the truncation-budget boundaries introduced
by todo 001's per-type caps table, so the prose rules are demonstrated
by example at every meaningful transition.

## Problem Statement

Todo 001 landed one worked case: a 3200-char `assign` short prompt
sitting under the new 3500 soft cap ("within soft cap, no truncation
applied"). The other boundaries in the caps table are documented in
prose only:

- **At the soft cap** (3500 for assign/report, 2500 for review, etc.):
  the prose says "soft cap is the targeted body length" but there's
  no example showing what "targeted" means when body size is exactly
  the soft-cap value — does truncation kick in at soft or hard?
- **Between soft and hard** (e.g., 3600–4499 for assign): transition
  zone. Current rule: "hard caps are the ceiling at which truncation
  priority kicks in" — so between soft and hard, emit as-is. No
  example demonstrates this.
- **At the hard cap** (4500 for assign/report): the truncation-priority
  cut rules fire. No example illustrates which sections get cut and
  in what order for the new per-type budgets.
- **Beyond the hard cap after all three cuts** (emit-as-is fallback):
  the old prose exercised this at 2500; now it only fires at 4500 for
  assign/report but is documented only by the rule "stop cutting and
  emit the prompt as-is." No worked case.

**Relates to:** Code review of PR #1, findings #1 (P1, testing) and
#4 (P2, testing), consolidated here per user walkthrough decision on
2026-04-20.

## Findings

- The single worked case in todo 001's implementation is at 3200 chars
  — comfortably under the soft cap. It demonstrates the most common
  path but not the interesting transitions.
- For instruction-prose skills with no compiled parser, worked cases
  ARE the runtime verification surface. Missing cases for the
  emit-as-is fallback especially matters because that path used to be
  exercised at 2500 (routine) and now only fires at 4500 for
  assign/report (rare), so real-world invocations rarely surface bugs
  in that code path if the prose is ambiguous.
- Review type is structurally most interesting: tiers 1 and 2 of the
  truncation priority are no-ops for review (Plan reference and Status
  are secondary-only per Phase 4 step 4d), so only tier 3 (Decisions /
  Open questions body) can actually fire. A worked case showing a
  review prompt hitting its 3500 hard cap and cutting Decisions body
  would make that subtlety legible.

**Affected file:**
- `skills/session-handoff/SKILL.md` — Phase 4 step 4g worked-cases
  section (currently one annotation; expand to 2–4 annotations).

## Proposed Solutions

### Option 1: Add one consolidated hard-cap + emit-as-is case

**Approach:** Add a second worked case to Phase 4g showing an `assign`
short prompt that hits the 4500 hard cap after all three cuts and
emits as-is. Answers the emit-as-is fallback gap (finding #4) in one
prose block.

**Pros:** Minimal scope creep; ~100 words; fills the most critical
gap (the fallback path that used to fire routinely).

**Cons:** Doesn't cover the review-type tier-3-only path, nor the
between-soft-and-hard transition zone.

**Effort:** 15–20 minutes.

**Risk:** Low.

---

### Option 2: Add one worked case per type class

**Approach:** Three additional worked cases:
1. An `assign` at 4500 (hard cap) → cuts fire in order, short prompt
   emitted as-is after all three.
2. A `review` at 3500 (hard cap) → tier 3 fires directly (tiers 1–2
   no-op for review's primary sections).
3. A `report` at 3700 (between soft and hard) → emitted as-is, no
   truncation, illustrates the transition zone.

**Pros:** Comprehensive coverage; each type's interesting boundary
is illustrated; prose rules become runtime-checkable via example.

**Cons:** Adds ~400 words to Phase 4g; prose density increases.

**Effort:** 45–60 minutes.

**Risk:** Low, but grows Phase 4g meaningfully.

---

### Option 3: Worked cases as a separate reference file

**Approach:** Move all worked cases (including the existing one from
todo 001) into `skills/session-handoff/references/worked-cases.md`.
Phase 4g links to the reference file. Each case gets its own section.

**Pros:** Keeps SKILL.md prose tight; worked cases can expand without
bloating the spec.

**Cons:** More indirection for the LLM executing the skill. The
existing worked case was deliberately placed inline next to the
truncation rules it illustrates — moving it loses that immediacy.

**Effort:** 1–2 hours.

**Risk:** Medium — structural split may hurt more than help for a
skill this small.

## Recommended Action

**Option 2 (preferred) or Option 1 (minimum).** If the per-type caps
table is the load-bearing design from todo 001, Option 2 makes the
invariants it encodes visible at every transition. If scope pressure
matters, Option 1 covers the most-regressed path (emit-as-is) and
leaves the transition-zone + review-tier-3 gaps for a later iteration.

## Technical Details

**Affected file (single):**
- `skills/session-handoff/SKILL.md` — Phase 4 step 4g, after the
  existing "Worked case (assign, within soft cap, no truncation)"
  annotation.

**No code changes required** — the skill is LLM-executed prose.

## Resources

- **Trigger:** PR #1 code review findings #1 + #4, session
  2026-04-20. Reviewer was `compound-engineering:ce-code-review`
  persona `testing` (P1 + P2 cross-severity).
- **Spec section:** `skills/session-handoff/SKILL.md` Phase 4 step 4g
  (landed in PR #1).
- **Related todo:** `docs/todos/001-complete-p2-per-type-short-prompt-soft-cap.md`.

## Acceptance Criteria

- [ ] Phase 4 step 4g in `skills/session-handoff/SKILL.md` includes at
  least one worked case demonstrating the emit-as-is fallback at the
  new hard cap (4500 for assign/report).
- [ ] If Option 2 is chosen: worked cases for all three transition
  states — at soft cap, between soft and hard, at hard cap after
  truncation — for at least one representative message type each.
- [ ] Review-type worked case illustrates that tier 3 (Decisions /
  Open questions body) is the only fireable cut for that type.
- [ ] Installed copy at `~/.claude/skills/session-handoff/SKILL.md` is
  resynced after the change.
- [ ] Commit on master with a concise message; pushed.

## Work Log

### 2026-04-20 - Created from PR #1 code review

**By:** Claude Opus 4.7 (ce-code-review walkthrough session)

**Actions:**
- User chose "Defer" for findings #1 and #4 during walkthrough of
  PR #1 code review.
- Created this todo to track the deferred boundary worked cases.
- Both findings share the same affected section (Phase 4g) and the
  same underlying concern (runtime verification via worked cases),
  so they consolidated cleanly into one follow-up.

**Learnings:**
- Testing reviewer's "worked cases are the runtime test suite for
  instruction-prose" framing was load-bearing. The old universal
  2500 cap used the emit-as-is fallback routinely in 3KB-ish
  handoffs; the new per-type caps make it a rare path for
  assign/report (only at 4500+), so a worked case becomes the only
  way a future maintainer sees the fallback prose is actually
  checked.
