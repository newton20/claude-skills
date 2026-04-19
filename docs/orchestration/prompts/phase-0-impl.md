# Phase 0 — Implement Unit 1 of the session-handoff skill

You are the implementation agent for **Unit 1** of the session-handoff skill.

Your working directory is `C:\Users\dunliu\projects\claude-skills\`. Stay
inside this repo unless the plan explicitly directs you elsewhere.

## Source of truth

Read the plan in full before you write any code:

- `docs/plans/2026-04-15-001-feat-session-handoff-skill-plan.md`

Your scope is **Unit 1 only** (section titled "Unit 1: Skill scaffold,
gstack conventions, and state gathering"). Do not implement Units 2–5 —
those run in later phases.

## Where to put files

Create skill source files under `skills/session-handoff/` in this repo (this
directory does not exist yet). Path mapping from the plan's `Files` field to
the real location on disk:

| Plan path | Real path in this repo |
|---|---|
| `SKILL.md` | `skills/session-handoff/SKILL.md` |
| `references/message-templates.md` | `skills/session-handoff/references/message-templates.md` |
| `references/sanitization-patterns.md` | `skills/session-handoff/references/sanitization-patterns.md` |

Installation to `~/.claude/skills/session-handoff/` is a separate step and
is **out of scope** for this phase. Version-control the sources here first.

## What to build

Implement exactly what Unit 1 specifies:

1. `SKILL.md` with valid gstack-compatible YAML frontmatter: `name:
   session-handoff`, description with trigger phrases, `preamble-tier: 1`.
2. A minimal gstack preamble inside `SKILL.md`: slug resolution, timeline
   logging (skill start/complete), session tracking. No telemetry, no voice
   section, no lake intro.
3. State-gathering instructions that cover git state (branch, short HEAD
   SHA, worktree dirty flag via `git status --porcelain`, `git status
   --short`, `git log --oneline -5`, `git diff --stat`), plan discovery
   (active plans under `docs/plans/`), latest checkpoint under
   `~/.gstack/projects/*/checkpoints/`, and CLAUDE.md presence.
4. Structured warnings for each missing source in the documented format:
   `[warning: {source} not available -- {reason} -- {what was skipped}]`
5. Explicit LLM instructions for conversation synthesis with `[inferred
   from session]` tags (see Unit 1 "Approach" for the exact wording the
   plan expects).
6. Skeleton files `references/message-templates.md` and
   `references/sanitization-patterns.md` — empty is fine for Unit 1; Units
   2 and 3 populate them. Include a one-line header in each so the file is
   self-documenting.

## Patterns to follow

The plan cites these as references. Read them before designing your output
format:

- `~/.claude/skills/checkpoint/SKILL.md` — look at git state gathering and
  the structured markdown output with YAML frontmatter.
- `~/.claude/skills/ce-sessions/SKILL.md` or similar — pre-resolved context
  in frontmatter via backtick commands.

## Verification checklist (from the plan)

Before signalling completion, confirm all four:

- [ ] `SKILL.md` exists with valid gstack-compatible frontmatter.
- [ ] State gathering produces output for each available source.
- [ ] Missing sources produce structured warnings, not silent omission.
- [ ] HEAD SHA and worktree dirty flag are captured.

## Test scenarios to think through

Work through the six scenarios listed in Unit 1's "Test scenarios" section
mentally. For each, the SKILL.md instructions should describe observable
behavior. No automated tests needed for Unit 1 — this is a skill definition,
not a compiled artifact.

## When you are done

Create the completion signal file. The orchestrator polls for this file
every 30 seconds and will advance to Phase 1 (Unit 2) as soon as it appears.

Use the absolute path below to eliminate any cwd ambiguity:

```powershell
$signal = 'C:\Users\dunliu\projects\claude-skills\docs\orchestration\signals\phase-0-impl-complete.md'
New-Item -ItemType File -Path $signal -Force -Value @"
# Phase 0 (Unit 1) complete

## Files created
- skills/session-handoff/SKILL.md
- skills/session-handoff/references/message-templates.md
- skills/session-handoff/references/sanitization-patterns.md

## Verification
- [x] SKILL.md frontmatter valid
- [x] State gathering covers git / plan / checkpoint / CLAUDE.md
- [x] Warning format matches spec
- [x] HEAD SHA and dirty flag captured

## Notes for Phase 1 (Unit 2)
<anything the next phase needs to know — blockers, design choices, open questions>
"@
```

The notes section matters. Unit 2 modifies `SKILL.md` and
`references/message-templates.md` — if you named sections differently than
the plan suggests, or made any design calls worth flagging, put them here.

## Guardrails

- Do not start Unit 2, 3, 4, or 5. Even if you have spare time.
- Do not install to `~/.claude/skills/`. Stay in this repo.
- Do not run `gstack-upgrade` or any other commands that touch user-owned
  skills. You are only authoring source files.
- If blocked, write the completion signal with a `status: blocked` note
  instead of silently stopping — the orchestrator needs some signal file
  to advance or to time out cleanly.
