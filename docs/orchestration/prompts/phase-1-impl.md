# Phase 1 — Implement Unit 2 of the session-handoff skill

You are the implementation agent for **Unit 2** of the session-handoff skill.

Your working directory is `C:\Users\dunliu\projects\claude-skills\`. Stay
inside this repo.

## Source of truth

Read in this order before writing anything:

1. `docs/plans/2026-04-15-001-feat-session-handoff-skill-plan.md` — the
   plan. Your scope is the section titled "Unit 2: Command parsing,
   message types, and role templates."
2. `docs/orchestration/signals/phase-0-impl-complete.md` — the handoff
   note from Phase 0. It lists the files Unit 1 created and any design
   choices you need to preserve.
3. `skills/session-handoff/SKILL.md` — current skill as Unit 1 left it.
4. `skills/session-handoff/references/message-templates.md` — still empty
   or a header-only skeleton from Unit 1.

## What to build (Unit 2 scope)

Implement exactly what Unit 2 specifies, and no more:

1. **Command parsing** inside `SKILL.md`: parse the two-axis grammar
   `/session-handoff [message-type] [target-role] [-- instructions]` per
   the plan. First known message type wins; then first known role; then
   everything after `--` is free-form instructions.
2. **Backward compatibility**: `/session-handoff qa` (unknown first arg
   that happens to be a known role) must still work — interpret as
   handoff type, qa role.
3. **Disambiguation**: `review` is always a message type, `reviewer` is
   always a role. No collision.
4. **Role preambles** in `references/message-templates.md`: 5 specific
   preambles for `coord`, `impl`, `qa`, `reviewer`, `general`, with the
   opening lines the plan specifies verbatim (or very close).
5. **Message type overrides** in `references/message-templates.md`: 5
   section-ordering / emphasis rules for `handoff`, `brief`, `assign`,
   `review`, `report`. DRY composition — one base template, role preamble
   insert, type-specific section ordering.

## Files you will modify

- `skills/session-handoff/SKILL.md` — add a command-parsing section.
  Keep Unit 1's state-gathering and frontmatter intact.
- `skills/session-handoff/references/message-templates.md` — add Base
  Template, Role Preambles, and Message Type Overrides sections.

Do not touch `references/sanitization-patterns.md` — that is Unit 3's
scope.

## Patterns to follow

- `~/.claude/skills/checkpoint/SKILL.md` — command detection pattern
  (parse input, detect subcommand).

## Verification checklist (from the plan)

Before signalling completion, confirm all five:

- [ ] All 5 message types produce structurally different output (composed
      from base + type overrides).
- [ ] All 5 roles produce different preambles.
- [ ] Custom instructions after `--` are appended to the instructions
      section.
- [ ] Backward-compatible: `/session-handoff qa` still works.
- [ ] No ambiguity: `review` is always a message type, `reviewer` is
      always a role.

## Test scenarios to think through

Nine scenarios listed in Unit 2's "Test scenarios" section. Walk through
each mentally — for every one, the SKILL.md parsing logic and template
composition should produce the documented behavior.

## When you are done

Create the completion signal. Use the absolute path to avoid cwd ambiguity:

```powershell
$signal = 'C:\Users\dunliu\projects\claude-skills\docs\orchestration\signals\phase-1-impl-complete.md'
New-Item -ItemType File -Path $signal -Force -Value @"
# Phase 1 (Unit 2) complete

## Files modified
- skills/session-handoff/SKILL.md (added command parsing)
- skills/session-handoff/references/message-templates.md (added base template, role preambles, type overrides)

## Verification
- [x] 5 message types structurally distinct
- [x] 5 role preambles distinct
- [x] Custom instructions after `--` threaded to output
- [x] Backward-compat preserved
- [x] review/reviewer disambiguation explicit

## Handoff notes for Unit 3
<anything the next phase needs — sanitization will modify SKILL.md and references/sanitization-patterns.md>
"@
```

## Guardrails

- Do not implement Unit 3 (sanitization), Unit 4 (two-tier output +
  artifacts), or Unit 5 (example output + quickstart).
- Do not edit `references/sanitization-patterns.md` — Unit 3's file.
- Do not touch files outside `skills/session-handoff/` except for
  creating the completion signal.
- If blocked, write the completion signal with `status: blocked` so the
  orchestrator can advance or time out cleanly.
