---
status: complete
priority: p3
issue_id: "007"
tags: [qa-plan, eval, calibration, dogfood]
dependencies: []
unblocked_by: ["PR #4 — qa-plan v0.1 merged 2026-04-23"]
closed_by: "v0.3 (2026-04-24) — docs/qa-plans/human-baseline-session-handoff-v0.1.md"
---

# Author a human-generated test list for session-handoff v0.1 as eval baseline

Surfaced during `/plan-eng-review` of the `/qa-plan` design (2026-04-22).
Without a human baseline, `/qa-plan` v0.1 Success Criterion 4 ("codex
catches at least one gap the personas missed") is subjective.

## Problem Statement

`/qa-plan` v0.1's acceptance test is: run it on `session-handoff` v0.1
and inspect output. But "does the plan's Top-10 include the right tests"
requires a ground truth. Currently: none.

A human-authored test list for session-handoff v0.1 closes that gap.
Time-boxed: 30 minutes of domain thinking produces a list of 10-20 cases
the author believes are the most important to test for session-handoff
v0.1. That list becomes the eval baseline.

During dogfood of /qa-plan:
- Overlap ≥ 7 with the human list → personas + codex are catching the
  right things. Ship with confidence.
- Overlap 4-6 → marginal quality. Tune prompts or cut losses.
- Overlap ≤ 3 → something is wrong with the adversarial framing.
  Don't ship /qa-plan v0.1 until it produces a useful Top-10.

## What to do

Before /qa-plan v0.1 dogfood (ideally before implementation, to avoid
motivated reasoning):

1. Create `docs/eval-baselines/session-handoff-v0.1-test-list.md`.
2. Author the human list. Be specific: each case has a description,
   severity (1-5), likelihood (1-5), risk dimension (contract /
   state-transition / migration / privilege / cross-surface).
3. Do not share with /qa-plan during its development — prevents
   the author from optimizing personas for the baseline.
4. During dogfood, load both lists and compute Top-10 overlap.

## Exit criterion

`docs/eval-baselines/session-handoff-v0.1-test-list.md` exists with
≥ 15 cases tagged with severity/likelihood/risk-dimension.

**Resolution (2026-04-24, v0.3):** baseline lives at
`docs/qa-plans/human-baseline-session-handoff-v0.1.md` (path
chosen for proximity to existing `docs/qa-plans/` artifacts; the
exit-criterion path was advisory pre-implementation). 20 cases
(top 10 + 10 supplementary) tagged with severity, likelihood, and
risk-dimension. Authoring constraints documented in the file
header: 30-min time box, single-pass read, no tooling access,
honest-to-the-clock priority cuts.

## Dependencies

None. Should be authored before /qa-plan v0.1 implementation completes.

## Design doc reference

`~/.gstack/projects/claude-skills/REDMOND+dunliu-master-design-20260422-113136.md`
Success Criterion 4 + Test plan artifact (eng-review round).
