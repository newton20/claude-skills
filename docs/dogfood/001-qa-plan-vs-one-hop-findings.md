---
title: "/qa-plan vs codex one-hop A/B — framework + analysis"
type: dogfood
status: in-progress (one-hop run requires user-driven fresh session)
date: 2026-04-24
target: session-handoff v0.1 (commits 6f76e74..d70403e)
todo: docs/todos/006-in-progress-p3-ab-test-qa-plan-vs-one-hop-during-dogfood.md
human_baseline: docs/qa-plans/human-baseline-session-handoff-v0.1.md
qa_plan_reference_runs:
  - docs/qa-plans/20260423-095733-dogfood-qa-plan-v0.1-target-qa-plan.md
  - docs/qa-plans/20260423-221948-master-qa-plan.md
  - docs/qa-plans/20260423-232637-test-qa-plan-slug-verify-qa-plan.md
  - docs/qa-plans/20260424-205535-master-qa-plan.md
---

# `/qa-plan` vs codex one-hop A/B — framework + analysis

## Premise

Codex's outside-voice review of the `/qa-plan` v0.1 design (2026-04-22)
proposed a **one-hop alternative** that skips `/qa-plan` entirely:

```
/session-handoff assign qa -- review the diff at <commit>..<commit> for
<repo>, derive a test plan, run the plan in this session, report findings
back as /session-handoff report coord
```

Zero new code. The fresh QA session does plan + execute + report in
one pass, leaning on the already-shipped session-handoff skill.

The decision gate (v0.1 plan, line 760 / 720): **if the one-hop
matches `/qa-plan` quality within 20%, retire `/qa-plan` in favor of
a taxonomy reference file the QA prompt cites.** This document
captures the framework for that comparison, the analysis of the
existing `/qa-plan` reference data, and the user-action required to
collect the one-hop side.

## Methodology

### Comparison axes

For each side (one-hop, `/qa-plan`, human baseline), we compare:

1. **Top-10 overlap with human baseline.** The human baseline at
   `docs/qa-plans/human-baseline-session-handoff-v0.1.md` is the
   ground-truth reference. Two cases match if they cover the same
   root failure mode, even if the exact wording differs. Scoring:
   ≥ 7/10 overlap is good signal; < 4/10 means the system misses
   real bugs the domain expert catches.
2. **Top-10 overlap with each other.** Cross-system overlap (one-
   hop vs `/qa-plan` Top-10) measures whether the two pipelines
   converge on the same Top-10 cases or diverge on signal.
3. **Unique cases per system.** Cases each system catches that the
   other does not — this is the "value-add" measure. If `/qa-plan`'s
   unique cases all rank below sev×lik=12, the multi-agent pipeline
   buys little beyond the one-hop.
4. **Cost.** Wall-clock time, token consumption, dollar cost per
   run. Pulled from `~/.gstack/analytics/skill-usage.jsonl` for
   `/qa-plan` (already populated for 4 runs); user notes for
   one-hop (no analytics integration).

### Quality scoring rubric

For each Top-10 case, score 0/1/2:
- **0** — case is not in the comparator's output at all
- **1** — comparator catches the same root failure mode, but
  understates severity, misses a key risk dimension, or buries it
  outside the Top-10
- **2** — comparator catches the same case AND ranks it
  comparably (within 1 Top-10 position) AND tags risk dimensions
  consistently

Aggregate: max 20 per side per axis. Compute **percent-match** as
`score / 20`. Decision rule per the v0.1 plan: **if `(one-hop
percent-match) / (/qa-plan percent-match) ≥ 0.80`, retire
`/qa-plan`**. Below 0.80, the multi-agent pipeline pays for itself.

## Available data

### `/qa-plan` reference runs (4 datasets)

