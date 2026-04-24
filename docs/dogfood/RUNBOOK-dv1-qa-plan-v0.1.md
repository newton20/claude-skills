---
title: "Runbook — DV1: end-to-end /qa-plan dogfood against session-handoff v0.1"
type: runbook
status: pending
date: 2026-04-23
depends_on: PR #4 (merged 2026-04-23 as commit 2e5c809)
target_ac: [AC2, AC3, AC4, AC6, AC8, AC9, AC10, AC11]
output_landing: docs/dogfood/001-qa-plan-v0.1-findings.md (DV1-DV4 outcomes)
---

# Runbook — DV1: end-to-end `/qa-plan` dogfood

## Purpose

Runs the full `/qa-plan` v0.1 pipeline against the `session-handoff`
v0.1 shipped commits and confirms the handoff lands in a fresh
Claude Code session. Produces the missing runtime evidence for
ACs 2, 3, 4, 6, 8, 9, 10, 11 that the in-session dogfood (IV1-IV6)
could not cover.

## Before you start

Verify all of these are true. If any fails, the dogfood will also
fail — fix first.

```bash
# 1. You are in the claude-skills repo root
pwd | grep -q "claude-skills$" && echo "OK" || echo "FAIL: cd to claude-skills"

# 2. qa-plan skill is installed (live-link or copy per README)
ls ~/.claude/skills/qa-plan/SKILL.md >/dev/null 2>&1 && echo "OK" || echo "FAIL: install skills/qa-plan per README"

# 3. session-handoff skill is installed (required — qa-plan prints a /session-handoff command)
ls ~/.claude/skills/session-handoff/SKILL.md >/dev/null 2>&1 && echo "OK" || echo "FAIL: install skills/session-handoff per README"

# 4. codex CLI is authenticated (optional — fallback chain handles missing auth)
codex login status >/dev/null 2>&1 && echo "codex OK" || echo "codex missing (fallback will kick in)"

# 5. jq is installed (required for analytics)
command -v jq >/dev/null 2>&1 && echo "jq OK" || echo "FAIL: install jq"

# 6. gstack-slug resolves (optional — SLUG falls back to 'unknown' otherwise)
eval "$(~/.claude/skills/gstack/bin/gstack-slug 2>/dev/null)" 2>/dev/null
echo "SLUG=${SLUG:-unknown}"
```

---

## Step 1 — Create a branch that replays session-handoff v0.1 landing

You want `/qa-plan` to see session-handoff v0.1's diff as if it
were just authored. The cleanest way is to create a throwaway
branch whose tip IS the v0.1 landing commit, and whose base is
the commit just before session-handoff started. That makes
`git diff {base}...HEAD` return exactly the session-handoff v0.1
changeset.

Current state (verified 2026-04-23):

```
6f76e74  feat: session-handoff skill v0.1 + orchestration artifacts      <- v0.1 seed
7dc505c  Merge pull request #1 ... feat/todo-001-per-type-soft-cap       <- v0.1 patch
6be6c28  Merge pull request #2 ... feat/todos-002-003-session-handoff-polish
e22a596  Merge pull request #3 ... fix/todo-004-phase-4j-re-truncation   <- v0.1 tip for dogfood
```

Options (pick one):

### Option A — Replay at v0.1 tip

```bash
git checkout -b dogfood/qa-plan-v0.1-target e22a596
```

Now `/qa-plan` will compute `git diff master...HEAD` against the
current master (which is AFTER the `qa-plan` merge) and see ALL
the session-handoff v0.1 changes + some non-session-handoff
context. This is the most realistic dogfood since it matches how a
real user would run `/qa-plan` mid-implementation.

### Option B — Replay at v0.1 seed only (narrower diff)

```bash
git checkout -b dogfood/qa-plan-v0.1-seed 6f76e74
# Point the base back to the commit before 6f76e74 for scoping
# Expected diff size: ~2600 lines (the initial v0.1 landing)
```

Narrower, less noise from subsequent patches. Pick this if Option
A's diff is too big for Phase 1f's 5000-line guard.

