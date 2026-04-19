# Phase 2 — Implement Unit 3 of the session-handoff skill (sanitization pipeline)

You are the implementation agent for **Unit 3** of the session-handoff skill.

Your working directory is `C:\Users\dunliu\projects\claude-skills\`. Stay inside this repo.

## Source of truth (read in this order)

1. `docs/plans/2026-04-15-001-feat-session-handoff-skill-plan.md` — the plan. Your scope is the section titled "Unit 3: Sanitization pass."
2. `docs/orchestration/signals/phase-0-impl-complete.md` — Unit 1's handoff notes. Contains the canonical warning format and SKILL.md section structure you must preserve.
3. `docs/orchestration/signals/phase-1-impl-complete.md` — Unit 2's handoff notes. Contains the Phase 2 parser output contract, `INSTRUCTIONS` threading rules, and notes on what sanitization must NOT touch (Phase 2 warning quoted tokens).
4. `skills/session-handoff/SKILL.md` — current skill after Units 1 and 2.
5. `skills/session-handoff/references/sanitization-patterns.md` — one-line skeleton Unit 1 left for you. You populate it.

## What to build (Unit 3 scope — and no more)

Implement the plan's Unit 3 approach exactly:

1. **Sanitization phase in `SKILL.md`.** Add a `## Phase 3: Sanitize` section between Phase 2 (parse command) and the existing `## Phase 3-5 (reserved)` stub. Move the stub to `## Phase 4-5 (reserved)`. The sanitization phase runs on assembled content BEFORE output (i.e. between Phase 4 assembly and Phase 5 output — but the contract lives in Phase 3 so the regex library is loaded and available early).
2. **Pattern library in `references/sanitization-patterns.md`.** Populate with regex categories from the plan:
   - API key shapes: `sk-`, `key-`, `token-`, base64 blocks > 20 chars
   - Env-var values: lines matching `=` preceded by names containing `KEY`, `SECRET`, `TOKEN`, `PASSWORD`, `CREDENTIAL`
   - Known service patterns: Supabase (`sb_`), Vercel tokens, AWS (`AKIA`), Anthropic (`sk-ant-`)
   - URLs with embedded credentials: `://user:pass@`
3. **Replacement format.** When a match's source file is known: `[REDACTED -- see {original_filepath}]`. When not: `[REDACTED -- potential secret removed]`. Document both in Phase 3 of SKILL.md.
4. **Over-redaction is preferred to under-redaction.** Say so explicitly in Phase 3. Note the acceptable false-positive case: commit SHAs that look like keys.
5. **Skill-loading failure handling.** If `references/sanitization-patterns.md` has malformed regex, skip sanitization with a canonical warning (`[warning: sanitization skipped -- malformed pattern in references/sanitization-patterns.md -- output emitted without redaction]`) and still emit the output. Use the same 3-segment warning shape Unit 1 established.

## What you must NOT touch

- `skills/session-handoff/references/message-templates.md` — Unit 2's file. Don't edit.
- Unit 1's frontmatter, pre-resolved context, preamble, Phase 1a-1e, source precedence, finalize, and important rules sections in SKILL.md.
- Unit 2's Phase 2 section in SKILL.md — its `INSTRUCTIONS` threading, worked examples, and warning strings must be preserved. **Per Unit 2's handoff notes: Phase 2 warning strings contain quoted tokens like `"<token>"` which are user input and may contain arbitrary characters. These are NOT secrets. Your sanitizer must target known secret shapes (sk-, AKIA, base64 blocks), not quoted strings. Do not over-redact Phase 2 warnings.**

## Patterns to follow

- `git-secrets` and `truffleHog` regex libraries for API-key detection.
- Unit 1's warning shape `[warning: {source} not available -- {reason} -- {what was skipped}]`.

## Verification checklist (from the plan)

Before signalling completion, confirm:

- [ ] No raw API keys, tokens, or passwords appear in either short-prompt or full-artifact output (the skill's output targets, Unit 4 builds them).
- [ ] File path references to secrets are preserved (the path is not a secret).
- [ ] Over-redaction is preferred over under-redaction — note this rule in Phase 3.
- [ ] `SUPABASE_KEY=sb_publishable_xxx` in CLAUDE.md would be replaced with `[REDACTED -- see CLAUDE.md]` (walk through mentally).
- [ ] Phase 2 warning quoted tokens are NOT redacted.

## When you are done

Write the completion signal using the structured schema from agent-orchestrator's protocol header. Use absolute paths:

```powershell
$signal = 'C:\Users\dunliu\projects\claude-skills\docs\orchestration\signals\phase-2-impl-complete.md'
New-Item -ItemType File -Path $signal -Force -Value @"
---
schema_version: 1
agent: impl
phase: phase-2-unit3
status: complete
timestamp: <ISO 8601>
git_commit: none
---

## Summary
<2-4 sentences on what you implemented.>

## Files modified
- skills/session-handoff/SKILL.md — added Phase 3: Sanitize; moved reserved stub to Phase 4-5
- skills/session-handoff/references/sanitization-patterns.md — populated with four regex categories

## Files deliberately NOT modified
- skills/session-handoff/references/message-templates.md — Unit 2's scope
- Unit 1 + Unit 2 sections of SKILL.md — preserved as Unit 2's handoff notes required

## Design calls the next phase should know about
<specific rules Unit 4 must honor: where sanitization runs in the pipeline, how Phase 4 assembly integrates with it, warning shape for malformed patterns, anything about clipboard/artifact output that sanitization constrains>

## Blockers / open questions
<either specific blockers, or "none">

## Verification performed
- [x] No raw secrets in output paths (walked through mentally)
- [x] File path references preserved in replacement format
- [x] Over-redaction principle documented
- [x] Phase 2 warning tokens explicitly NOT redacted
- [x] Malformed-regex fallback uses Unit 1 canonical warning shape
"@
```

If blocked, set `status: blocked` and populate Blockers.

## Scope guardrails

- Do NOT implement Unit 4 (two-tier output + artifacts) or Unit 5 (example + docs).
- Do NOT commit. The repo is pre-initial-commit; leave that to the user.
- Do NOT edit files outside `skills/session-handoff/` except the completion signal.
