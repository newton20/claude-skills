---
schema_version: 1
agent: impl
phase: phase-3-unit4
status: complete
timestamp: 2026-04-19T04:44:48Z
git_commit: none
---

## Summary

Implemented Unit 4 (two-tier output + artifact management) by adding two
new sections to `skills/session-handoff/SKILL.md`: an `## Auto-cleanup
(run before Phase 1)` block between the preamble and Phase 1 (so the
14-day pruning fires before state gathering), and full `## Phase 4:
Assemble` + `## Phase 5: Output` sections replacing the Phase 4-5
reserved stub. Phase 4 covers preamble substitution, Base-Template
section rendering with per-section provenance tagging, message-type
override selection, INSTRUCTIONS threading, short-prompt assembly with a
documented truncation priority, full-artifact YAML frontmatter assembly,
artifact-path derivation, and provenance-marker stripping. Phase 5
sequences the Phase 3 sanitize → strip provenance → mkdir → write →
clipboard → print pipeline, with canonical 3-segment warnings for every
failure mode (cleanup, mkdir, write, clipboard). Unit 1/2/3 sections are
untouched.

## Files modified
- skills/session-handoff/SKILL.md — added `## Auto-cleanup (run before Phase 1)` between the preamble and Phase 1; added `## Phase 4: Assemble` (steps 4a–4i) and `## Phase 5: Output` (steps 5.1–5.7) replacing the Phase 4-5 reserved stub

## Files deliberately NOT modified
- skills/session-handoff/references/message-templates.md — Unit 2's file (consumed, not edited)
- skills/session-handoff/references/sanitization-patterns.md — Unit 3's file (consumed, not edited)
- Phase 1, 2, 3 sections of SKILL.md (preamble, Phase 1a–1e, Phase 2 parsing + worked examples, Phase 3 sanitize contract)
- Frontmatter, HARD GATE, pre-resolved context, source precedence, finalize, important rules — all preserved verbatim

## Design calls the next phase (Unit 5) should know about

### Exact short-prompt shape

Unit 5's example output must reproduce this shape verbatim (the
receiving agent and the human user see the same structure):

```
## Handoff Prompt (copy this)

```
{SHORT_PROMPT}
```

Full artifact saved to: {artifact_path}
```

`{SHORT_PROMPT}` itself is plain markdown — H2 headings only, no YAML
frontmatter, no artifact-body H1. It opens with the role preamble
(with `{phase}` / `{plan_path}` substituted for `impl`) and closes
with the literal line:

```
If on the same machine, read `{artifact_path}` for additional detail.
```

Unit 5 should pick values that make the substitutions visible (for
`impl`: a real-looking plan title and path) so the synthetic example
teaches the substitution rule without looking like fabricated prose.

### Exact artifact frontmatter field order

Unit 5's example artifact MUST use this field order (downstream tooling
in V2 will parse positionally):

```yaml
---
schema_version: 1
type: <handoff|brief|assign|review|report>
role: <coord|impl|qa|reviewer|general>
branch: <branch or "unknown">
sha: <short HEAD SHA or "unknown">
timestamp: <ISO 8601>
source_session_id: <_SESSION_ID from preamble>
warnings:
  - <warning 1>
  - <warning 2>
---
```

When `warnings` is empty, render `warnings: []` literally. Unit 5's
synthetic example should show at least one warning to teach the block
shape, and should also include a `(no warnings)` rendering in the body
`## Warnings` section to teach the visible-empty-state convention.

### Artifact path convention

`~/.claude/handoffs/{SLUG}/{TIMESTAMP}-{MSG_TYPE}-{TARGET_ROLE}.md`

- `{TIMESTAMP}` is `YYYYMMDD-HHMMSS` local time (matches the
  checkpoint skill so handoffs and checkpoints sort consistently).
- `{SLUG}` falls back to `unknown` when gstack-slug is absent — the
  path becomes `~/.claude/handoffs/unknown/...` in that case. Unit 5
  should NOT show the `unknown` fallback in the primary example
  (picks a real-looking slug like `claude-skills`), but may mention it
  in passing prose.

### Truncation priority — how it presents to the user

