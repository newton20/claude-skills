# Phase 0 (Unit 1) complete

status: complete

## Files created
- `skills/session-handoff/SKILL.md` (13.3 KB)
- `skills/session-handoff/references/message-templates.md` (skeleton, one-line header)
- `skills/session-handoff/references/sanitization-patterns.md` (skeleton, one-line header)

## Verification
- [x] SKILL.md exists with valid gstack-compatible frontmatter (name, description with trigger phrases, preamble-tier: 1, version, allowed-tools).
- [x] State gathering covers git / active plans / latest checkpoint / CLAUDE.md / conversation synthesis.
- [x] Every missing source emits a warning in the canonical 3-segment shape `[warning: {source} not available -- {reason} -- {what was skipped}]`.
- [x] HEAD SHA (`git rev-parse --short HEAD`) and worktree dirty flag (derived from `git status --porcelain`) are captured as first-class fields in Phase 1a alongside branch, status, log, and diff stat.

## Notes for Phase 1 (Unit 2)

### Structure of SKILL.md (where Unit 2 plugs in)

SKILL.md is organized to match the plan's "Flow" section so subsequent units add sections without rewriting existing ones. Top to bottom:

1. Frontmatter
2. Intro + HARD GATE
3. `## Pre-resolved context` (ce-sessions-style `!backtick` commands for slug/branch/SHA/worktree). Stable. Unit 2 should not touch.
4. `## Preamble (run first)` — minimal: session touch, slug eval, branch, session_id, `_TEL_START`, timeline `started` event, spawned-session detection. Stable. Unit 2 should not touch.
5. `## Phase 1: Gather state` (the Unit 1 payload, subsections 1a–1e).
6. `## Phase 2-5 (reserved)` placeholder. **Unit 2 replaces this** with `## Phase 2: Parse command` and friends, or removes it and inserts new phase sections above Source Precedence.
7. `## Source precedence (when sources conflict)`
8. `## Finalize (timeline complete)` — uses `${OUTCOME:-success}`; Units 2–4 should set `OUTCOME` based on workflow result.
9. `## Important rules`

### Design calls Unit 2 should know about

- **Warning format is contractual.** Unit 2's command-parsing warnings (unknown arg, ambiguous role) must use the same `[warning: {source} not available -- {reason} -- {what was skipped}]` shape, with `{source}` being e.g. `command argument` and `{what was skipped}` describing the default that kicked in. The receiving agent parses these uniformly.
- **Spawned-session flag.** Preamble prints `SPAWNED_SESSION: true|false`. When true, Unit 2 must auto-pick defaults for any ambiguity instead of calling `AskUserQuestion`.
- **Review vs. reviewer.** Enforced in the SKILL.md description and the plan: `review` is a message type, `reviewer` is a role. Unit 2's parser should treat the literal tokens that way — no alias collision.
- **Multiple active plans.** Phase 1b outputs ALL matching paths, one per line. Unit 2 must not assume a single plan; the templates in Unit 2 / the assembly in Unit 4 should enumerate plan paths or pick via `AskUserQuestion` when not in a spawned session.
- **Conversation synthesis wording.** Phase 1e embeds the plan's verbatim LLM instruction for session decisions + open questions (including the `[no session decisions captured -- conversation context unavailable]` fallback). If Unit 2 rewords it, keep the `[inferred from session]` prefix and the fabrication prohibition.
- **Grep anchor.** Plan discovery uses `grep "^status: active"` (anchored to line start, no `$` terminator). Matches the plan spec; Unit 2 inherits any false-positive risk (a prose line that starts with `status: active` at column 0 would match — accepted).
- **Slug fallback.** When `gstack-slug` is absent, `SLUG` becomes `unknown` and the checkpoint lookup at `~/.gstack/projects/unknown/checkpoints/` almost always misses — which is fine because a warning is emitted. Unit 2's artifact path `~/.claude/handoffs/{slug}/` will inherit the same fallback; if `slug=unknown`, the handoff lives under `~/.claude/handoffs/unknown/`, which is acceptable but worth calling out in Unit 4's cleanup logic.

### No blockers
Unit 1 delivered state gathering; Unit 2 (command parsing + templates) can start immediately against the `## Phase 2-5 (reserved)` anchor. No open questions for the orchestrator.
