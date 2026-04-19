# Phase 4 — Implement Unit 5 of the session-handoff skill (example output + quickstart docs)

You are the implementation agent for **Unit 5** of the session-handoff skill.

Your working directory is `C:\Users\dunliu\projects\claude-skills\`. Stay inside this repo. This is the final phase — the skill should be end-user-ready when you're done.

## Source of truth (read in this order)

1. `docs/plans/2026-04-15-001-feat-session-handoff-skill-plan.md` — the plan. Your scope is the section titled "Unit 5: Example output and quickstart documentation."
2. `docs/orchestration/signals/phase-0-impl-complete.md` through `phase-3-impl-complete.md` — the four prior phases' handoff notes. Unit 4's notes specifically describe the exact short-prompt shape and artifact YAML frontmatter field order your example must mirror.
3. `skills/session-handoff/SKILL.md` — current state after Units 1–4.
4. `skills/session-handoff/references/message-templates.md` — role preambles and message-type overrides. Your example should show one of each composed properly.

## What to build (Unit 5 scope — and no more)

Implement the plan's Unit 5 approach exactly:

1. **"## Quick Start" block at the top of SKILL.md**, immediately after the frontmatter and HARD GATE, before Pre-resolved context. Keep it ~5 lines:
   ```
   ## Quick Start

   ```bash
   git clone <repo> ~/.claude/skills/session-handoff
   # Then in any project:
   /session-handoff                    # default: handoff for general role
   /session-handoff brief coord        # briefing for coordinator
   /session-handoff assign qa -- test the booking flow
   ```
   ```
2. **"## Example Output" section near the end of SKILL.md**, after `## Important rules`. Show TWO artifacts for ONE synthetic scenario:
   - A realistic **short prompt** (what the clipboard gets, ~2000 chars), with all placeholders resolved to a synthetic project (e.g., `yoga-house` rebuild, Phase 2 handoff to impl agent).
   - The corresponding **full artifact** (with YAML frontmatter per Unit 4's schema).
   The example must demonstrate: role preamble, branch/SHA line, status summary, plan reference, at least one `[inferred from session]` tag, at least one `[warning: ...]` warning line, and a `[REDACTED -- see CLAUDE.md]` replacement (so the sanitization path is visible).
   Use fake-but-plausible data. No real API keys, no real file paths from the user's actual projects.
3. **Trigger phrases in frontmatter description.** The Unit 1 description already has trigger phrases. Verify they cover: `handoff`, `session handoff`, `fresh context`, `new session`, `brief the coordinator`, `create a playbook prompt`, `pass this to another session`, `hand off to {role}`. Add any missing ones.
4. **Prerequisites section.** A short "## Prerequisites" block (after Quick Start, before Pre-resolved context) listing: Claude Code CLI, a git repo (optional — skill handles its absence), a `docs/plans/` directory (optional), write access to `~/.claude/handoffs/`. Keep it scannable.

## Verification checklist (from the plan)

- [ ] Example output is realistic and demonstrates both tiers (short prompt + artifact).
- [ ] Example shows every major feature: role preamble, git state, plan reference, inferred tag, warning shape, sanitization replacement.
- [ ] Install instructions work from a clean machine (`git clone ~/.claude/skills/session-handoff`, then `/session-handoff` works).
- [ ] Trigger phrases cover the user's vocabulary from session history.
- [ ] Prerequisites section is honest about what the skill needs and what it degrades gracefully without.

## Patterns to follow

- Other skills in `~/.claude/skills/` that have Example Output sections — `checkpoint/SKILL.md` if it has one, otherwise mirror the concise style used in `compound-engineering` plugin skill files.

## What you must NOT touch

- Units 1–4's Phase sections in SKILL.md. You are only adding the Quick Start, Prerequisites, and Example Output blocks. You are not editing the phase pipelines.
- `references/message-templates.md` and `references/sanitization-patterns.md` — done by Units 2 and 3.

## When you are done

Write the completion signal (structured schema, absolute path):

```powershell
$signal = 'C:\Users\dunliu\projects\claude-skills\docs\orchestration\signals\phase-4-impl-complete.md'
New-Item -ItemType File -Path $signal -Force -Value @"
---
schema_version: 1
agent: impl
phase: phase-4-unit5
status: complete
timestamp: <ISO 8601>
git_commit: none
---

## Summary
Session-handoff skill end-user-ready. <1-2 sentences on what the example demonstrates.>

## Files modified
- skills/session-handoff/SKILL.md — added Quick Start, Prerequisites, Example Output

## Files deliberately NOT modified
- skills/session-handoff/references/message-templates.md — Unit 2's file
- skills/session-handoff/references/sanitization-patterns.md — Unit 3's file
- Phase 1-5 sections of SKILL.md — preserved verbatim

## Design calls the next phase should know about
(No next phase. This is the final unit.)
- For V2 (deferred in plan): the `/session-receive` command would parse incoming short prompts. Your artifact frontmatter (`schema_version: 1`) is the forward-compat anchor.
- For user-facing install: document any gap you found while writing the Quick Start.

## Blockers / open questions
<or "none">

## Verification performed
- [x] Quick Start block in place
- [x] Prerequisites block in place
- [x] Example Output demonstrates both tiers
- [x] Example includes role preamble, git state, plan ref, [inferred], [warning], [REDACTED]
- [x] Trigger phrases cover user vocabulary
- [x] No real secrets / real file paths in the example
"@
```

If blocked, set `status: blocked` with Blockers populated.

## Scope guardrails

- This is the final unit. No "Unit 6" to defer to. If you discover a gap, document it in the handoff notes as an issue for future maintenance, not as scope you absorb.
- Do NOT commit. The skill is still living under the claude-skills repo as uncommitted work.
- Do NOT install the skill to `~/.claude/skills/` — the install step is documented in Quick Start but is the user's action, not yours. Your job is to leave the skill shippable.