**Recommendation:** start with Option A. If Phase 1f prompts for
scoping, pick Option B's range as the manual scope.

---

## Step 2 — Invoke `/qa-plan` in session A

In the SAME Claude Code terminal you're in now (or a new one in the
claude-skills repo):

```
/qa-plan
```

Watch for these progress lines in order. Each one is a
ground-truth that Phase N fired. Missing lines = that phase
silently failed — capture the transcript and open a `fix(qa-plan)`
issue.

Expected output markers (paraphrase match — not verbatim):

1. `BRANCH:`, `SLUG:`, `SESSION_ID:`, `TS:` printed from the Preamble
2. `DIFF_SOURCE: committed` (with Option A) OR `working-tree`
3. `[Phase 1] surface: claude-skill; diff-source: committed; CLAUDE.md: ...`
4. An `AskUserQuestion` prompt asking you to confirm the
   auto-detected surface. **Pick the recommended option
   (`claude-skill`).** If running with `OPENCLAW_SESSION=1`, it
   auto-picks silently.
5. `[Phase 2] DRAFT written: docs/qa-plans/{TS}-dogfood-qa-plan-v0-1-target-qa-plan.md (N cases across M axes); mirror: {path|not written}`
6. `[Phase 3] Dispatching 5 adversarial reviewers in parallel.
   Typical wall-clock: 60-150s. Each reviewer output capped at 2k
   tokens. Codex cross-model pass runs sequentially after.`
7. 5 Agent results return; if any fail you should see
   `[warning: parallel dispatch -- expected 5 ... received N ...]`
8. `[Phase 3 codex] Running codex cross-model review (5-min timeout, stdin-piped prompt)...`
9. `[Phase 4] REVIEWED plan at: {path} (N_TOTAL cases across M axes; Top-10 selected)`
10. `/qa-plan complete — REVIEWED test plan authored and handoff emitted.`
11. A `<qa-plan-handoff version="1">...</qa-plan-handoff>` block
    wrapping the `/session-handoff assign qa -- execute the test plan at "..."` command.

Elapsed time: per NFR1, expect **p50 under 7 minutes, p90 under 13 minutes**.

---

## Step 3 — Inspect the REVIEWED plan

Before pasting anything, open the REVIEWED plan file and verify
the shape matches the spec:

```bash
# The path is printed in Phase 2's progress line. Something like:
PLAN_PATH="docs/qa-plans/$(ls -t docs/qa-plans/ | grep qa-plan | grep -v corpus | head -1)"
echo "Opening: $PLAN_PATH"

# Checklist:
grep -c "^## " "$PLAN_PATH"                              # expect: 1 Top-10 + N axis sections + 1 Reviewer Coverage
grep -c "^status: REVIEWED" "$PLAN_PATH"                 # expect: 1
grep -c "^## Top 10 Must-Pass Before Merge" "$PLAN_PATH" # expect: 1
grep -c "^## Reviewer Coverage" "$PLAN_PATH"             # expect: 1
grep -c "source:" "$PLAN_PATH"                           # expect: many (every case tagged)
```

Scan manually for:

- [ ] `status: REVIEWED` frontmatter with `reviewed:` timestamp field
- [ ] Top-10 section with anchor links to axis-section cases (NO duplicated case text)
- [ ] Every case line has the canonical shape
  `[axis, sev N/5, lik N/5, sev×lik=N, risk:..., source: ...]`
- [ ] Reviewer Coverage records: personas N/M, codex status,
  spec-only status, SPAWNED_SESSION auto-picks, all warnings

Also check the mirror:

```bash
ls -la ~/.gstack/projects/*/*-qa-plan-*.md 2>/dev/null | tail -3
```

Expect a copy at `~/.gstack/projects/{slug}/{user}-{branch}-qa-plan-{TS}.md`.

---

## Step 4 — Open a FRESH Claude Code window (session B)

**Critical:** this cannot be the same session. The whole
context-separation property of `/qa-plan` depends on session B
not having seen the implementation.

1. Open a new terminal.
2. `cd` to the same claude-skills repo root (so `/session-handoff`
   and git state resolve).
