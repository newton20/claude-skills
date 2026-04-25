# claude-skills

A personal collection of [Claude Code](https://claude.com/claude-code) skills plus the plans, todos, and orchestration artifacts that produced them.

Each skill is LLM-executed instruction prose (no compiled parser, no runtime). The value lives in the discipline of the prose — tight phase boundaries, canonical warning shapes, explicit source-precedence rules, and worked examples that illustrate every invariant. Skills ship through a plan → implement → review → merge cycle tracked in `docs/`.

## What's here

| Skill | Status | What it does |
|---|---|---|
| [`session-handoff`](skills/session-handoff/SKILL.md) | v0.1 shipped | Generates role-aware, structured handoff prompts between agent sessions. Captures git state, active plans, checkpoints, and conversation context into a self-contained prompt a fresh session can act on without re-discovery. Supports 5 message types (`handoff`, `brief`, `assign`, `review`, `report`) × 5 target roles (`coord`, `impl`, `qa`, `reviewer`, `general`) = 25 legal combinations via a DRY base template. |
| [`qa-plan`](skills/qa-plan/SKILL.md) | v0.1 shipped | Surface-aware QA test plan author. Classifies the just-implemented change across a 5-surface taxonomy (web / cli / library / service / claude-skill), drafts an impl-aware test plan, reviews it with 4 adversarial personas + 1 spec-only gap reviewer + a cross-model codex pass (all dispatched in a single parallel block), writes the REVIEWED plan to disk, and prints a `/session-handoff assign qa` command wrapped in a machine-parseable `<qa-plan-handoff>` block. Context separation via planned handoff, not heroics — three HARD GATES prevent test execution, test code generation, and source modification inside the planning session. |
| [`ado-pr`](skills/ado-pr/SKILL.md) | v1.1.1 shipped | Interactive Azure DevOps pull-request management. Read PR details and threads (with a 3-layer filter that separates humans, CI bots, and Git system events), reply and resolve review comments, create inline or general-purpose threads, create PRs from a template, update descriptions, embed images as ADO attachments, and verify a commit made it into a given build. Four bundled `scripts/` wrap `az devops invoke`'s exit-code quirk so POST/PATCH calls produce real success/failure codes instead of always-1. Safety rules with "Why:" clauses gate every write operation, and the common image-upload and build-ancestry flows live in `references/` for on-demand loading. |

More skills coming. Each one gets its own `skills/<name>/` directory with a `SKILL.md` entry point and optional `references/` for split-out content.

## Install a skill

Every skill is self-contained under `skills/<name>/`. To make a skill callable as `/<name>` in Claude Code, install it into `~/.claude/skills/`. Pick whichever install style fits your workflow.

### Option A — Live link (recommended for contributors)

Links the installed skill at the repo copy so `git pull` keeps it current. Zero resync step. The installed skill tracks whatever branch the repo is on, which is usually what you want when iterating.

**macOS / Linux:**

```bash
ln -s "$(pwd)/skills/session-handoff" ~/.claude/skills/session-handoff
```

**Windows (PowerShell):**

```powershell
New-Item -ItemType Junction `
  -Path "$HOME\.claude\skills\session-handoff" `
  -Target "$HOME\project\claude-skills\skills\session-handoff"
```

Junctions work without admin or Developer Mode and are transparent to the Claude Code harness. Adjust the `-Target` path if your clone lives elsewhere.

### Option B — One-time copy (pin to a known-good state)

Copies the skill once. The installed copy stays frozen until you copy again. Pick this if you want the repo and the installed skill to evolve independently.

```bash
cp -R skills/session-handoff ~/.claude/skills/
```

### Verify

```bash
ls ~/.claude/skills/session-handoff/SKILL.md
```

Then invoke from any Claude Code session:

```
/session-handoff assign qa -- run the smoke tests on feat/booking-rebuild
```

See the skill's `SKILL.md` for full argument grammar and worked examples.

## Install `/qa-plan` subagents (v0.2+)

`/qa-plan` v0.2 ships **project-defined Claude Code subagents** at
`skills/qa-plan/agents/` — five files, one per reviewer (four
adversarial personas + one spec-only gap reviewer). Each file's
frontmatter declares `tools:` which Claude Code enforces at
subagent dispatch, so persona runs are restricted to `[Bash, Read,
Grep]` and the spec-only reviewer is restricted to `[Read, Grep]`
without prompt-level hedging.

Install them alongside the skill at `~/.claude/agents/`:

**macOS / Linux — live link (recommended for contributors):**

```bash
mkdir -p ~/.claude/agents
for f in skills/qa-plan/agents/*.md; do
  ln -sf "$(pwd)/$f" "$HOME/.claude/agents/$(basename "$f")"
done
```

**macOS / Linux — one-time copy:**

```bash
mkdir -p ~/.claude/agents
cp skills/qa-plan/agents/*.md ~/.claude/agents/
```

**Windows (PowerShell) — junctions per file aren't supported for
single files; use copy or `mklink` per-file:**

```powershell
New-Item -ItemType Directory -Force -Path "$HOME\.claude\agents" | Out-Null
Copy-Item skills\qa-plan\agents\*.md "$HOME\.claude\agents\"
```

**Windows (git-bash) — copy:**

```bash
mkdir -p ~/.claude/agents
cp skills/qa-plan/agents/*.md ~/.claude/agents/
```

**Verify:**

```bash
ls ~/.claude/agents/qa-plan-*.md
# qa-plan-persona-confused-user.md
# qa-plan-persona-data-corruptor.md
# qa-plan-persona-race-demon.md
# qa-plan-persona-prod-saboteur.md
# qa-plan-spec-only-reviewer.md
```

**Re-copy after each pull.** If you used Option B (one-time copy)
for the skill, do the same for the subagents — copy-installed
files stay frozen until you copy again. Option A (live link) keeps
the installed subagent files tracking the repo; re-install only
when new subagent files land.

**Fallback behavior:** `/qa-plan` still works if the subagents are
not installed — Phase 3 falls back to `general-purpose` dispatch
with prompt-level tool intent and emits a canonical warning per
missing subagent. Reviewer Coverage in the REVIEWED plan records
the degraded enforcement. Install the subagents for the stronger
guarantee.

## Development rhythm

Skills here ship through a deliberate cycle that leaves receipts at every step:

1. **Plan** — write a plan at `docs/plans/YYYY-MM-DD-NNN-<slug>-plan.md`. YAML frontmatter with `status: active` makes it discoverable by the session-handoff skill during `/session-handoff` invocations.
2. **Implement** — land the skill under `skills/<name>/` on a feature branch. Keep changes tightly scoped.
3. **Review** — run structured reviews against the diff before merging. Typical loop on this repo:
   - `/compound-engineering:ce-code-review` — parallel persona reviewers (correctness, testing, maintainability, project-standards, agent-native, learnings)
   - `/codex review` — independent second opinion from OpenAI Codex CLI
   - Apply safe_auto fixes; defer the rest to tracked todos.
4. **Ship** — merge commit preserves the review history under the PR. Feature branch deleted.

When review surfaces a non-blocking follow-up, capture it as a todo at `docs/todos/NNN-<status>-<priority>-<slug>.md` rather than letting it disappear. Status flows `pending` → `ready` → `complete`; the filename encodes the current state so `ls docs/todos/` is a progress dashboard.

## Layout

```
.
├── skills/                       # Installable Claude Code skills
│   └── session-handoff/
│       ├── SKILL.md              # Entry point (LLM reads this)
│       └── references/           # Split-out content (templates, patterns)
├── docs/
│   ├── plans/                    # Feature plans (YAML frontmatter, active/completed)
│   ├── todos/                    # Tracked follow-ups (NNN-{status}-{priority}-{slug}.md)
│   └── orchestration/            # Multi-agent orchestration experiments
│       ├── manifest.yaml         # Phase/unit breakdown for parallel agent sessions
│       ├── prompts/              # Per-phase agent prompts
│       └── signals/              # Per-phase completion signals
├── .gitignore
└── README.md
```

## Todos at a glance

`docs/todos/` is an append-only log with status in the filename. Current state:

```
001-complete-p2-per-type-short-prompt-soft-cap.md
002-complete-p3-boundary-worked-cases-phase-4g.md
003-complete-p3-session-handoff-placeholder-vs-literal-sanitization.md
004-complete-p3-recheck-short-prompt-cap-after-placeholder-lint.md
005-complete-p2-verify-session-handoff-report-coord-route.md
006-in-progress-p3-ab-test-qa-plan-vs-one-hop-during-dogfood.md
007-complete-p3-author-human-test-list-for-session-handoff-v0.1.md
```

Todos 001-005 + 007 complete. TODO 006 (A/B framework) shipped in v0.3; remaining work is two user-driven fresh-session reference runs — see `docs/dogfood/001-qa-plan-vs-one-hop-findings.md` "User-action required" section.

## Design principles

A few things the skills here share, by construction:

- **Instruction prose over compiled parsers.** Skills are Markdown the LLM executes at runtime. That means: the prose itself IS the contract. No code to debug, no tests to run — the specification has to be precise enough that the LLM produces deterministic output from ambiguous input.
- **Canonical warning shape.** Every skill emits `[warning: {source} not available -- {reason} -- {what was skipped}]` — a 3-segment format that lets downstream agents parse warnings without regex gymnastics.
- **Worked examples for every invariant.** Rules without examples rot. Each skill's `SKILL.md` carries worked cases that illustrate the tricky paths (truncation boundaries, empty-state placeholders, error-fallback warnings) so the spec is legible at runtime.
- **Two-tier output: short prompt + full artifact.** Skills that generate content produce a skimmable short prompt (for clipboard / quick context) AND a structured full artifact saved to disk. The two tiers are composed from the same source with per-type length budgets.
- **Graceful degradation on missing sources.** Every optional input (git, plans, checkpoints, CLAUDE.md) is wrapped in a presence check. Absence emits a warning, never silent omission.

## Contributing

This is a personal skills collection, but if you're reading the source to borrow patterns:

- Mirror the existing skill structure — `SKILL.md` at the root + optional `references/` for split-out content the main file imports.
- Use the canonical warning shape.
- Write plans before code. Even for small skills, a 2-paragraph plan at `docs/plans/` catches scope drift before it ships.
- Land review follow-ups as todos, not untracked notes.

## License

No license specified yet — this is a private repo. If you've cloned or forked it, assume "all rights reserved" until a LICENSE file appears.
