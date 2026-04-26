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
| `README*`, `CHANGELOG*`, `LICENSE*`, `CONTRIBUTING*`, `docs/**` | claude-skill (only when `skills/*/SKILL.md` exists in the repo tree — these files document skills in skill-repo context; on non-skill repos they do NOT count for any surface and the fallback in Phase 1g fires) |

Ties: the surface with the most matches wins. If two surfaces tie,
Phase 1 asks the user to pick. If every surface has zero matches
(e.g., a README-only diff in a non-skill repo), Phase 1g's
no-match fallback asks the user to pick manually or abort — see
SKILL.md Phase 1g for the fallback prose.

**Why documentation files fold into `claude-skill` only in skill
repos:** in a claude-skills monorepo, the top-level `README.md`
(plus `CHANGELOG.md`, `LICENSE`, `CONTRIBUTING.md`, `docs/**`) is
part of the user-facing surface of the shipped skills — changes
there get the same axis coverage (slot filling, artifact shape,
phase-boundary adherence, adversarial-probe alignment) that
`SKILL.md` changes do. In a non-skill repo, the same files
describe whatever the repo's primary surface is, and attributing
them to `claude-skill` would be wrong. The `skills/*/SKILL.md`
presence probe is a cheap, deterministic way to distinguish the
two cases.

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
| "Race on concurrent signup"                   | 5   | 4   | 20      | 2    | Race Demon           | 1 (primary tiebreaker: 2 tags > 1 tag)    |
| "Signup form missing email check"             | 5   | 4   | 20      | 1    | spec-only + impl     | 2 (tag-count tied at 1; secondary tiebreaker: spec+impl agreement wins) |
| "SQL injection via search param"              | 5   | 4   | 20      | 1    | Prod Saboteur        | 3 (1 tag, single-source; loses both tiebreakers) |
| "Slow page load with 50 items"                | 3   | 5   | 15      | 0    | Confused User        | 4 (lower sev×lik; no tie)                 |

---

## Spec/impl boundary (Phase 3 spec-only gap reviewer)

The Phase 3 spec-only reviewer reads ONLY the spec bundle for the
detected surface and outputs test cases the DRAFT plan MISSES from
a black-box viewpoint. The allowlist / denylist below is enforced
via (a) the project-defined `qa-plan-spec-only-reviewer` subagent's
`tools: [Read, Grep]` frontmatter — `Bash` is denied at the
Claude Code subagent layer, not just by prompt intent — and (b)
explicit forbidden-paths prose in the per-call prompt that scopes
`Read` and `Grep` to the allowed paths. When the subagent file is
not installed at `~/.claude/agents/qa-plan-spec-only-reviewer.md`,
dispatch falls back to `general-purpose` with prompt-only tool
intent and Reviewer Coverage records the degraded enforcement.
See SKILL.md Phase 7b for the full enforcement story and the
fallback canonical warning.

| Surface       | Spec-only reviewer CAN see                      | Spec-only reviewer CANNOT see           |
|---------------|-------------------------------------------------|-----------------------------------------|
| web           | Common base (`README*`, `CHANGELOG*`, `LICENSE*`, `CONTRIBUTING.md`, `docs/**` excluding `docs/plans/`); PRDs / user stories / mockups / acceptance criteria typically live under `docs/**` and are captured by the common base | Source, UI implementation, tests, anything under `src/`, `app/`, `pages/`, `components/` |
| cli           | Common base + `man/**`                          | Source under `bin/`, `cmd/`, `cli/`, internal tests |
| library       | Common base + `types/**/*.d.ts`, `typings/**/*.d.ts` (best-effort: cannot perfectly distinguish public from internal types in arbitrary repos; the dedup gate is the safety net) | Source under `src/`, `lib/`, `pkg/`, internals, private modules, `src/**/*.d.ts` (impl-adjacent) |
| service       | Common base + `openapi.{yaml,yml,json}`, `swagger.{yaml,yml,json}`, `api/openapi.*`, `spec/openapi.*` | Service code, DB internals, migrations, anything under `src/`, `routes/`, `migrations/` |
| claude-skill  | Common base + `~/.gstack/projects/$SLUG/*-design-*.md` (only this project's design docs, non-recursive — matches what the SKILL.md resolver actually does) | `skills/*/SKILL.md`, `skills/*/references/*`, `skills/*/agents/*`, `docs/plans/*` (impl-shaped) |

**Common base bundle** (all 5 surfaces): `README.md` / `README.rst`
/ `README.txt`, `CHANGELOG.md` / `CHANGELOG.rst`, `LICENSE` /
`LICENSE.md`, `CONTRIBUTING.md`, plus `docs/**` (`*.md`, `*.rst`,
`*.txt`) excluding `docs/plans/**` (impl-shaped). Per-surface
extras stack on this base.

**claude-skill recursion caveat:** plan docs under `docs/plans/`
describe IMPL intent (excluded even though they are docs); design
docs under `~/.gstack/projects/` capture product intent (allowed).
The `skills/*/agents/*.md` files are subagent prompts — they are
the impl of the persona's behavior, NOT the spec of the parent
skill — so they're forbidden too.

**Spec bundle expansion in v0.2.1 (`CHANGELOG`, `LICENSE`,
`CONTRIBUTING`, `docs/**`):** Unit 3 of v0.2 expanded the
claude-skill *surface detection* patterns to count documentation
files (so a `README`-only diff in a skill repo no longer falls
through to a no-match prompt). The spec/impl boundary above must
mirror that expansion — otherwise the spec-only reviewer starves
on a docs-only diff that auto-detected as claude-skill (codex
pre-merge review of PR #9 surfaced this; v0.2.1 fix). The
expanded bundle keeps `docs/plans/*` excluded for the same reason
as before (plan docs are impl-shaped). `docs/dogfood/` is part of
the spec bundle — dogfood findings ARE product-intent
documentation about how the skill should behave.

**Per-surface bundle implementation in v0.3 (web/cli/library/service):**
Run #4 codex review (sev×lik=16) caught that the v0.2.2 Phase 3a
case statement set `SPEC_BUNDLE_IMPL_STATUS="not-implemented"` for
every non-`claude-skill` surface — i.e., the spec-only reviewer
was *always skipped* on web/cli/library/service runs with a
canonical "v0.3 implements per-surface bundles" warning. v0.3
ships the implementation: the common base (`README`, `CHANGELOG`,
`LICENSE`, `CONTRIBUTING`, `docs/**` minus `docs/plans/**`)
applies to every surface, with per-surface extras stacked above
(OpenAPI for service, `man/**` for cli, `types/**/*.d.ts` for
library, `~/.gstack/projects/**/*-design-*.md` for claude-skill,
nothing extra for web). The `SPEC_BUNDLE_IMPL_STATUS` variable
and its "not-implemented" branch were removed; reaching the
starvation-gate warning now genuinely means "this repo lacks docs
at the standard paths," not "we haven't implemented this surface."

**Spec-starvation gate.** If the allowlist bundle is under 1500
tokens, Phase 3 skips the spec-only reviewer entirely with a
canonical warning — below that threshold the reviewer hallucinates
rather than de-biases. With the v0.3 per-surface implementation,
a service repo with even a small `openapi.yaml` plus a `README`
typically clears the gate; a library with `types/**/*.d.ts` or a
docs site with substantial `docs/**` content does too. Repos with
neither structured docs nor a populated allowlist target will
honestly skip — the warning text now reflects that.