Truncation is silent from the user's point of view: Unit 4 just
produces a shorter prompt. There is no visible truncation marker,
ellipsis, or "[truncated]" label. The guarantee is that the
invariants (role preamble, branch/SHA, instructions/threaded
INSTRUCTIONS, warnings, artifact pointer) always survive. Unit 5's
example should NOT demonstrate a truncated prompt; pick a
small-enough synthetic project that the natural output fits under
2000 chars.

### Canonical warning shapes introduced in Unit 4

All use the Unit 1 3-segment contract. Unit 5's example should show at
least one of these to teach the shape:

| Step | Warning |
|---|---|
| Auto-cleanup | `[warning: handoff cleanup -- {reason} -- stale artifacts not removed]` |
| mkdir | `[warning: artifact write failed -- could not create {path} -- full artifact not saved to disk]` |
| Write | `[warning: artifact write failed -- {reason} -- full artifact not saved to disk]` |
| Clipboard (no tool) | `[warning: clipboard copy failed -- clip.exe/pbcopy/xclip not found -- copy the prompt above manually]` |
| Clipboard (tool failed) | `[warning: clipboard copy failed -- {tool} returned non-zero exit status -- copy the prompt above manually]` |

### Where the clipboard-failure warning lands in stdout

When clipboard copy fails, the warning prints on its own line between
the closing fence of the short-prompt code block and the "Full
artifact saved to" line. Unit 5's example should show this layout if
it demonstrates the clipboard failure mode. When the artifact-write
warning fires, it REPLACES the "Full artifact saved to" line (so the
user does not chase a file that was never written).

### Provenance markers are not output

Unit 4 tags each assembled section with an internal `origin=...`
marker that Phase 3 consumes. Phase 5 step 5.2 strips every marker
before anything reaches stdout, clipboard, or disk. Unit 5's example
should NEVER show `origin=...` in the example output — it is purely
internal.

### OUTCOME semantics (for the finalize timeline event)

`success` is the default: clipboard or artifact-write failures emit
warnings, not errors. Only Phase 4 assembly failure or user abort
changes OUTCOME. Unit 5 does not need to show OUTCOME in the example
(it only appears in the gstack timeline log, not the user-visible
output), but the quickstart may mention it in passing.

### HARD GATE language is now slightly stale

The top-of-file HARD GATE still says "(artifact writing is implemented
in Unit 4)" and the Important rules section has the same parenthetical.
Both are now factually fulfilled but read as forward-looking. Unit 5's
documentation polish can rewrite these to past-tense / present-tense
without changing the contract. (Left intentionally for Unit 5 since
that unit owns documentation polish.)

## Blockers / open questions

none

## Verification performed
- [x] Short prompt shape matches plan (self-contained, under 2500 chars) — documented in 4f (structure) and 4g (truncation invariants)
- [x] Truncation priority documented — step 4g lists the three cut tiers (plan details → status details → decisions/open-questions body) and the always-keep invariants (preamble, branch/SHA, INSTRUCTIONS, warnings, artifact pointer)
- [x] Artifact YAML frontmatter complete — step 4h enumerates `schema_version`, `type`, `role`, `branch`, `sha`, `timestamp`, `source_session_id`, `warnings` with field order and empty-state rule (`warnings: []`)
- [x] Cleanup runs before state-gathering, not after — the `## Auto-cleanup (run before Phase 1)` section is placed between the preamble and `## Phase 1: Gather state`; the explanatory copy makes the ordering rationale explicit
- [x] Clipboard fallback warning uses canonical shape — step 5.5 emits `[warning: clipboard copy failed -- clip.exe/pbcopy/xclip not found -- copy the prompt above manually]` and the tool-specific variant with the same 3-segment structure
- [x] Phase 3 integration preserves over-redaction rule — step 5.1 explicitly states "Do NOT bypass or weaken Phase 3" and repeats the over-redaction clause; Phase 4's provenance tagging provides the `{origin}` metadata Phase 3 needs for the known-origin replacement template
- [x] Artifact directory auto-creation on first run — step 5.3 uses `mkdir -p` (idempotent) with a canonical warning on failure; first-run cleanup is a no-op (`[ -d ]` guard) so the skill works cleanly on a machine that has never run the skill before
