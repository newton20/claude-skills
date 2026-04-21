---
title: "fix: Re-apply Phase 4g truncation after Phase 4j appends placeholder warnings"
type: fix
status: active
date: 2026-04-21
origin: docs/todos/004-ready-p3-recheck-short-prompt-cap-after-placeholder-lint.md
---

# fix: Re-apply Phase 4g truncation after Phase 4j appends placeholder warnings

## Overview

Phase 4j (placeholder lint) appends warnings to `SHORT_PROMPT` AFTER Phase 4g has already fit the prompt under its per-type hard cap. When the lint re-renders the `## Warnings` section, the emitted short prompt can grow back over the cap, silently breaking the cap contract Phase 4g establishes. Fix: after Phase 4j's re-render, if the prompt exceeds the type's hard cap, re-apply Phase 4g's existing truncation priority (tiers 1–3). If still over cap after all three cuts, fall through to the existing "emit as-is" rule.

The change is doc-only — the skill is LLM-executed prose. Two locations in `skills/session-handoff/SKILL.md` change (Phase 4j prose and the Phase 5.2.5 pointer). The installed copy at `~/.claude/skills/session-handoff/SKILL.md` is resynced from the repo.

## Problem Frame

Phase 4 ordering for a typical `assign` invocation:

1. Step 4g renders the short prompt and applies truncation priority until the prompt fits under the `assign` hard cap (4500 chars).
2. Step 4j scans the sanitized, provenance-stripped prompt for placeholder tokens inside code segments.
3. On hits, step 4j appends one warning per token and re-renders the `## Warnings` section in both tiers.

The step-3 re-render grows the emitted short prompt. If step 1 had left the prompt at e.g. 4480 chars, adding a 180-char warning bullet produces a 4660-char emitted prompt that violates `assign`'s 4500 hard cap. Step 4g's cut rules are not re-run, so the cap contract silently breaks.

Empirically rare — most `assign` short prompts sit 2500–3500 chars and each warning adds ~130–180 chars. But the cap is a contract: downstream consumers (clipboard assumptions, receiving-agent context budgeting) rely on the invariant holding always, not usually.

Surfaced by `/codex review` on PR #2 (`newton20/claude-skills`) after the Phase 4j inline-span + re-render fix landed (commit `9122a56`).

## Requirements Trace

- R1. Phase 4j prose documents that, after re-rendering `## Warnings`, if `SHORT_PROMPT` exceeds the type's hard cap, step 4g's truncation priority (tiers 1–3) re-fires.
- R2. The "stop cutting and emit as-is" fall-through remains the terminal behavior when the prompt still exceeds after all three cuts.
- R3. The Phase 5.2.5 execution-order pointer mentions the re-truncation pass so the chronological reader sees it.
- R4. Installed copy at `~/.claude/skills/session-handoff/SKILL.md` is resynced from `skills/session-handoff/SKILL.md`.

(Maps directly to the four non-administrative acceptance criteria in the origin todo.)

## Scope Boundaries

- No change to the Phase 4g truncation-priority tiers themselves (cut order and always-keep list are preserved).
- No change to the Phase 4j regex, whitelist, warning shape, or dedup rule.
- No change to the ordering invariant with Phase 3 sanitization (lint still runs after Phase 3 and after 4i provenance-strip).
- No change to `FULL_ARTIFACT` — the artifact has no cap, so warning re-renders on that tier cannot breach anything.
- No behavior change for invocations that add zero placeholder warnings (the lint already skips the re-render in that case).

## Context & Research

### Relevant Code and Patterns

- `skills/session-handoff/SKILL.md:830–924` — Phase 4g "Short-prompt truncation priority" with the per-type caps table, tier 1–3 cut rules, always-keep list, and the terminal "emit as-is" rule. The re-truncation in this plan reuses this prose — it does not restate the tiers.
- `skills/session-handoff/SKILL.md:982–1108` — Phase 4j "Placeholder lint", specifically the "Re-render the warnings sections after appending" block (lines ~1056–1078) which is the insertion point for the new re-truncation contract.
- `skills/session-handoff/SKILL.md:1139–1150` — Phase 5.2.5 pointer to step 4j; currently mentions the scan, whitelist, and re-render. Needs one additional line about re-truncation.

### Institutional Learnings

- Todo 001 (per-type caps) established that the cap is a per-type contract, not a soft suggestion. Todo 002 (boundary worked cases) established that worked cases ARE the runtime test suite for instruction-prose skills. Both treatments are preserved here — this fix does not invalidate any existing worked case and does not require a new one.
- Todo 003 (Phase 4j) established the ordering invariant: lint runs AFTER Phase 3 sanitization and AFTER 4i provenance-strip. This plan preserves that invariant — the re-truncation happens strictly after the lint's re-render, within the same Phase 5 execution window.

### External References

None. The change is internal to a single skill file.

