# claude-skills

A personal collection of [Claude Code](https://claude.com/claude-code) skills plus the plans, todos, and orchestration artifacts that produced them.

Each skill is LLM-executed instruction prose (no compiled parser, no runtime). The value lives in the discipline of the prose — tight phase boundaries, canonical warning shapes, explicit source-precedence rules, and worked examples that illustrate every invariant. Skills ship through a plan → implement → review → merge cycle tracked in `docs/`.

## What's here

| Skill | Status | What it does |
|---|---|---|
| [`session-handoff`](skills/session-handoff/SKILL.md) | v0.1 shipped | Generates role-aware, structured handoff prompts between agent sessions. Captures git state, active plans, checkpoints, and conversation context into a self-contained prompt a fresh session can act on without re-discovery. Supports 5 message types (`handoff`, `brief`, `assign`, `review`, `report`) × 5 target roles (`coord`, `impl`, `qa`, `reviewer`, `general`) = 25 legal combinations via a DRY base template. |
| [`qa-plan`](skills/qa-plan/SKILL.md) | v0.1 shipped | Surface-aware QA test plan author. Classifies the just-implemented change across a 5-surface taxonomy (web / cli / library / service / claude-skill), drafts an impl-aware test plan, reviews it with 4 adversarial personas + 1 spec-only gap reviewer + a cross-model codex pass (all dispatched in a single parallel block), writes the REVIEWED plan to disk, and prints a `/session-handoff assign qa` command wrapped in a machine-parseable `<qa-plan-handoff>` block. Context separation via planned handoff, not heroics — three HARD GATES prevent test execution, test code generation, and source modification inside the planning session. |

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
007-in-progress-p3-author-human-test-list-for-session-handoff-v0.1.md
```

Todos 001-005 complete. Todos 006-007 unblocked by `qa-plan` v0.1 merge and now gating on dogfood runs (see `docs/dogfood/001-qa-plan-v0.1-findings.md`).

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
