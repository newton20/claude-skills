---
status: ready
priority: p3
issue_id: "004"
tags: [session-handoff, phase-4, phase-5, truncation, placeholder-lint]
dependencies: ["003"]
---

# Re-check short-prompt cap after Phase 4j appends warnings

Phase 4j (placeholder lint) appends warnings AFTER the Phase 4g
truncation pass has already fit `SHORT_PROMPT` into its type-specific
hard cap. For a short prompt that is already at or near the cap, the
re-rendered `## Warnings` section (one new bullet per placeholder hit)
can push the emitted text back over the hard cap — breaking the cap
contract Phase 4g establishes.

## Problem Statement

Phase 4 ordering for a typical `assign` invocation:

1. Phase 4g renders the short prompt and applies truncation priority
   until the prompt fits under the `assign` hard cap (4500 chars).
2. Phase 4j scans the sanitized, provenance-stripped short prompt for
   placeholder tokens inside code segments.
3. If hits are found, Phase 4j appends one warning bullet per token
   and re-renders the `## Warnings` section.

The step-3 re-render grows the emitted short prompt. If step 1 had
left the prompt at (e.g.) 4480 chars, adding a 180-char warning bullet
produces a 4660-char emitted prompt that violates `assign`'s 4500 hard
cap. Phase 4g's truncation-priority rules (cut Plan reference → Status
→ Decisions body) are not re-run, so the cap contract silently breaks.

## Findings

- Empirically rare: most real `assign` short prompts sit ~2500-3500
  chars (well under the 4500 hard cap), and each placeholder warning
  adds ~130-180 chars. A prompt would need 4300+ chars AND at least
  one placeholder to breach.
- But: caps are a contract. "Sometimes the emitted prompt is over the
  cap" is qualitatively different from "always under" — downstream
  consumers (clipboard size assumptions, receiving-agent context
  budgeting) rely on the invariant.
- Surfaced by `/codex review` on PR #2 of `newton20/claude-skills`
  after the Phase 4j landing commit (2026-04-20/21).

## Proposed Solutions

### Option 1: Re-apply Phase 4g truncation after Phase 4j warnings

**Approach:** After Phase 4j's re-render step, if `SHORT_PROMPT`
now exceeds the type's hard cap, re-run the Phase 4g truncation
priority (tiers 1-3). If the prompt still exceeds after all three
cuts, fall through to the existing "stop cutting and emit as-is"
rule.

**Pros:** Preserves the cap contract under all conditions.
Reuses the existing truncation-priority machinery.

**Cons:** Doc-only complexity — Phase 4j now has a hidden
dependency on Phase 4g that needs to be navigable. The rule
"truncation-priority applies AFTER the placeholder lint when the
lint adds warnings" is non-obvious.

**Effort:** 20-30 min (prose addition in Phase 4j).

**Risk:** Low.

### Option 2: Run Phase 4j before Phase 4g

**Approach:** Swap the order so the placeholder lint runs BEFORE
the short prompt is truncated. Lint appends warnings → warnings
section is rendered normally by step 4h → Phase 4g truncates the
fully-assembled output.

**Pros:** Clean: one truncation pass, no re-check needed.

**Cons:** Violates todo 003's existing ordering invariant — the
lint is supposed to run AFTER Phase 3 sanitization so
`[REDACTED -- see foo]` tokens don't shape-match placeholders.
Swapping order would require either (a) running the lint against
pre-sanitized content (which loses the false-positive guarantee)
or (b) a more complex re-run-Phase-3 approach.

**Effort:** 1-2 hours (restructures Phase 4/5 ordering).

**Risk:** Medium — changes a load-bearing ordering invariant.

### Option 3: Accept the cap as a soft limit past the lint

**Approach:** Document that the hard cap is enforced up to Phase
4g, and that Phase 4j may add up to ~500 bytes of warning text on
top. Treat the cap as "hard cap for body; warnings may add
overhead."

**Pros:** Zero implementation cost.

**Cons:** Weakens the cap contract. Downstream consumers would
need to read the Phase 4j disclaimer to know the actual emitted
ceiling.

**Effort:** 10 min (disclaimer added to Phase 4g).

**Risk:** Low, but signals "cap is guidance, not contract" — bad
precedent for future tooling.

## Recommended Action

**Option 1.** The cap contract is load-bearing. Reusing Phase 4g's
existing truncation-priority machinery after Phase 4j's re-render
is the smallest change that preserves the invariant. The only
wrinkle is documentation: the Phase 4j prose needs one paragraph
explaining the "if the re-render pushes us over the cap, re-apply
step 4g's truncation-priority" rule.

## Technical Details

**Affected file (single):**
- `skills/session-handoff/SKILL.md` — Phase 4j prose (add the
  re-truncation paragraph after the re-render contract); Phase
  5.2.5 pointer (expand to mention the re-truncation pass).

**No code changes required** — the skill is LLM-executed prose.

**Related invariants preserved:**
- Phase 3 sanitization runs first (so `[REDACTED]` tokens don't
  shape-match).
- Phase 4i provenance-strip runs before the lint.
- Placeholder tokens THEMSELVES pass through unchanged; only the
  `warnings:` block and `## Warnings` section are modified by the
  lint.

## Resources

- **Trigger:** `/codex review` on PR #2 of `newton20/claude-skills`,
  second review round after the Phase 4j inline-span + re-render fix
  (commit `9122a56`). P2 finding: "Re-check short-prompt caps after
  adding placeholder warnings."
- **Related todos:**
  - `001-complete-*` — per-type soft-cap table (the cap contract
    this todo preserves).
  - `003-complete-*` — placeholder lint (Phase 4j, landed in PR #2).

## Acceptance Criteria

- [ ] Phase 4j prose documents that, after re-rendering the
  `## Warnings` section, if the short prompt exceeds the type's
  hard cap, Phase 4g's truncation priority (tiers 1-3) re-fires.
- [ ] The existing "stop cutting and emit as-is" fall-through rule
  still applies after the re-truncation pass if the prompt remains
  over cap.
- [ ] Phase 5.2.5 pointer is updated to mention the re-truncation.
- [ ] Installed copy at `~/.claude/skills/session-handoff/SKILL.md`
  is resynced.
- [ ] Commit + push. Does not need to block on this — P2 finding,
  rare in practice, can ship as its own small PR.

## Work Log

_(empty — will fill when the follow-up lands)_