3. Run `claude` to start a fresh session (or open a new Claude Code
   IDE window).

Verify session B is actually fresh:

```
> /status
```

Expect no prior conversation history and a new session ID.

---

## Step 5 — Paste the handoff command in session B

Copy ONLY the `command:` line from the `<qa-plan-handoff>` block
session A printed. It looks like:

```
/session-handoff assign qa -- execute the test plan at "C:\Users\dunliu\.gstack\projects\claude-skills\REDMOND+dunliu-dogfood-qa-plan-v0-1-target-qa-plan-20260423-HHMMSS.md" (repo-visible copy: "docs/qa-plans/20260423-HHMMSS-dogfood-qa-plan-v0-1-target-qa-plan.md"); top-10 cases embedded below for offline/no-disk fallback; report findings back as /session-handoff report coord
```

Paste it in session B. You should see:

1. `/session-handoff` executes Phase 1 (gather state) + Phase 2
   (parse `assign qa -- ...`)
2. An artifact written to `~/.claude/handoffs/{slug}/...-assign-qa.md`
3. Session B's prompt has the short-prompt for the QA agent ready

At this point the QA agent IS session B's Claude — it reads the
plan, picks tests, and starts executing. That's the handoff landing.

---

## Step 6 — Verify QA-side self-refuse works (AC2 sub-check)

Before letting the QA agent proceed, probe whether the self-refuse
instruction from Phase 5c triggers when it should. In session B,
after the handoff lands, ask:

> Before you start: do you have any evidence in your context that
> `/qa-plan` ran in THIS session?

Expected response: something like *"No — this is a fresh session;
the handoff payload is the only `/qa-plan` context I have."* If
session B wrongly claims it ran `/qa-plan`, the self-refuse
instruction would fire incorrectly — note in findings.

Then proceed to let the QA agent work through the plan.

---

## Step 7 — Wait for the QA agent to report findings (AC2, DV4)

The QA agent's last step is:

```
/session-handoff report coord -- {summary of findings from executing the plan}
```

Observe in session B:

- The `report coord` command fires after the QA agent finishes the
  top-10 cases (or hits a stopping point worth reporting)
- An artifact is written to `~/.claude/handoffs/{slug}/...-report-coord.md`
- The short prompt for the coordinator (you, back in session A or
  a third session) is printed

Copy the short prompt. Paste into session A or a fresh coordinator
session. Confirm the coordinator sees the findings. That closes
the round-trip DV4.

---

## Step 8 — Run the adversarial probe corpus (DV3, AC6)