## Key Technical Decisions

- **Re-use Phase 4g's cut machinery verbatim** (rather than introduce a new truncation path in Phase 4j). Rationale: single source of truth for cut rules, no risk of drift between the two spec locations, minimal prose addition.
- **Re-truncation runs only when the lint appended ≥1 warning**. Rationale: Phase 4j already skips the re-render on zero hits (`SKILL.md:1073–1074`); the re-truncation inherits the same guard. Zero-hit invocations incur no extra work.
- **Preserve the "emit as-is" fall-through**. Rationale: the terminal rule in Phase 4g already handles the pathological case where no cut brings the prompt under cap (e.g., `assign`/`review`/`report` where cuts are structurally no-ops per step 4d). Re-invoking step 4g naturally inherits this fall-through without new prose.
- **Do NOT re-truncate `FULL_ARTIFACT`**. Rationale: the artifact has no cap (per step 4h). Re-rendering the artifact's warnings block is fine; no further action needed for that tier.
- **No new worked case required**. Rationale: the existing Phase 4j worked case (single inline span, single token) already exercises the re-render path; adding the re-truncation rule does not introduce a new observable behavior to demonstrate unless the user exercises a pathological >4300-char prompt with a placeholder. Note this explicitly as deferred so a future maintainer can add a worked case if invocations ever surface one.

## Open Questions

### Resolved During Planning

- **Q: Swap Phase 4j and Phase 4g order instead?** No. That was Option 2 in the origin todo and was rejected there: it violates the "lint runs after Phase 3 sanitization" invariant from todo 003.
- **Q: Treat the cap as soft past the lint?** No. That was Option 3 and weakens the cap contract; todo 004 rejected it.
- **Q: Do we need a new worked case?** Not required for correctness. Deferred; see below.

### Deferred to Implementation

- Exact prose wording of the re-truncation paragraph (inline vs. nested bullet list in step 4j). The implementer should pick the form that reads most naturally next to the existing "Re-render the warnings sections after appending" block.
- Whether to add a fifth worked case in Phase 4g showing `assign` at 4480 chars → post-lint 4660 chars → re-truncation fires → emit-as-is. Optional polish; defer unless invocations surface the pathological case in practice.

## Implementation Units

