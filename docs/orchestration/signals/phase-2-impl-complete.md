---
schema_version: 1
agent: impl
phase: phase-2-unit3
status: complete
timestamp: 2026-04-19T04:36:18Z
git_commit: none
---

## Summary

Implemented Unit 3 (sanitization pipeline) by adding a `## Phase 3: Sanitize`
section to `skills/session-handoff/SKILL.md` between the Phase 2 parser and
the now-renamed `## Phase 4-5 (reserved)` stub, and populating
`skills/session-handoff/references/sanitization-patterns.md` with the four
regex categories from the plan (API key shapes, env-var values, known
service patterns, and URLs with embedded credentials). Phase 3 defines
both the contract (replacement templates, over-redaction preference,
malformed-pattern fallback) and the load-time sanity check, and
explicitly carves out Phase 2 warning quoted tokens as protected content.

## Files modified
- skills/session-handoff/SKILL.md — added `## Phase 3: Sanitize`; renamed reserved stub to `## Phase 4-5 (reserved)`
- skills/session-handoff/references/sanitization-patterns.md — populated with four labelled regex categories (was a one-line skeleton)

## Files deliberately NOT modified
- skills/session-handoff/references/message-templates.md — Unit 2's scope
- Unit 1 sections of SKILL.md (frontmatter, pre-resolved context, preamble, Phase 1a–1e, source precedence, finalize, important rules) — preserved verbatim
- Unit 2 section of SKILL.md (Phase 2: Parse command, worked examples, warning templates with quoted tokens) — preserved verbatim per Unit 2's handoff contract

## Design calls the next phase (Unit 4) should know about

### Where sanitization runs in the pipeline
Phase 3 is split by design: the pattern LIBRARY loads early (right after
Phase 2) so a malformed-pattern warning can be emitted before Unit 4
spends cycles on assembly; the pattern APPLICATION runs LATE, between
Phase 4 assembly and Phase 5 output. Unit 4 must call sanitization on
BOTH the short prompt AND the full artifact content strings after
assembling them, but BEFORE writing to disk, copying to clipboard, or
printing to stdout. Nothing leaves the skill unsanitized.

### Provenance tracking is Unit 4's responsibility
Phase 3's replacement templates need a `{original_filepath}` when the
secret came from an identifiable source. Unit 4 should track per-section
origin metadata during assembly so the sanitizer can choose
`[REDACTED -- see {filepath}]` (when origin is known) vs
`[REDACTED -- potential secret removed]` (when origin is unknown, e.g.
from conversation synthesis). Suggested approach: tag each assembled
section with an `origin=...` marker the sanitizer reads and strips, or
pass a per-section origin map into the sanitize step. If Unit 4 cannot
cheaply track provenance, the fallback template is always safe.

### Warnings collection contract
Phase 3 emits at most ONE warning (malformed / missing / unreadable
pattern file) and uses the canonical Unit 1 3-segment shape
`[warning: sanitization skipped -- {reason} -- output emitted without redaction]`.
This warning appends to the same `warnings:` block Phase 1 and Phase 2
populate. Unit 4's Base-Template `## Warnings` section must render it
alongside the other warnings. Inline `[REDACTED -- ...]` markers are
NOT warnings and do NOT go in the warnings block — they appear in the
body text where the match was found.

### Output tiers: sanitize both
Unit 4 produces a short prompt (~2000 chars) for clipboard and a full
artifact for disk. Both are subject to Phase 3 sanitization. The
replacement markers `[REDACTED -- see {filepath}]` and
`[REDACTED -- potential secret removed]` are short enough that they do
not blow the ~2000 char budget; the worst case is a URL-credential
rewrite that leaves the scheme and host visible. No special length
handling is required.

### Protected zones (must survive sanitization)
- **Phase 2 warning quoted tokens** — e.g. `"unknown-thing"`, `"qa"`,
  `"reviewer"`. These are user input echoed back for diagnosis. The
  patterns deliberately target only known secret shapes, not quoted
  strings. Confirmed: none of the four categories match a short quoted
  user token.
- **File paths** in replacement templates and references.
- **Warning strings themselves** — `[warning: ...]` lines are
  diagnostic metadata.
- **Pre-resolved context values** (slug, branch, short HEAD SHA,
  worktree flag). Short SHAs may trip the base64 pattern — this is the
  documented acceptable false positive; Unit 4 need do nothing extra.
- **Template fragments from `references/message-templates.md`** at
  load time. Sanitization applies to FINAL assembled output, not to
  template source files.

### Ordering within Phase 3 is not sensitive
The four categories can run in any order. When both env-var and API-key
patterns match the same fragment (e.g. `SUPABASE_KEY=sb_publishable_xxx`),
whichever runs first redacts the value; the later ones see only the
replacement marker and no-op. Unit 4 does not need to pick an order.

## Blockers / open questions
none

## Verification performed
- [x] No raw secrets in output paths (walked through mentally): env-var category replaces the RHS of `NAME=VALUE` lines with the REDACTED marker; API-key category catches prefix-labelled keys and long base64 blocks; service-specific category catches Supabase / Vercel / AWS / Anthropic / OpenAI / GitHub / Slack shapes; URL-credential category rewrites `user:pass@` with `REDACTED:REDACTED`. Union of the four categories covers the stated R6 requirement for both output tiers.
- [x] File path references preserved in replacement format: both templates document `[REDACTED -- see {original_filepath}]` with an explicit note that paths themselves are NOT secrets.
- [x] Over-redaction principle documented: dedicated "Over-redaction is preferred to under-redaction" subsection in Phase 3 plus a matching "Out of scope" note at the bottom of `sanitization-patterns.md`. Acceptable false positives enumerated: short commit SHAs, UUIDs, build hashes, diff-stat base64 fragments.
- [x] Phase 2 warning tokens explicitly NOT redacted: "What sanitization must NOT touch" subsection in Phase 3 lists Phase 2 warning quoted tokens first; `sanitization-patterns.md` "Out of scope" restates the same rule with the rationale. The four regex categories all target secret SHAPES (prefixes, long base64, secret-named env vars, credential URLs), none of which match `"unknown-thing"`, `"qa"`, or similar quoted user input.
- [x] Malformed-regex fallback uses Unit 1 canonical warning shape: `[warning: sanitization skipped -- malformed pattern in references/sanitization-patterns.md -- output emitted without redaction]` matches the `[warning: {source} not available -- {reason} -- {what was skipped}]` 3-segment contract Unit 1 established. Alternate reasons (file not found, file unreadable) use the same shape with a different reason segment.
- [x] `SUPABASE_KEY=sb_publishable_xxx` walkthrough: env-var pattern `(?i)\b([A-Z0-9_]*?(?:KEY|...)[A-Z0-9_]*)\s*[:=]\s*\S.*` matches the line, replaces the value side, result: `SUPABASE_KEY=[REDACTED -- see CLAUDE.md]` when provenance is CLAUDE.md. Service-specific Supabase pattern `\bsb_(?:publishable|secret)_...` is a belt-and-braces match that produces the same outcome if env-var runs second.
