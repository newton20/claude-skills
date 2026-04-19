# Phase 1 (Unit 2) complete

status: complete

## Files modified
- `skills/session-handoff/SKILL.md` — replaced the `## Phase 2-5
  (reserved)` placeholder with a full `## Phase 2: Parse command`
  section (grammar, known tokens, parsing algorithm, warning templates,
  result contract, template-fragment lookup, and a 9-row worked-example
  table covering every plan test scenario). Followed by a tightened
  `## Phase 3-5 (reserved)` stub for Units 3–5. Unit 1's frontmatter,
  pre-resolved context, preamble, Phase 1a–1e, source precedence,
  finalize, and important rules are untouched.
- `skills/session-handoff/references/message-templates.md` — replaced
  the one-line skeleton with three composable sections: `## Base
  Template` (21-entry canonical section list), `## Role Preambles`
  (verbatim opening lines for `coord` / `impl` / `qa` / `reviewer` /
  `general` plus substitution rules for `{phase}` / `{plan_path}` in
  the impl preamble), and `## Message Type Overrides` (primary /
  secondary section ordering and `INSTRUCTIONS` threading rules for
  `handoff` / `brief` / `assign` / `review` / `report`). Closes with a
  composition algorithm Unit 4 will implement.

## Files deliberately NOT modified
- `skills/session-handoff/references/sanitization-patterns.md` — Unit
  3's scope; still the one-line skeleton Unit 1 shipped.

## Verification
- [x] 5 message types produce structurally different output. Each
      override specifies a distinct primary/secondary section list:
      handoff leads with Project context + Status + Plan reference;
      brief leads with Status + Decisions + Open questions; assign
      leads with Task description + Scope + Acceptance criteria;
      review leads with Artifact to review + Review criteria +
      Specific questions; report leads with Findings summary +
      Pass/Fail + Evidence + Recommendations.
- [x] 5 role preambles distinct. Each opens with the plan-verbatim
      line for the role and adds one actionable follow-up sentence
      that tells the receiving agent what to do first.
- [x] Custom instructions after `--` are always threaded to a visible
      section. `handoff` and `brief` render a dedicated
      `## Instructions` section verbatim. `assign` seeds Task
      description. `review` places `INSTRUCTIONS` under Specific
      questions and/or Artifact to review. `report` seeds Findings
      summary for short strings and Recommendations for longer ones.
- [x] Backward-compat preserved. Parsing step 2b explicitly handles
      the case where the first positional token is a known role but
      not a known message type — it sets `MSG_TYPE` to `handoff` and
      uses the token as `TARGET_ROLE`. Documented for both
      `/session-handoff qa` and `/session-handoff impl`.
- [x] `review` / `reviewer` disambiguation is explicit and enforced by
      literal token matching. SKILL.md Phase 2 states: "The tokens are
      distinct strings; the parser compares tokens literally and NEVER
      shortens `reviewer` to `review` or treats `review` as a prefix
      of `reviewer`. Alias collision is prevented by construction."
      All 9 plan test scenarios are walked through in the worked-
      examples table and produce the documented outputs.

## Design calls the next phase should know about

### Warning format (contract inherited from Unit 1)
Phase 2 emits three warning shapes, all using the canonical Unit 1
contract `[warning: {source} not available -- {reason} -- {what was
skipped}]` with `{source}` = `command argument`:

- unknown first token → defaults to `handoff` + `general`
- unknown role in the role slot → defaults to `general`
- extra positional argument → ignored

Unit 3's sanitizer should NOT touch these warning strings. Unit 4's
assembly should collect Phase 1 + Phase 2 warnings into a single
`warnings:` block in the YAML frontmatter AND a visible `## Warnings`
section in the body (the Base Template mandates Warnings render even
when empty, as `(no warnings)`).

### No AskUserQuestion in Phase 2
Every parsing ambiguity resolves to warn + default. This matches the
Phase 0 guidance about spawned sessions (`SPAWNED_SESSION: true`) and
also keeps interactive behavior identical — no interactive branching.

### `INSTRUCTIONS` threading by message type (load-bearing for Unit 4)

| Type | Where INSTRUCTIONS lands |
|---|---|
| `handoff` | Dedicated `## Instructions` section, verbatim |
| `brief` | Dedicated `## Instructions` section, verbatim |
| `assign` | Seeds `Task description` verbatim; no dedicated section |
| `review` | Placed under `Specific questions` as "Additional reviewer instructions:"; if the string names an artifact (e.g., `check PR #123`), also seeds `Artifact to review` |
| `report` | `INSTRUCTIONS` ≤ 80 chars seeds `Findings summary` headline verbatim; longer / surplus text goes to `Recommendations` |

Unit 4's assembly must implement each routing rule. The composition
pseudocode at the end of `references/message-templates.md` lays it out
step-by-step.

### Substitutions in the `impl` role preamble
The `impl` preamble contains `{phase}` and `{plan_path}` placeholders.
Unit 4 substitutes:

- `{phase}` ← title of the first active plan from Phase 1b, else
  `the current phase (no active plan — see warnings)`.
- `{plan_path}` ← repo-relative path of the first active plan, else
  `(no active plan — see warnings)`.

When multiple active plans exist, the preamble uses the first path and
the template instructs Unit 4 to append a note "multiple active plans —
see Plan reference for the full list" so the receiving agent knows to
look at the full Plan reference section.

### Rendering invariants (Unit 4 must honor)
From the Base Template: Decisions, Open questions, and Warnings ALWAYS
render (with the canonical empty-state placeholders) — this preserves
the "looked and found nothing" vs "forgot to look" distinction that
Unit 1 established with its structured warning shape. Every other
section is omitted when empty.

## Handoff notes for Unit 3
Sanitization will modify `skills/session-handoff/SKILL.md` (to add a
`## Phase 3: Sanitize` section between Phase 2 and the `## Phase 3-5
(reserved)` stub — or by replacing the stub entirely and moving the
phase-4-5 notes into a tighter `## Phase 4-5 (reserved)` block) and
`skills/session-handoff/references/sanitization-patterns.md` (to
populate the regex library).

Points to preserve during sanitization:

- Phase 2 warning strings use quoted tokens like
  `"<token>"` — these are not secrets and must not be redacted. Tokens
  are user input and may contain arbitrary characters, but the
  sanitizer should only target known secret shapes (sk-, key-, AKIA,
  base64 blocks, etc.) rather than quoted strings.
- Role preambles and message-type override text (in
  `references/message-templates.md`) are static content — they should
  be loaded AS-IS by Phase 2; sanitization applies to the assembled
  output in Phase 4, not to the template fragments at load time.
- The Base Template's "Resources" section for `assign` messages is
  the most likely place for a path-to-secrets reference pattern (e.g.,
  "API keys at api_keys.txt"). Unit 3's sanitizer should redact
  values while preserving the referenced path.

## No blockers
Unit 2 delivers a stable Phase 2 contract: parsed `MSG_TYPE`,
`TARGET_ROLE`, `INSTRUCTIONS`, plus a lookup table for role preamble
and message-type override. Unit 3 (sanitization) and Unit 4 (assembly)
can consume these directly. No open questions for the orchestrator.