- [x] **Unit 1: Document the re-truncation pass and update the execution-order pointer**

  **Goal:** Add prose to Phase 4j that re-applies Phase 4g's truncation priority when the lint's re-render pushes `SHORT_PROMPT` back over the type's hard cap, and update the Phase 5.2.5 pointer so chronological readers see the same contract. Resync the installed copy.

  **Requirements:** R1, R2, R3, R4

  **Dependencies:** None

  **Files:**
  - Modify: `skills/session-handoff/SKILL.md` (Phase 4j re-render block around line 1056–1078; Phase 5.2.5 pointer around line 1139–1150)
  - Modify: `~/.claude/skills/session-handoff/SKILL.md` (resync from repo copy — the install target, not version-controlled)
  - Test: none — instruction-prose skill, no test file

  **Approach:**
  - In Phase 4j, immediately after the existing "Re-render the warnings sections after appending" block (currently ending with "both tiers need the updated section to stay consistent"), add a new sub-block:
    - Heading-style cue consistent with the surrounding prose (e.g., bolded lead-in like `**Re-check the short-prompt cap after re-rendering.**`).
    - One paragraph stating: if the re-rendered `SHORT_PROMPT` exceeds `MSG_TYPE`'s hard cap per the step 4g table, re-apply step 4g's truncation priority (tier 1 → tier 2 → tier 3) against the re-rendered `SHORT_PROMPT`. If the prompt still exceeds after all three cuts, the existing step 4g fall-through applies: stop cutting and emit as-is.
    - One sentence restating scope: `FULL_ARTIFACT` is never capped, so no re-truncation on that tier. Zero-warning invocations skip this step entirely (inherits the existing re-render guard).
    - Explicit cross-reference back to step 4g so the reader can find the cut rules without restating them.
  - In Phase 5.2.5, extend the existing summary so the final sentence (currently `"See step 4j for the full regex, whitelist, warning shape, and re-render contract."`) also mentions the re-truncation pass, e.g., `"...re-render contract, and post-lint re-truncation."`
  - Resync the installed copy: copy `skills/session-handoff/SKILL.md` over `~/.claude/skills/session-handoff/SKILL.md`. Verify with `diff` that the two files are byte-identical after the copy.

  **Patterns to follow:**
  - `skills/session-handoff/SKILL.md:1056–1078` — the existing "Re-render the warnings sections after appending" block is the structural model for the new re-truncation block (bolded lead-in + explanatory paragraph + invariant line).
  - The cross-reference pattern "See step 4X for ..." is already used throughout Phase 5 pointers (e.g., step 5.2.5's trailing sentence). Reuse verbatim.

  **Test scenarios:**
  - Happy path (prose review): reading Phase 4j top-to-bottom, the re-truncation rule follows the re-render rule naturally and references step 4g's tiers rather than duplicating them.
  - Happy path (prose review): reading Phase 5 top-to-bottom, step 5.2.5 now advertises four Phase-4j behaviors (scan, whitelist, warning shape, re-render, re-truncation — five if counted individually).
  - Edge case (prose review): an invocation that appends zero warnings — the prose makes clear this step is skipped, no extra work performed.
  - Edge case (prose review): an invocation where re-rendering the warnings section does NOT push the prompt back over the cap — the prose makes clear the re-truncation is conditional on the cap check, not unconditional.
  - Edge case (prose review): `assign` / `review` / `report` where all three cut tiers are structurally no-ops per step 4d — the prose makes clear the terminal "emit as-is" rule from step 4g still applies, which is exactly what the reader wants.
  - Integration (file sync): `diff skills/session-handoff/SKILL.md ~/.claude/skills/session-handoff/SKILL.md` produces no output after resync.

  **Verification:**
  - Phase 4j contains a re-truncation sub-block located after the re-render block and before the `**Invariant.**` paragraph or the worked case (implementer picks the exact insertion point).
  - Phase 5.2.5's trailing sentence enumerates the re-truncation alongside the re-render contract.
  - The repo SKILL.md and the installed SKILL.md are byte-identical.
  - No other Phase 4g, Phase 4h, Phase 4i, or Phase 5 section changed (the fix is confined to the two edit points).

## System-Wide Impact

- **Interaction graph:** No runtime interaction graph change. The skill already runs step 4g and step 4j in the documented order; this fix adds a conditional re-entry from step 4j back into step 4g's cut logic.
- **Error propagation:** No new failure modes. The re-truncation reuses step 4g's machinery, which already has the "emit as-is" fall-through for pathological cases.
- **State lifecycle risks:** None. No persisted state, no file-system impact beyond the one installed-copy resync.
- **API surface parity:** None — internal spec change, no externally observable command/flag/schema change.
- **Integration coverage:** Covered by the sanity-invocation acceptance criterion in todo 004 (any real `/session-handoff` invocation carrying a placeholder in INSTRUCTIONS exercises the path).
- **Unchanged invariants:** Phase 3 sanitization still runs first; step 4i provenance-strip still runs before the lint; the lint still scans AFTER sanitization and AFTER provenance-strip and BEFORE output. Placeholder tokens themselves still pass through unchanged. The per-type caps table, tier 1–3 cut rules, always-keep list, and emit-as-is fall-through are all preserved verbatim.

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Prose becomes dense / hard to follow in Phase 4j | Keep the re-truncation block short (~3 sentences); cross-reference step 4g rather than restating cut rules. |
| Implementer forgets the installed-copy resync | Explicit in Unit 1's Files list and Verification bullet. Integration test scenario is the `diff` check. |
| Future maintainer edits step 4g cut rules without checking step 4j | The cross-reference + the shared "emit as-is" terminal rule mean step 4j inherits step 4g's updates automatically. No duplication to drift. |

## Documentation / Operational Notes

- No user-facing changelog entry required — this is internal spec tightening, not observable behavior change (the rare pathological case was the only observable, and most users will not hit it).
- The origin todo's work log is still empty; the implementer should update it during implementation per the work-log pattern established in todos 001–003.
- After the PR lands, flip the origin todo's filename prefix from `004-ready-*` to `004-complete-*` and its frontmatter `status: ready` → `status: complete`, matching the convention used by todos 001–003.

## Sources & References

- **Origin document:** [docs/todos/004-ready-p3-recheck-short-prompt-cap-after-placeholder-lint.md](../todos/004-ready-p3-recheck-short-prompt-cap-after-placeholder-lint.md)
- **Related plan:** [docs/plans/2026-04-15-001-feat-session-handoff-skill-plan.md](./2026-04-15-001-feat-session-handoff-skill-plan.md) — original session-handoff skill design.
- **Related todos (landed):**
  - `docs/todos/001-complete-p2-per-type-short-prompt-soft-cap.md` — per-type caps table (the contract this fix preserves).
  - `docs/todos/002-complete-p3-boundary-worked-cases-phase-4g.md` — boundary worked cases in Phase 4g.
  - `docs/todos/003-complete-p3-session-handoff-placeholder-vs-literal-sanitization.md` — Phase 4j placeholder lint (the step this fix extends).
- **Triggering review:** `/codex review` on PR #2 of `newton20/claude-skills`, second review round after commit `9122a56` (Phase 4j inline-span + re-render fix).
- **Affected files:**
  - `skills/session-handoff/SKILL.md:982–1108` (Phase 4j)
  - `skills/session-handoff/SKILL.md:1139–1150` (Phase 5.2.5)