| Run | Date       | Target                       | Surface       | Top-10 sev×lik high | Codex C4 |
|-----|------------|------------------------------|---------------|---------------------|----------|
| #1  | 2026-04-23 | `/qa-plan` v0.1 (dogfood)    | claude-skill  | 20 (Codex prompt heredoc) | PASS 5/10 |
| #2  | 2026-04-23 | `/qa-plan` v0.1 (self-review on master) | claude-skill | 25 (jq -n missing -c, observed live) | PASS 2/10 |
| #3  | 2026-04-23 | `/qa-plan` slug-verify branch | claude-skill | 25 (mirror drift after Phase 4 Edit) | PASS 1+/10 |
| #4  | 2026-04-24 | `/qa-plan` v0.2 (PR #9 merge self-review) | claude-skill | 20 (5 cases tied) | PASS 2/10 |

**Important caveat:** all 4 runs target `/qa-plan` itself (self-
review), not session-handoff v0.1. The original v0.1 plan called
for a `/qa-plan` run against session-handoff v0.1 to A/B against
one-hop on the same target. **That run does not yet exist.** The
4 reference runs are useful for cost / Criterion-4 / cross-run
methodology metrics, but the head-to-head session-handoff
comparison requires a 5th `/qa-plan` run.

### Human baseline (1 dataset)

`docs/qa-plans/human-baseline-session-handoff-v0.1.md` — 30-min
time-boxed authoring against session-handoff v0.1, 20 cases listed,
top 10 cut explicit. Authored 2026-04-24 by the v0.3 implementation
agent.

### One-hop reference run (0 datasets — REQUIRES USER ACTION)

The one-hop must run in a **fresh Claude Code session** to preserve
the same context-separation property `/qa-plan` was designed
around. Cannot be spawned from the v0.3 implementation session.

## User-action required to complete the A/B

To run the head-to-head, the user runs **two** commands in **two
separate fresh Claude Code sessions** with the repo checked out at
the session-handoff v0.1 endpoint (commit `d70403e`):

### Session A — `/qa-plan` reference run

```
git checkout d70403e  # session-handoff v0.1 endpoint
/qa-plan
```

Captured output: `docs/qa-plans/{TS}-{branch}-qa-plan.md` (the
REVIEWED plan with Top-10).

### Session B — one-hop alternative

```
/session-handoff assign qa -- review the diff at 6f76e74..d70403e
for skills/session-handoff/, derive a test plan, run the plan in
this session, report findings back as /session-handoff report
coord
```

Captured output: whatever the one-hop session writes — likely a
plain-text Top-10 in the conversation transcript, plus the
`report coord` artifact at `~/.claude/handoffs/{slug}/...`.

### What to collect for the comparison

For each session, capture:
- Wall-clock time (start to "done" message)
- Token usage (final `/cost` if available)
- Dollar cost (final `/cost` if available)
- The Top-10 case list (extracted into the comparison table below)
- Risk-dimension tags per case
- Subjective notes on perceived quality / confidence

Once both runs are complete, fill in the comparison tables below
and compute the percent-match scores.

## Pre-comparison observations from the 4 self-review runs

These observations apply to `/qa-plan` itself and inform what we
expect to see in the head-to-head:

1. **Codex Criterion 4 lock-in is real.** 4 of 4 consecutive runs
   PASS — codex contributed at least one unique case at sev×lik
   ≥ 12 with < 50% token overlap with persona output, every time.
   This is direct evidence the cross-model pass adds signal not
   reachable from same-model personas. Predicted impact on A/B:
   if the one-hop only uses one model (Claude), it loses the
   cross-model dimension. Expect `/qa-plan`'s Top-10 to include
   2-3 cases the one-hop would miss.
2. **Self-catching is real.** Run #2 caught the live `jq -n` /
   `jq -nc` bug at sev×lik=25 — the highest-severity case in any
   run. Run #4 caught two more bugs in itself (spec-bundle stub,
   warning emission divergence). The compound-review architecture
   demonstrably surfaces bugs the impl-aware draft missed. The
   one-hop has no equivalent: the same agent that drafts the plan
   also runs it, so blind-spots in the draft transfer to the
   execution.
