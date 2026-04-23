---
status: ready
priority: p3
issue_id: "006"
tags: [qa-plan, dogfood, eval, architecture]
dependencies: ["005"]
---

# A/B the /qa-plan pipeline vs codex's "one-hop" alternative during v0.1 dogfood

Surfaced by codex during outside-voice review of the `/qa-plan` design
(2026-04-22). Codex's core critique was that the whole skill may be
overbuilt — a simpler shape (`/session-handoff assign qa -- review the
diff, derive a test plan, run it, report findings`) might achieve the
same outcome with zero new code. User kept the richer shape but this
TODO captures the comparison that would make the decision evidence-based.

## Problem Statement

/qa-plan v0.1 ships with adversarial multi-persona review + codex
cross-model pass. The cost is ~30 min of skill-authoring work plus the
complexity of orchestrating 4-5 subagents on every run. The hypothesis
is that the adversarially-reviewed plan produces meaningfully better
QA outcomes than a fresh QA session deriving its own plan from scratch.

That hypothesis is currently unfalsifiable because we have no counterfactual
data.

## What to do

When /qa-plan v0.1 reaches dogfood stage (Next Step 12 of the design
doc, `session-handoff` v0.1 branch as target):

1. Run `/qa-plan` as designed. Capture the produced plan.
2. In a separate fresh session, run `/session-handoff assign qa -- review
   the session-handoff v0.1 diff, derive a test plan, run it, report
   findings back as /session-handoff report coord`. Capture what the
   one-hop agent produces.
3. Compare:
   - Does one plan catch bugs the other misses?
   - Does one take 2x longer / 3x more tokens for marginal quality?
   - Is the Top-10 overlap ≥ 7? (if yes, one-hop might be enough;
     if no, /qa-plan is doing something real)
4. Write findings to `docs/dogfood/001-qa-plan-vs-one-hop-findings.md`.
5. Decision gate for v0.2: if one-hop matches /qa-plan quality within
   20%, retire /qa-plan in favor of a taxonomy reference file that
   /session-handoff prompts cite (codex's recommendation).

## Exit criterion

A `docs/dogfood/` artifact with concrete comparison numbers + a v0.2
decision: keep /qa-plan, simplify, or retire.

## Dependencies

- TODO 005 (verify report-route) must be done first, since both arms of
  the A/B use the same handoff primitive.
- /qa-plan v0.1 must be implemented and ready for dogfood.

## Design doc reference

`~/.gstack/projects/claude-skills/REDMOND+dunliu-master-design-20260422-113136.md`
Review history / Outside-voice round / codex finding #1 + simpler shape
recommendation.
