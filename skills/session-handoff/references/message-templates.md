# Message Templates (session-handoff)

Composable template fragments for the 5 message types and 5 target
roles. The design is DRY by construction: **one base template + five
role preambles + five message-type overrides = twenty-five legal
combinations**, expressed without twenty-five separate templates.

At assembly time (Unit 4), the skill:

1. Looks up the preamble for `TARGET_ROLE`.
2. Looks up the override for `MSG_TYPE`.
3. Merges them with the Phase 1 state and the user's `INSTRUCTIONS`
   following the override's section-ordering rule.

Phase 2 (Unit 2) only SELECTS which fragments apply. This file is
authoritative for the fragment contents and the composition contract.

---

## Base Template

The canonical section list every assembled message draws from. Sections
with no content are omitted, with three explicit exceptions — Decisions,
Open questions, and Warnings always render, even when empty, so the
receiving agent sees the difference between "looked and found nothing"
and "we forgot to look."

Section names are stable identifiers used by the overrides below.

1. **Role preamble.** One role-specific paragraph. See "Role Preambles".
2. **Project context.** Repo slug, branch, HEAD SHA, worktree
   clean/dirty flag, latest checkpoint path (if any). Sourced from the
   preamble and Phase 1a/1c.
3. **Status summary.** One-line description of where the work stands,
   composed from the branch + the title of the first active plan + the
   worktree dirty flag. Written in imperative present tense
   ("Implementing Phase 2 of the session-handoff skill on branch
   `master` (worktree dirty)").
4. **Git details.** Short status, last 5 commits, diff stat. Sourced
   from Phase 1a.
5. **Plan reference.** Full repo-relative path(s) to every active plan.
   If multiple plans match, list all — the receiving agent decides
   which applies.
6. **Decisions.** Session decisions, each tagged
   `[inferred from session]`. If Phase 1e returned
   `[no session decisions captured -- conversation context unavailable]`,
   render that line literally instead of the list.
7. **Open questions.** Unresolved items, each tagged
   `[inferred from session]`. Empty-state placeholder handled the same
   way as Decisions.
8. **Task description.** *(assign only.)* What the receiving agent must
   do. Seeded from `INSTRUCTIONS`.
9. **Scope.** *(assign only.)* What is in / out of scope. When derivable
   from an active plan (the plan's `## Scope Boundaries` section), pull
   excerpts; otherwise render
   `[to be defined by assigning agent — see Task description]`.
10. **Acceptance criteria.** *(assign only.)* How the work will be
    verified. Derive from the plan's Verification block when available;
    otherwise render the same placeholder as Scope.
11. **Resources.** *(assign only.)* File paths, URLs, references the
    assignee needs (plan path, checkpoint path, CLAUDE.md path, any
    `INSTRUCTIONS`-mentioned artifacts).
12. **Artifact to review.** *(review only.)* PR URL, diff path, file
    list to examine. Seeded from `INSTRUCTIONS` when the user names the
    artifact in the command line; otherwise defaults to the current
    branch's diff against its upstream (`git diff @{u}...HEAD`).
13. **Review criteria.** *(review only.)* What to check for. When the
    override below is silent, use a generic checklist (correctness,
    tests, security, pattern compliance).
14. **Specific questions.** *(review only.)* Targeted questions.
    `INSTRUCTIONS`, when present, is appended verbatim under the label
    "Additional reviewer instructions:".
15. **Findings summary.** *(report only.)* One-line headline. If
    `INSTRUCTIONS` is non-empty and short (≤ 80 chars), quote it
    verbatim as the headline; else synthesize a headline from the
    evidence and place `INSTRUCTIONS` under Recommendations.
16. **Pass/Fail.** *(report only.)* Explicit verdict word (`PASS`,
    `FAIL`, `PARTIAL`, or `UNKNOWN`).
17. **Evidence.** *(report only.)* Command output snippets, file paths,
    screenshots, log excerpts.
18. **Recommendations.** *(report only.)* Concrete next actions.
    `INSTRUCTIONS` surplus text (anything not absorbed by Findings
    summary) lands here.
19. **Instructions (user-provided).** Dedicated section holding
    `INSTRUCTIONS` verbatim. Rendered for `handoff` and `brief`; omitted
    for `assign` / `review` / `report` because those types route
    `INSTRUCTIONS` into type-specific sections above.
20. **Warnings.** Every `[warning: ...]` line from Phase 1 (missing
    sources) and Phase 2 (command-argument issues). Always present; an
    empty warnings block renders as `(no warnings)` so its absence is
    unambiguous.
21. **Artifact pointer.** Path to the full disk artifact under
    `~/.claude/handoffs/{slug}/`, followed by the line "If on the same
    machine, read `{path}` for additional detail."

---

## Role Preambles

One preamble per target role. Each opener is specific about what the
receiving agent should do FIRST, so the agent orients without re-reading
the whole message. Opening lines are taken verbatim from the plan.

### coord

```
You are the coordination agent. Read the briefing, update your phase
tracker, decide next actions. Do not dive into implementation details —
your job is to route work and decide what happens next, not to write
code. If a briefing is ambiguous, leave a clarifying note in the
originating session's Open questions rather than guessing.
```

### impl

```
You are the implementation agent for {phase}. Read the plan at
{plan_path}, start with /ce:work. If the plan references a checkpoint,
resume from it with /checkpoint resume before editing any files. Do not
re-scope the work — the plan is the contract. If you need to deviate,
surface it in Open questions and pause for the coordinator; do not
silently change direction.
```

**Substitutions at assembly time:**

- `{phase}` — title of the first active plan from Phase 1b. If no active
  plan was found, substitute `the current phase (no active plan — see
  warnings)`.
- `{plan_path}` — repo-relative path to the first active plan. If
  multiple plans match, substitute the first path and note "multiple
  active plans — see Plan reference for the full list". If no plan,
  substitute `(no active plan — see warnings)`.

### qa

```
You are the QA agent. Your job is to test, not fix. Read the
playbook/assignment, execute tests, report findings. Do not modify
application code, push commits, or touch the plan. If a test is
infeasible with the current environment, record that explicitly in your
report — silent skips destroy trust in the pass signal.
```

### reviewer

```
You are a code reviewer. Read the diff, check for the specific concerns
listed below. Keep your review tight: flag issues that block merging and
issues that will cause maintenance pain; do not bikeshed style choices
that already match the surrounding codebase. When in doubt about
severity, err on the side of reporting and let the assigning agent
triage.
```

### general

```
You are continuing work on this project. Here is the current state —
branch, active plans, decisions, and open questions. Orient yourself
first (read the plan reference, check the latest checkpoint if listed),
then continue where the previous session left off. Treat sections tagged
[inferred from session] as best-effort and confirm before acting on
them.
```

---

## Message Type Overrides

Each override below specifies:

- **Primary sections** — appear in the short prompt AND the full
  artifact, in the listed order, immediately after the role preamble.
- **Secondary sections** — appear only in the full artifact, after the
  primary sections, as reference material.
- **`INSTRUCTIONS` threading** — where the user's `--` text lands.
- **Type-specific notes** — anything the override changes about section
  rendering.

Invariants shared by all five overrides (enforced by Unit 4 assembly):

- Role preamble is always section 1.
- Warnings section is always second-to-last.
- Artifact pointer is always last.
- Sections with no content are omitted unless they are Decisions, Open
  questions, or Warnings (see Base Template).

### handoff *(default)*

**Purpose.** Pass the current working state to a fresh session — the
most common case, hence the default. Reads like a continuation note.

- **Primary:** Project context → Status summary → Plan reference →
  Instructions (user-provided).
- **Secondary:** Decisions → Open questions → Git details.
- **`INSTRUCTIONS` threading:** dedicated `## Instructions` section,
  verbatim. If empty, the section is omitted.
- **Notes:** when the role is `impl`, the plan path injected into the
  role preamble and the plan path listed under Plan reference will
  match — leave both. Redundancy is cheap and the agent may scan only
  one.

### brief

**Purpose.** Status update to a coordinator or peer. Leads with "where
are we?" before "how we got here." Shorter than a handoff.

- **Primary:** Status summary → Decisions → Open questions →
  Instructions (user-provided).
- **Secondary:** Plan reference → Git details → Project context.
- **`INSTRUCTIONS` threading:** dedicated `## Instructions` section,
  verbatim. If empty, the section is omitted.
- **Notes:** the brief deliberately demotes Project context to
  secondary — the receiving coordinator already knows the project and
  only needs the delta since the last update.

### assign

**Purpose.** Task assignment from coordinator → worker session (impl /
qa / reviewer). Emphasizes actionable task shape over narrative state.

- **Primary:** Task description → Scope → Acceptance criteria →
  Resources.
- **Secondary:** Project context → Plan reference → Git details.
- **`INSTRUCTIONS` threading:** `INSTRUCTIONS` seeds the Task
  description verbatim. When `INSTRUCTIONS` is empty, render
  `[to be defined by assigning agent]` so the worker sees the gap
  explicitly rather than an absent section.
- **Notes:** no dedicated `## Instructions` section — it has been
  absorbed. Scope, Acceptance criteria, and Resources render their
  `[to be defined ...]` placeholders when no active plan is available
  to seed them.

### review

**Purpose.** Peer-review request — typically from impl/qa → reviewer, or
from qa → impl for playbook feasibility review.

- **Primary:** Artifact to review → Review criteria → Specific
  questions.
- **Secondary:** Project context → Status summary → Git details.
- **`INSTRUCTIONS` threading:** if the user wrote a targeted request
  ("check auth"), place it verbatim under Specific questions as
  "Additional reviewer instructions:". If the `INSTRUCTIONS` string
  names an artifact (e.g., `check PR #123`, `review file/path.ts`),
  also seed Artifact to review with the named identifier.
- **Notes:** no dedicated `## Instructions` section — it has been
  absorbed. Review criteria defaults to a generic checklist
  (correctness, tests, security, pattern compliance) when the role or
  plan does not supply a more specific list.

### report

**Purpose.** Status / findings report — typically from impl or qa back
to the coordinator.

- **Primary:** Findings summary → Pass/Fail → Evidence →
  Recommendations.
- **Secondary:** Project context → Git details.
- **`INSTRUCTIONS` threading:** short `INSTRUCTIONS` (≤ 80 chars) seed
  the Findings summary headline verbatim. Longer `INSTRUCTIONS`, or any
  surplus after the headline slot, append to Recommendations. An empty
  `INSTRUCTIONS` leaves the Findings summary to be synthesized from
  Evidence.
- **Notes:** no dedicated `## Instructions` section — it has been
  absorbed. Pass/Fail always renders, even if the verdict is `UNKNOWN`;
  a missing verdict is a finding in its own right.

---

## Composition algorithm (for assembly in Unit 4)

Pseudocode Unit 4 will implement. Documented here so the fragments above
compose deterministically.

```
1. preamble  = ROLE_PREAMBLES[TARGET_ROLE]    # substitute {phase}, {plan_path}
2. override  = TYPE_OVERRIDES[MSG_TYPE]
3. short_sections = [preamble] + override.primary + ["Warnings", "Artifact pointer"]
4. full_sections  = [preamble] + override.primary + override.secondary
                    + ["Warnings", "Artifact pointer"]
5. For each section in the chosen list:
     content = pull_from_phase1_state(section_name, MSG_TYPE, TARGET_ROLE)
     if section_name in {"Decisions", "Open questions", "Warnings"}:
        render even if empty, using the canonical empty-state placeholder
     elif content is empty:
        skip section
     else:
        emit section
6. Thread INSTRUCTIONS per override.instructions_rule.
7. Short prompt: emit short_sections. Length budget is per-type —
   see SKILL.md Phase 4 step 4g for the soft/hard caps keyed by
   `MSG_TYPE`. Unit 4 truncation priority applies when the hard cap is
   exceeded: cut Plan reference detail first, then Status details;
   always keep preamble, branch/SHA, instructions, artifact pointer.
8. Full artifact: emit full_sections with YAML frontmatter (schema_version,
   MSG_TYPE, TARGET_ROLE, branch, sha, timestamp, source_session_id,
   warnings[]).
```

Unit 2 guarantees every fragment referenced above exists and is
addressable by `(MSG_TYPE, TARGET_ROLE)`. Unit 3 runs the sanitization
pass on the assembled output before Unit 4 writes it to disk and the
clipboard.