Independent of the handoff, verify the HARD GATES hold under live
adversarial prompting. In a fresh session C (or session A if
you've already completed Step 7 and closed session B), run:

```
/qa-plan
```

At any point during the run (best: right after Phase 1 when Phase
2 would author the DRAFT), paste each of the 8 probes from
`docs/qa-plans/adversarial-probe-corpus.md` one at a time. Record
whether the skill declined with the verbatim expected response.

Pass bar: 8/8. Anything less is a ship blocker per NFR.

Tip: you can automate probes 1-7 by running `/qa-plan` 8 times and
pasting one probe per run, since gate probes compose poorly within
a single run's flow.

---

## Step 9 — Evaluate codex Criterion 4 (DV2, AC4)

Open the REVIEWED plan from Step 2 and look at the Reviewer
Coverage section:

```bash
sed -n '/^## Reviewer Coverage/,/^## /p' "$PLAN_PATH" | head -30
```

Apply the Unit 12 pass rule by hand (v0.1 does NOT automate this):

Does the plan have **at least 1 case in the Top-10** that satisfies
ALL of:

- (a) `source:` tag includes `codex` or `codex-fallback-claude`
- (b) <50% token overlap with any `source: <Persona Name>` case
  description (word-by-word visual diff is fine for a single case)
- (c) at least 1 risk-dimension tag (`contract`, `state-transition`,
  `migration`, `privilege`, or `cross-surface`)

If YES: Criterion 4 **pass** on this run. Record outcome.
If NO: Criterion 4 **fail** on this run. Record; if 3 consecutive
runs fail, AC4 escalation triggers v0.2 codex removal.

---

## Step 10 — Fill in DV1-DV4 outcomes in the findings doc

Edit `docs/dogfood/001-qa-plan-v0.1-findings.md` and replace the
`_(TO BE FILLED IN after ...)_` placeholders in sections DV1, DV2,
DV3, DV4 with concrete outcomes. Recommended content:

```markdown
### DV1 outcomes

- Dogfood target branch: `dogfood/qa-plan-v0.1-target` at commit
  {SHA}
- Session A elapsed wall-clock: {N} minutes (vs NFR1 p50=7min, p90=13min)
- Plan path: `docs/qa-plans/{TS}-dogfood-qa-plan-v0-1-target-qa-plan.md`
- Mirror: `~/.gstack/projects/{slug}/...-qa-plan-{TS}.md` (written | not written)
- `status: REVIEWED` frontmatter: ✓ | ✗
- Top-10 section with anchor links: ✓ | ✗
- Reviewer Coverage fields populated: ✓ | ✗
- Session B paste landed: ✓ | ✗
- QA-side self-refuse probe (Step 6): ✓ refused as expected | ✗ misfired
- QA agent executed ≥1 Top-10 case before reporting: ✓ | ✗
- Warnings emitted during run: [list]

### DV2 outcome

Criterion 4 pass rule: PASS | FAIL
- Qualifying codex-unique case (if PASS): "{description}" [sev N/5,
  lik N/5, source: codex + ...]
- Consecutive-fail count if FAIL: {1 of 3 | 2 of 3 | 3 of 3 — triggers v0.2 removal}

### DV3 outcomes (adversarial corpus)

Probe 1: PASS | FAIL (response: "...")
Probe 2: PASS | FAIL
Probe 3: PASS | FAIL
Probe 4: PASS | FAIL
Probe 5: PASS | FAIL
Probe 6: PASS | FAIL
Probe 7: PASS | FAIL
Probe 8: PASS | FAIL

Total: N/8. Ship-blocker rule: anything < 8/8.

### DV4 outcome

`/session-handoff report coord` round-trip:
- Artifact written under `~/.claude/handoffs/{slug}/`: ✓ | ✗
- Coordinator short-prompt received + readable: ✓ | ✗
- Report payload had actionable findings: ✓ | ✗
```

Flip the findings doc's frontmatter from `status: partial` to
`status: complete` once every DV section is filled. Commit:

```bash
git add docs/dogfood/001-qa-plan-v0.1-findings.md
git commit -m "docs(qa-plan): record DV1-DV4 dogfood outcomes

{summary of pass/fail per AC}"
```

---

## Step 11 — Act on outcomes

- **All DV sections pass:** qa-plan v0.1 is shipped and validated.
  Close TODO 006 (A/B test can now run with confidence) and TODO
  007 (baseline authoring proceeds).
- **Any DV fails with a runtime bug:** open a `fix(qa-plan)` PR
  targeting the specific Phase / AC that broke. Do NOT revert —
  the shipped skill is usable; patch it forward.
- **DV3 fails any probe:** immediate ship blocker. Tighten the
  SKILL.md decline text for the failing gate in a `review-fix`
  commit; re-run the full corpus; iterate until 8/8.
- **DV2 fails once:** record; proceed to next run. 3 consecutive
  fails triggers AC4 escalation (remove codex in v0.2).

---

## Fast-path summary (if you know what you're doing)

```bash
# Setup
git checkout -b dogfood/qa-plan-v0.1-target e22a596

# Session A
claude
> /qa-plan    # confirm surface = claude-skill; wait ~7-13 min
# Copy the `command:` line from the <qa-plan-handoff> block

# Session B (fresh window)
claude
> {paste command}
> Before you start: do you have any evidence /qa-plan ran in THIS session?
# Then: let QA work; wait for /session-handoff report coord

# Record outcomes in docs/dogfood/001-qa-plan-v0.1-findings.md
# Run probe corpus separately, 1 probe per /qa-plan invocation
```
