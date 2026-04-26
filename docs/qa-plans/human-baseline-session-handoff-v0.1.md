---
title: "Human-authored test baseline — session-handoff v0.1"
type: human-baseline
status: complete
date: 2026-04-24
target: session-handoff v0.1 (commits 6f76e74..d70403e)
purpose: |
  Eval ground truth for /qa-plan dogfood metrics and TODO 006 A/B.
  Top-10 overlap against /qa-plan reviewed plans for the same diff
  range measures whether the adversarial pipeline catches the same
  cases a domain expert would prioritize. Also serves as the
  reference dataset for the one-hop alternative in TODO 006.
methodology: |
  Time-boxed 30 minutes of domain thinking against the
  session-handoff v0.1 SKILL.md surface (1513 lines, 5 phases,
  3 references files). No reviewer pipeline; this is one human's
  reading of the diff. Cases are listed in priority order — top
  10 first, then 6-10 supplementary cases for context.
todo: docs/todos/007-in-progress-p3-author-human-test-list-for-session-handoff-v0.1.md
related:
  - docs/dogfood/001-qa-plan-v0.1-findings.md
  - docs/qa-plans/20260423-095733-dogfood-qa-plan-v0.1-target-qa-plan.md
  - docs/qa-plans/20260423-221948-master-qa-plan.md
  - docs/qa-plans/20260423-232637-test-qa-plan-slug-verify-qa-plan.md
  - docs/qa-plans/20260424-205535-master-qa-plan.md
---

# Human-authored test baseline — session-handoff v0.1

This is the human-authored ground-truth test list for
session-handoff v0.1. It exists for two reasons:

1. **Calibrate `/qa-plan` Top-10 quality** — count overlap between
   this list and the Top-10 sections of the four `/qa-plan`
   reviewed plans for the same diff (Run #1, #2, #3, #4 against
   session-handoff v0.1 / qa-plan v0.2 / etc.). Per the v0.1 plan
   Success Metrics: ≥ 7/10 overlap is good signal; < 4/10 means
   the adversarial framing misses real bugs.
2. **Anchor TODO 006 A/B** — when the one-hop alternative
   (`/session-handoff assign qa -- review the diff, derive a test
   plan, run it, report findings`) emits its own list, compare
   against this baseline as well. The four-axis comparison is:
   one-hop vs human, `/qa-plan` vs human, one-hop vs `/qa-plan`
   absolute, and one-hop vs `/qa-plan` Top-10-only.

## Authoring constraints

- **30-minute time box.** No iteration after the timer.
- **Domain expert reading.** I read the SKILL.md once, the two
  reference files once, and listed cases as I went. No second pass.
- **No tooling access.** I did not run the skill, did not read
  any `/qa-plan` output, did not consult the codex review of any
  PR. This is a clean baseline.
- **Severity / likelihood subjective.** The same caveat that
  applies to `/qa-plan` Top-10 sev×lik scores applies here.

## Cases — Top-10 (priority order)

1. **Sanitization library load failure produces empty redaction
   set** — Phase 3 loads `references/sanitization-patterns.md`. If
   the file is missing, malformed, or only partially parsed, the
   skill must FAIL CLOSED (refuse to write artifact, emit warning)
   rather than write the handoff with no redaction. Risk: leak
   secrets to clipboard / disk.
   `[security, sev 5/5, lik 3/5, sev×lik=15, risk:privilege]`

