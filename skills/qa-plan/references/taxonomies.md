# Taxonomies (qa-plan)

The test-plan authoring taxonomy has three composable axes:

1. **Surface axes** (this file, below) — how to test for each of the
   5 surfaces. The Phase 2 planner picks the axis list for the
   detected surface and produces at least one case per axis.
2. **Risk dimensions** (cross-cutting) — what-kind-of-risk tags
   every case carries regardless of surface.
3. **Spec/impl boundaries** — per-surface allowlist/denylist for the
   Phase 3 spec-only gap reviewer.

SKILL.md references this file by pointer only ("read
`references/taxonomies.md` for the per-surface axis list and
spec/impl boundary before authoring") so the surface content does
not duplicate between the planner and the reviewer prompts.

---

## Surface detection rules

| Diff path pattern                                         | Detected surface |
|-----------------------------------------------------------|------------------|
| `*.tsx`, `*.jsx`, `*.html`, `*.css`, `public/*`           | web              |
| `bin/*`, `cmd/*`, `cli/*`, `package.json#bin`             | cli              |
| `lib/*`, `src/lib/*`, `pkg/*`                             | library          |
| `api/*`, `routes/*`, `migrations/*`, `Docker*`            | service          |
| `skills/*/SKILL.md`, `~/.claude/skills/*`                 | claude-skill     |

Ties: the surface with the most matches wins. If two surfaces tie,
Phase 1 asks the user to pick.

---

## Per-surface axis lists

Each axis is 3-5 bullets (tight). Phase 2 produces at least one
case per axis for the detected surface.

### web

- **Flows** — end-to-end happy path + the 2 most likely failure paths
- **Form validation** — empty / invalid / boundary values per field
- **Responsive breakpoints** — mobile / tablet / desktop layout integrity
- **Accessibility** — keyboard nav, focus order, ARIA labels, color contrast
- **Browser compat + network failure** — slow 3G, offline, request timeout

### cli

- **Arg matrix** — valid, invalid, boundary; positional + flagged + mutually exclusive
- **stdin / stdout** — piping in, piping out, non-tty detection, binary data
- **Exit codes** — 0 success, conventional error codes, signal exit
- **Env var overrides** — `$XDG_*`, `$HOME`, tool-specific override, unset fallback
- **Concurrent invocation + signals** — SIGINT / SIGTERM handling, lock contention

### library

- **Public API contract** — every exported function called with valid + invalid inputs
- **Invariants** — pre/post conditions for any stateful object
- **Thread / async safety** — concurrent call, re-entrant call
- **Error propagation** — exceptions raised, caught, and re-surfaced correctly
- **Version compat + API surface stability** — deprecation path, SemVer boundary

### service

- **Endpoint contract per method** — GET / POST / PUT / DELETE request / response shape
- **Auth matrix** — unauth / wrong-role / correct-role / expired-token per endpoint
- **Rate limits + idempotency** — concurrent calls, retry-after, idempotency keys
- **Migration safety** — forward + rollback per schema change, data preservation
- **Backward compat** — old clients against new server, new clients against old server

### claude-skill

- **Slot filling** — every `{placeholder}` in prose templates substituted correctly
- **Phase boundary adherence** — no skipped phases, no out-of-order execution
- **Malformed user input** — unknown token, empty input, adversarial prompt
- **Hard-gate enforcement** — adversarial corpus probes elicit prescribed decline
- **Artifact shape + placeholder lint** — generated artifacts parse; no `{slot}` leaks

---

## Risk dimensions (cross-cutting)

Every case is tagged with ≥1 risk dimension. These cross-cut the
surface axes — a single case can carry 1-3 dimension tags.

| Tag                 | Meaning                                                          |
|---------------------|------------------------------------------------------------------|
| `contract`          | API / CLI / interface changed; callers may break                 |
| `state-transition`  | Stateful object moves between states; may corrupt or deadlock    |
| `migration`         | Schema / data / config transform; may lose data or block rollback |
| `privilege`         | Auth, permissions, secret handling, trust-boundary crossing      |
| `cross-surface`     | Integration point between two or more surfaces                   |

---

## Worked example — risk-dimension tagging

| Case description                                          | Surface       | sev | lik | Risk tags                   |
|-----------------------------------------------------------|---------------|-----|-----|-----------------------------|
| `POST /users` with email already in DB returns 409        | service       | 4   | 4   | `contract`                  |
| Two parallel signups with same email race to insert       | service       | 5   | 2   | `state-transition, privilege` |
| `ALTER TABLE users ADD COLUMN role NOT NULL` on 10M rows  | service       | 5   | 3   | `migration, state-transition` |
| CLI reads stdin, writes parsed output to stdout (pipe)    | cli           | 3   | 4   | `contract`                  |
| Skill SKILL.md has unfilled `{slot}` placeholder on emit  | claude-skill  | 4   | 3   | `contract`                  |

---

## Worked example — Top-10 weighting calculation

Sort descending by `sev × lik`. Break ties by risk-dimension-tag
count (more tags wins). Secondary tiebreaker: cases tagged
`source: spec-only + impl-aware` (both sources agree) win ties
over single-source cases (pre-validated signal).

| Case                                          | sev | lik | sev×lik | tags | source               | Rank                                      |
|-----------------------------------------------|-----|-----|---------|------|----------------------|-------------------------------------------|
| "Signup form missing email check"             | 5   | 4   | 20      | 1    | spec-only + impl     | 1 (tie broken by spec+impl agreement)     |
| "Race on concurrent signup"                   | 5   | 4   | 20      | 2    | Race Demon           | 2 (tie broken by 2 tags vs 1)             |
| "SQL injection via search param"              | 5   | 4   | 20      | 1    | Prod Saboteur        | 3                                         |
| "Slow page load with 50 items"                | 3   | 5   | 15      | 0    | Confused User        | 4                                         |

---

## Spec/impl boundary (Phase 3 spec-only gap reviewer)

The Phase 3 spec-only reviewer reads ONLY the spec bundle for the
detected surface and outputs test cases the DRAFT plan MISSES from
a black-box viewpoint. The allowlist / denylist below is enforced
via (a) `tools: ["Read", "Grep"]` on the Agent dispatch and (b)
explicit forbidden-paths prose in the reviewer prompt. Defense-in-
depth, not a hard sandbox — the reviewer is an LLM and may still
peek; Reviewer Coverage discloses this caveat.

| Surface       | Spec-only reviewer CAN see                      | Spec-only reviewer CANNOT see           |
|---------------|-------------------------------------------------|-----------------------------------------|
| web           | PRD, user stories, mockups, acceptance criteria | Source, UI implementation, tests        |
| cli           | README usage, `--help`, man pages               | Source, internal tests                  |
| library       | Public API docs, type signatures (public only)  | Internals, private modules              |
| service       | OpenAPI schema, user-facing docs                | Service code, DB internals              |
| claude-skill  | `README.md` skill-table row, `~/.gstack/projects/**/*-design-*.md` | `skills/*/SKILL.md`, `skills/*/references/*`, `docs/plans/*` (impl-shaped) |

**claude-skill recursion caveat:** plan docs under `docs/plans/`
describe IMPL intent (excluded even though they are docs); design
docs under `~/.gstack/projects/` capture product intent (allowed).

**Spec-starvation gate.** If the allowlist bundle is under 1500
tokens, Phase 3 skips the spec-only reviewer entirely with a
canonical warning — below that threshold the reviewer hallucinates
rather than de-biases.