3. **Persona axis coverage is not free.** All 4 runs hit ≥ 4 risk
   dimensions in the Top-10 (contract / state-transition /
   migration / privilege / cross-surface). The Run #1 Confused-
   User finding ("accidental hard-gate framing") is exactly the
   kind of case a single-model one-hop would miss because it's
   not adversarial against the prompt — it's adversarial against
   the *natural-coworker register* the implementer's voice
   defaults to.
4. **Spec-only adds top-of-Top-10 cases.** Runs #3, #4 had
   `source: spec-only + impl-aware` cases occupying the #1 / #2
   Top-10 slots — pre-validated agreement is a strong signal.
   The one-hop has no spec-only equivalent (it reads everything
   at once).

These observations give a **hypothesis: `/qa-plan` will retain
its multi-agent pipeline.** The Run #2 self-catch alone is
evidence the pipeline is doing real work. The A/B will quantify
the margin.

## Comparison tables (TO BE FILLED ONCE ONE-HOP RUNS)

### Table A — Top-10 overlap with human baseline

| Human baseline case (top 10)              | `/qa-plan` (Run #5) score | One-hop score |
|-------------------------------------------|---------------------------|---------------|
| 1. Sanitization library load failure      |                           |               |
| 2. Verbatim AWS-key / GitHub-PAT redact   |                           |               |
| 3. Phase 4j placeholder lint inline spans |                           |               |
| 4. Phase 2 grammar — `--` boundary        |                           |               |
| 5. Phase 2 message-type exact-match       |                           |               |
| 6. No-git-repo graceful degrade           |                           |               |
| 7. Detached HEAD                          |                           |               |
| 8. Multiple active plans                  |                           |               |
| 9. Phase 4g truncation cap                |                           |               |
| 10. Clipboard absent                      |                           |               |
| **TOTAL**                                 |                  / 20    |       / 20    |
| **Percent match**                         |                          %|              %|

### Table B — Cost per run

| Metric          | `/qa-plan` (Run #5) | One-hop |
|-----------------|---------------------|---------|
| Wall-clock      |                     |         |
| Total tokens    |                     |         |
| Dollar cost     |                     |         |

### Table C — Decision

- `/qa-plan` percent match: ____ %
- One-hop percent match: ____ %
- Ratio (one-hop / `/qa-plan`): ____
- **Decision per v0.1 plan rule:** if ratio ≥ 0.80, retire
  `/qa-plan` in favor of taxonomy reference file. Otherwise,
  `/qa-plan` stays.
- Decision: ____

## Status + next step

**Status: BLOCKED on user-driven fresh-session runs.**

The framework is complete; the human baseline is authored; the
analysis of the 4 self-review reference runs is captured. The
two missing data points are:

- **Run #5 of `/qa-plan`** against session-handoff v0.1 (commit
  `d70403e`)
- **One-hop run** against the same target

Both are user-driven fresh-session work — the v0.3 implementation
agent cannot spawn fresh Claude Code sessions on the user's machine
without losing the context-separation property both the A/B and the
skill itself depend on.

Once collected, fill in the tables above and update this doc's
`status:` frontmatter to `complete`. Cross-reference the decision
into `docs/dogfood/001-qa-plan-v0.1-findings.md` "v0.3 backlog"
and into the v0.4 plan if `/qa-plan` retires.

## Related

- TODO 006: `docs/todos/006-in-progress-p3-ab-test-qa-plan-vs-one-hop-during-dogfood.md`
- TODO 007: `docs/todos/007-in-progress-p3-author-human-test-list-for-session-handoff-v0.1.md` — closed by `human-baseline-session-handoff-v0.1.md`
- v0.1 plan decision-rule reference: `docs/plans/2026-04-22-001-feat-qa-plan-skill-plan.md` (Risk Matrix row "Personas drift into implementation-context bias", Future Considerations bullet on one-hop fallback)