2. **Verbatim AWS-key / GitHub-PAT in conversation buffer is
   redacted in BOTH short prompt and full artifact** — Phase 3 is
   the only line of defense between the user's terminal scrollback
   and the clipboard / disk. If a redaction pattern misses (or the
   library load partially succeeded — see #1), the secret reaches
   `~/.claude/handoffs/` and the system clipboard. Test verbatim
   AWS access keys (`AKIA...`), GitHub PATs (`ghp_...`),
   Anthropic / OpenAI keys, and at least one rotated-format
   variant.
   `[security, sev 5/5, lik 4/5, sev×lik=20, risk:privilege]`

3. **Phase 4j placeholder lint catches literal `{slot}` leaks
   inside code-fence inline backtick spans** — the lint covers
   "naive token replace failed" cases. If a slot like `{branch}`
   or `{plan_path}` survives substitution (e.g., a template
   fragment was loaded but the substitution loop skipped it), the
   short prompt copied to clipboard contains literal placeholder
   text. The fresh agent reads `{branch}` as a literal identifier
   and the handoff is broken silently. Test: every code-fence
   variant (triple-backtick block, single-backtick inline, fenced
   diff, etc.) with each known placeholder name.
   `[contract, sev 5/5, lik 3/5, sev×lik=15, risk:contract]`

4. **Phase 2 grammar — unknown token after `--` is treated as
   free-text instructions, not a parse error** — the `--` separator
   is the boundary between structured tokens (message-type, role)
   and free-text user instructions. Test: `/session-handoff assign
   qa -- ${some-shell-expression-the-user-meant-as-text}` and
   verify the right side is treated as a literal string in the
   prompt, not parsed.
   `[contract, sev 4/5, lik 4/5, sev×lik=16, risk:contract]`

5. **Phase 2 message-type token recognition is exact-match, no
   prefix or fuzzy** — the SKILL.md prose says "no aliases, no
   prefix matching." Test: `/session-handoff brie coord` (typo)
   should NOT silently auto-correct to `brief`; it should either
   reject or treat the whole thing as unknown. Same for `/sh
   asign qa` (prefix-only). The risk is the receiving agent
   getting a surprising role / message type because a typo got
   silently rewritten.
   `[contract, sev 4/5, lik 3/5, sev×lik=12, risk:contract]`

6. **No-git-repo path: short prompt is still written + clipboard
   still copies + warning emitted** — Phase 1a says git is
   optional. The full artifact omits the Git State section, the
   warning lands in the warnings list, and the user gets the
   handoff anyway. If any of those four properties fails (no
   prompt, no clipboard, no warning, OR a misleading "unknown"
   substituted into the prompt body without disclosure), the
   "graceful degrade" property is broken.
   `[state-transition, sev 4/5, lik 3/5, sev×lik=12, risk:contract]`

7. **Detached-HEAD git state (no branch name, but HEAD SHA still
   resolves)** — the pre-resolved context block at the top of
   SKILL.md uses `git rev-parse --abbrev-ref HEAD`, which returns
   `HEAD` literally on a detached checkout. The skill must either
   (a) treat this as "branch unknown" and emit the warning, or
   (b) report `branch: detached` explicitly. Test: detach to a
   commit, run the skill, verify the short prompt does not
   contain literal `branch: HEAD` or otherwise mislead the
   receiving agent.
   `[state-transition, sev 4/5, lik 3/5, sev×lik=12, risk:contract]`

8. **Multiple active plans — Phase 1b discovery picks
   deterministically (or asks)** — `docs/plans/` may contain 3+
   files with `status: active` frontmatter. The skill must either
   pick by some deterministic rule (most-recently-modified?
   alphabetically last?) or ask via `AskUserQuestion`. Silent
   "first one found" behavior is a Race Demon target — file order
   from `find` / `ls` is filesystem-dependent.
   `[contract, sev 4/5, lik 3/5, sev×lik=12, risk:contract]`

9. **Phase 4g short-prompt truncation cap per message-type does
   not cut mid-sentence in a way that strips a sanitization
   marker** — the truncation tier list cuts conversation
   synthesis, then plan summary, then checkpoint context, then
   git-state detail. If truncation happens mid-redaction-marker
   (e.g., `[REDACTED:secret_p` instead of `[REDACTED:secret_pattern_3]`),
   the receiving agent sees broken markup and may try to "fix"
   it. Test: a long handoff that truncates exactly at a
   redaction-marker boundary.
   `[contract, sev 3/5, lik 4/5, sev×lik=12, risk:privilege]`

10. **Clipboard tool absent (no `pbcopy` / `clip.exe` /
    `xclip`) — short prompt is still printed to stdout and warning
    emitted** — graceful degrade. The short prompt is the
    user-visible value; if clipboard fails, stdout is the fallback.
    Failing silently (no print, no warning) means the user thinks
    the skill ran but has nothing to paste.
    `[state-transition, sev 4/5, lik 3/5, sev×lik=12, risk:contract]`

## Cases 11-20 (supplementary, not in Top-10 cut)

11. **Empty repo (no commits yet)** — `git rev-parse --short HEAD`
    returns nonzero. Both branch and HEAD SHA are "unknown",
    worktree is "dirty" or "clean" depending on whether files
    exist. Two warnings emitted, not one.
    `[state-transition, sev 3/5, lik 2/5, sev×lik=6]`

12. **CLAUDE.md missing** — Phase 1d emits warning, full artifact's
    Project Context section is omitted, short prompt is unaffected.
    `[contract, sev 3/5, lik 3/5, sev×lik=9]`

13. **Latest checkpoint discovery — checkpoint file is malformed
    (corrupt YAML, truncated)** — Phase 1c must NOT crash. Read
    error → warning → checkpoint section omitted.
    `[state-transition, sev 3/5, lik 2/5, sev×lik=6]`

14. **Permission failure writing `~/.claude/handoffs/{slug}/`** —
    canonical 3-segment warning emitted, short prompt still
    printed to stdout, exit code does NOT signal failure (graceful
    degrade per skill prose).
    `[contract, sev 4/5, lik 2/5, sev×lik=8]`

15. **`OPENCLAW_SESSION` set: skill runs without `AskUserQuestion`
    prompts** — Phase 2 multi-token disambiguation needs a path
    that does not block on user input when called from an
    orchestrator. Verify all `AskUserQuestion` sites have a
    `SPAWNED_SESSION` auto-skip branch.
    `[cross-surface, sev 3/5, lik 3/5, sev×lik=9]`

16. **Sanitization patterns file present but empty** — load
    succeeds, zero patterns applied, every input passes through
    unchanged. Per the SKILL.md prose ("over-redaction preferred
    to under-redaction"), an empty pattern set is a security
    regression. Should this fail closed too? Open question —
    the spec doesn't explicitly answer.
    `[privilege, sev 4/5, lik 1/5, sev×lik=4]`

17. **Free-text `INSTRUCTIONS` field with shell metacharacters,
    backticks, `$()` substitutions** — Phase 4e threads INSTRUCTIONS
    into the prompt. Test that backticks and `$()` are not
    accidentally executed during prompt assembly (this would
    require shell expansion on the assembly side, which the skill
    should NOT use).
    `[privilege, sev 4/5, lik 2/5, sev×lik=8]`

18. **Worktree dirty flag — uncommitted changes show "dirty";
    untracked-only changes also show "dirty"** — `git status
    --porcelain` returns nonempty for both. Confirm the
    receiving agent sees a single "dirty" state, not a separate
    "untracked-only" state, and the warnings disclose what
    "dirty" covers.
    `[contract, sev 3/5, lik 4/5, sev×lik=12]` —
    *(actually this case probably belongs in Top-10; tradeoff
    against #10. I'll note it here as a candidate substitution.)*

19. **Slug derivation — `gstack-slug` not on PATH** — the skill's
    `eval "$(gstack-slug)"` falls through silently, SLUG defaults
    to "unknown". The full artifact path becomes
    `~/.claude/handoffs/unknown/...` rather than failing. Verify
    the warning surfaces the slug-resolution failure.
    `[contract, sev 3/5, lik 3/5, sev×lik=9]`

20. **End-to-end fresh-session paste** — copy the short prompt,
    paste into a NEW Claude Code window, watch the receiving
    agent execute. The receiving agent should:
    (a) read the role correctly,
    (b) NOT re-discover state (branch, HEAD, plans) because it's
        already in the prompt,
    (c) NOT crash on missing context fields (handle "unknown"
        gracefully).
    This is the AC1 / AC3 end-to-end test for session-handoff
    itself; it's foundational ground truth.
    `[cross-surface, sev 5/5, lik 5/5, sev×lik=25]` —
    *(this should genuinely be #1 — but it's the load-bearing
    AC test for session-handoff itself, not a /qa-plan-discovered
    case. I list it last for that reason; any baseline missing
    this is incomplete.)*

## Notes for the eval

- Cases #18 and #20 surface the limit of a 30-minute one-pass
  baseline: priority calls are debatable, and the obvious
  end-to-end case lands at the bottom because the listing went
  axis-by-axis rather than impact-sorted. The Top-10 / Top-20
  cut here is honest-to-the-clock, not retrospectively optimized.
- Counting exact overlap with `/qa-plan` Top-10s requires
  fuzzy matching — case descriptions on each side will differ.
  Two cases match if they cover the same root failure mode, even
  if the worded scenario differs. The TODO 006 comparison doc
  records the matching judgment per pair so the call is
  reproducible.
- This baseline targets `session-handoff` v0.1 specifically.
  For future targets, the methodology (30-min time box, single-
  pass read, no tooling) replicates; the case list does not
  carry over.

---

**End of baseline.** Eval comparison against `/qa-plan` reviewed
plans and the one-hop alternative lives in
`docs/dogfood/001-qa-plan-vs-one-hop-findings.md` (TODO 006).
