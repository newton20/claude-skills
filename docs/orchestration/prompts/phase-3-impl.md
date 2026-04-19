# Phase 3 — Implement Unit 4 of the session-handoff skill (two-tier output + artifact management)

You are the implementation agent for **Unit 4** of the session-handoff skill.

Your working directory is `C:\Users\dunliu\projects\claude-skills\`. Stay inside this repo.

## Source of truth (read in this order)

1. `docs/plans/2026-04-15-001-feat-session-handoff-skill-plan.md` — the plan. Your scope is the section titled "Unit 4: Two-tier output and artifact management."
2. `docs/orchestration/signals/phase-0-impl-complete.md` — Unit 1's handoff notes.
3. `docs/orchestration/signals/phase-1-impl-complete.md` — Unit 2's handoff notes. Contains the `INSTRUCTIONS` threading rules by message type (`handoff` / `brief` / `assign` / `review` / `report`) that your assembly must implement.
4. `docs/orchestration/signals/phase-2-impl-complete.md` — Unit 3's handoff notes. Contains where sanitization runs in the pipeline and any constraints it places on your output path.
5. `skills/session-handoff/SKILL.md` — current skill after Units 1, 2, 3.
6. `skills/session-handoff/references/message-templates.md` — Unit 2's template library. Your assembly consumes this.

## What to build (Unit 4 scope — and no more)

Implement the plan's Unit 4 approach exactly:

1. **Short prompt (~2000 chars target, max 2500).** Self-contained. Role preamble + project/branch/SHA + status one-liner + plan path + decisions + open questions + key instructions. Ends with: "If on the same machine, read `{artifact_path}` for additional detail."
2. **Truncation priority when short prompt exceeds target.** Documented in SKILL.md: cut plan details first, then status details. Always keep: role preamble, branch/SHA, instructions, artifact path reference.
3. **Full artifact on disk.** Complete structured document with YAML frontmatter (`schema_version: 1`, `type`, `role`, `branch`, `sha`, `timestamp`, `source_session_id`), all gathered state from Phase 1, all warnings from Phase 1 + Phase 2, all template-fragment composition from Phase 2, sanitized per Phase 3.
4. **Artifact path.** `~/.claude/handoffs/{project-slug}/{timestamp}-{type}-{role}.md`. Use the `SLUG` resolved in Phase 1; if `SLUG=unknown`, artifact lives under `~/.claude/handoffs/unknown/` (Unit 1's handoff notes flagged this as acceptable).
5. **Auto-cleanup at skill start.** `find ~/.claude/handoffs/{project-slug}/ -name "*.md" -mtime +14 -delete`. Run this BEFORE gathering state, not after output. Emit a canonical warning if the cleanup errors (`[warning: handoff cleanup -- {reason} -- stale artifacts not removed]`).
6. **Clipboard copy with fallback.** Try `clip.exe` (Windows), `pbcopy` (Mac), `xclip -selection clipboard` (Linux). On failure emit: `[warning: clipboard copy failed -- {command} not found -- copy the prompt above manually]`. The prompt is still displayed in full; the warning just tells the user to copy by hand.
7. **SKILL.md structure.** Add `## Phase 4: Assemble` (short prompt + full artifact composition) and `## Phase 5: Output` (sanitize -> clipboard -> write artifact -> display). Remove or collapse the `## Phase 4-5 (reserved)` stub.
8. **Integration with Phase 3 sanitization.** Phase 3's output is the input to Phase 5. Do NOT rewrite Phase 3; call it between assembly and output. Respect its "over-redaction is preferred" contract.

## Verification checklist (from the plan)

- [ ] Short prompt fits in a typical clipboard and is immediately actionable (under 2500 chars for a full project; fewer for minimal projects).
- [ ] Full artifact has complete context including all sources and warnings.
- [ ] No secrets in either output tier (rely on Phase 3 sanitization).
- [ ] Auto-cleanup runs without errors on first invocation when the directory does not exist.
- [ ] Artifact YAML frontmatter contains `schema_version`, `type`, `role`, `branch`, `sha`, `timestamp`, `source_session_id`.
- [ ] When clipboard command fails, warning emitted, prompt still displayed.
- [ ] When artifact directory does not exist, it is created automatically.
- [ ] Truncation priority rule written explicitly in Phase 4 of SKILL.md.

## Patterns to follow

- `~/.claude/skills/checkpoint/SKILL.md` structured markdown output with YAML frontmatter (mentioned by Unit 1 as the reference).

## What you must NOT touch

- Unit 1's state-gathering sections in SKILL.md.
- Unit 2's Phase 2 parsing section and the role preambles / message-type overrides in `references/message-templates.md`.
- Unit 3's Phase 3 sanitization section and `references/sanitization-patterns.md`.

## When you are done

Write the completion signal (structured schema, absolute path):

```powershell
$signal = 'C:\Users\dunliu\projects\claude-skills\docs\orchestration\signals\phase-3-impl-complete.md'
New-Item -ItemType File -Path $signal -Force -Value @"
---
schema_version: 1
agent: impl
phase: phase-3-unit4
status: complete
timestamp: <ISO 8601>
git_commit: none
---

## Summary
<2-4 sentences.>

## Files modified
- skills/session-handoff/SKILL.md — added Phase 4 (Assemble) + Phase 5 (Output); removed Phase 4-5 reserved stub

## Files deliberately NOT modified
- skills/session-handoff/references/message-templates.md — Unit 2's file (consumed, not edited)
- skills/session-handoff/references/sanitization-patterns.md — Unit 3's file (consumed, not edited)
- Phase 1, 2, 3 sections of SKILL.md

## Design calls the next phase should know about
<what Unit 5 (example output + docs) must reflect in its example: exact short prompt shape, exact artifact frontmatter field order, how truncation presents itself, where the clipboard fallback warning appears, etc.>

## Blockers / open questions
<or "none">

## Verification performed
- [x] Short prompt shape matches plan (self-contained, under 2500 chars)
- [x] Truncation priority documented
- [x] Artifact YAML frontmatter complete
- [x] Cleanup runs before state-gathering, not after
- [x] Clipboard fallback warning uses canonical shape
- [x] Phase 3 integration preserves over-redaction rule
- [x] Artifact directory auto-creation on first run
"@
```

If blocked, set `status: blocked` with Blockers populated.

## Scope guardrails

- Do NOT implement Unit 5 (example output + docs).
- Do NOT commit. Leave uncommitted for the user to review.
- Do NOT write an actual example artifact to `~/.claude/handoffs/` as part of implementation — that is Unit 5's documentation scope, and it uses a synthetic project.
