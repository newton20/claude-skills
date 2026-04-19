---
title: "feat: Build /session-handoff skill — inter-agent communication primitive"
type: feat
status: active
date: 2026-04-15
revised: 2026-04-16
deepened: 2026-04-16
---

# feat: Build /session-handoff skill — inter-agent communication primitive

## Overview

Build a Claude Code skill (`/session-handoff`) that generates role-aware, structured handoff prompts between agent sessions. V1 ships immediately with 5 message types and 5 target roles, replacing 19+ manual "create a seamless handoff" requests. The design is extensible toward a full inter-agent protocol (Path B) where coordinator, implementation, QA, and reviewer sessions exchange briefings, playbooks, reports, and task assignments through typed message schemas with validation.

## Problem Frame

The real problem is not "session handoff." It is **structured inter-agent communication with role separation.**

The user runs multi-phase projects (yoga-house, polymarket-quant, deal-seaker) with a deliberate separation-of-concerns pattern:
- **Coordinator session**: oversees all phases, decides parallelization, creates task assignments
- **Implementation sessions**: one per phase, focused context on that phase's code
- **QA sessions**: independent testing with browser automation, produces reports
- **Review sessions**: code review, design review, outside voice

Each session needs focused context (not the full project history) and communicates with other sessions through structured artifacts. The current workflow is entirely manual: the user copies prompts between sessions, writes briefing docs by hand, and relays QA findings verbally.

**Example from polymarket-quant Phase 0:**
```
Coordinator → QA:      "Create a test playbook" (task assignment)
QA → Implementation:   "Here's my playbook, review for feasibility" (peer review)
Implementation → QA:   "Feedback: skip test X, add test Y" (review response)  
QA → Coordinator:      "Phase 0 QA complete, 3 findings" (status report)
Coordinator → Impl:    "Phase 1 ready, here's what to build" (next phase handoff)
```

That is 5 handoffs per phase, each manually orchestrated today.

**Related but distinct**: The gstack `/checkpoint` skill captures working state for resuming the *same* session. `/session-handoff` produces typed messages for *different* sessions with different roles.

## Requirements Trace

### V1 (this plan)
- R1. Single command captures git state (branch, HEAD SHA, worktree status), plan status, and project context
- R2. Generates a self-contained prompt that can be pasted into any fresh agent session
- R3. Prompt includes all file paths, branch names, and references needed to continue without re-discovery
- R4. Supports **message types**: `brief`, `assign`, `review`, `report`, and `handoff` (default)
- R5. Supports **target roles**: `coord`, `impl`, `qa`, `reviewer`, and `general` (default)
- R6. Sanitizes output to prevent secret/credential leakage
- R7. Saves full artifact to `~/.claude/handoffs/{project}/`, auto-cleans artifacts older than 14 days
- R8. Attempts clipboard copy with graceful fallback
- R9. Installable at `~/.claude/skills/session-handoff/`, adopts gstack conventions for routing/timeline

### V2 (Path B, future)
- R10. Coordinator session can receive and parse incoming briefings/reports
- R11. Typed message schemas with required fields per message type
- R12. Multi-phase orchestration with dependency tracking

## Scope Boundaries

- No auto-detection of context exhaustion (requires hooks/token counting not available)
- No automatic session creation (user pastes prompts manually)
- No direct integration with orchestrators (OpenClaw, Conductor) beyond producing universal prompts
- V1 does not validate that the receiving session actually processes the handoff correctly
- V1 does not implement `/session-receive` (coordinator-side parsing of incoming messages)

### Deferred to V2 (Path B)

- `/session-receive` command for coordinator sessions to parse incoming briefings/reports
- Typed message schemas with required/optional field validation
- Multi-phase dependency graph tracking
- Auto-generation of QA playbook templates from plan files
- Session registry (which sessions are active, what roles they have)

## Context & Research

### Relevant Code and Patterns

- `~/.claude/skills/checkpoint/SKILL.md` -- git state gathering (branch, status, diff stat, log), structured markdown output with YAML frontmatter
- `ce-sessions/SKILL.md` -- pre-resolved context (repo name, branch via backtick commands in frontmatter)
- gstack preamble -- standard skill scaffolding for routing, timeline, telemetry

### User's Multi-Agent Workflow (from session history)

| Message type | From → To | Frequency | Content |
|---|---|---|---|
| Phase handoff | Coordinator → Impl | Very high | Plan path, phase scope, env setup, first action |
| Task assignment | Coordinator → QA | High | Test scope, playbook instructions, what to report |
| Peer review | QA → Impl | Medium | Playbook for feasibility review |
| Review response | Impl → QA | Medium | Structured feedback (skip/adjust/add) |
| Status report | Impl/QA → Coordinator | High | Phase completion, findings, blockers |
| Briefing | Any → Coordinator | High | Progress summary, decisions made, open questions |

### Source Precedence Model

When gathering state from multiple sources that may conflict:

1. **Git state** (branch, HEAD SHA, worktree dirty) -- ground truth, deterministic
2. **Plan files** (docs/plans/ with `status: active` in YAML frontmatter) -- structured, versioned
3. **Checkpoint files** (~/.gstack/projects/*/checkpoints/) -- recent but may be stale
4. **CLAUDE.md** -- project context, may be outdated
5. **Conversation context** -- best-effort, lossy, explicitly marked as `[inferred]`

Sections sourced from conversation context (decisions, open questions) are marked `[inferred from session]` in the output so the receiving agent knows the confidence level.

## Key Technical Decisions

- **gstack conventions**: Adopts gstack preamble, telemetry, and routing. The skill lives at `~/.claude/skills/session-handoff/` (user-owned, not touched by gstack-upgrade). Uses gstack binaries for slug, config, timeline.
- **Message types, not just roles**: The primary axis is the *type of message* (brief, assign, review, report, handoff), not just the target role. A `brief coord` is structurally different from an `assign qa`.
- **Two-tier output**: Short prompt (~2000 chars) is self-contained and works on any machine, including cross-machine DevBox handoffs. Full artifact on disk has complete detail. Short prompt references artifact as optional: "If on the same machine, read {path} for additional detail."
- **Sanitization pass**: Regex-based filter runs before output to strip patterns matching API keys, tokens, passwords, and known secret env var names. References file paths to secrets instead of inlining values.
- **Structured warnings, not silent omission**: When a data source is unavailable (no git, no plan, clipboard fails), the output includes a warning line: `[warning: no active plan found in docs/plans/ -- plan context omitted]`
- **Artifact storage**: `~/.claude/handoffs/{project}/` with 14-day auto-cleanup. Keeps repos clean. Not version-controlled but accessible across sessions on the same machine.

## Open Questions

### Resolved During Planning

- **Q: Standalone vs gstack?** gstack conventions. Gets routing, timeline for free. gstack-upgrade doesn't touch user-owned skills.
- **Q: Where to save artifacts?** `~/.claude/handoffs/{project}/` to keep repos clean. 14-day auto-cleanup.
- **Q: Should it update CLAUDE.md?** No. Separate concern.
- **Q: What about the shell-script MVP alternative?** Full skill. The role/message-type system and sanitization justify the investment. User will invoke this 100+ times.
- **Q: Conversation context reliability?** Best-effort, explicitly labeled as inferred. User confirms decisions/questions block before finalizing when invoked interactively.

### Deferred to Implementation

- Exact prompt template wording (iterate based on testing with real projects)
- Clipboard: `clip.exe` vs `powershell Set-Clipboard` on Windows (test both)
- Whether sanitization regex is configurable or hardcoded

## Kill Signal

If Claude Code ships native session persistence or cross-session memory that eliminates the need for manual handoffs, this skill becomes obsolete. Monitor for: Claude Code context carry-over between sessions, persistent project memory across sessions, or built-in multi-agent orchestration.

## Output Structure

```
~/.claude/skills/session-handoff/
  SKILL.md                              # Main skill file
  references/
    message-templates.md                # Templates per message type x role
    sanitization-patterns.md            # Secret-matching regex patterns
```

## High-Level Technical Design

> *Directional guidance for review, not implementation specification.*

### Command Grammar

```
/session-handoff [message-type] [target-role] [-- additional instructions]

Message types: handoff (default), brief, assign, review, report
Target roles:  general (default), coord, impl, qa, reviewer

Examples:
  /session-handoff                                 → general handoff, default role
  /session-handoff brief coord                     → briefing for coordinator
  /session-handoff assign qa                       → task assignment for QA agent
  /session-handoff review impl                     → peer review request to impl agent
  /session-handoff report coord -- phase 0 done    → status report to coordinator
  /session-handoff impl -- start phase 3           → phase handoff to impl agent
  /session-handoff handoff reviewer -- check auth  → handoff targeting reviewer role (no ambiguity)
```

### Flow

```
User invokes /session-handoff [type] [role] [-- instructions]
    |
    v
PHASE 1: GATHER STATE
    - git: branch, HEAD SHA, worktree dirty?, status --short, log --oneline -5
    - Plans: find docs/plans/*-plan.md, parse YAML frontmatter for status: active
    - Checkpoint: most recent in ~/.gstack/projects/{slug}/checkpoints/
    - CLAUDE.md: read if exists
    - Conversation: synthesize decisions + open questions (mark as [inferred])
    - On failure: emit structured warning per source, continue with available data
    |
    v
PHASE 2: PARSE COMMAND
    - Extract message type (first arg if known type, else "handoff")
    - Extract target role (next arg if known role, else "general")
    - Extract additional instructions (everything after --)
    - Load template from references/message-templates.md
    |
    v
PHASE 3: SANITIZE
    - Run regex patterns from references/sanitization-patterns.md
    - Replace matches with "[REDACTED -- see {filepath}]"
    - Scan for known env var patterns (API_KEY, SECRET, TOKEN, PASSWORD)
    |
    v
PHASE 4: ASSEMBLE
    - SHORT PROMPT (clipboard): role preamble + project/branch/SHA + status
      summary + plan reference (path only) + instructions + "read full
      artifact at {path} for details"
    - FULL ARTIFACT (disk): all sections with complete detail
    |
    v
PHASE 5: OUTPUT
    - Print short prompt in fenced code block
    - Attempt clipboard copy (clip.exe / pbcopy / xclip, with warning on failure)
    - Save full artifact to ~/.claude/handoffs/{project}/{timestamp}-{type}-{role}.md
    - Auto-cleanup: delete artifacts older than 14 days in that directory
    - Print confirmation with artifact path
```

### Message Type Templates (directional)

Each message type emphasizes different sections:

| Type | Primary sections | Secondary sections |
|---|---|---|
| **handoff** | Project context, status, plan reference, instructions | Decisions, open questions |
| **brief** | Status summary, progress, decisions, blockers | Plan reference, git state |
| **assign** | Task description, scope, acceptance criteria, resources | Project context, plan reference |
| **review** | Artifact to review, review criteria, specific questions | Project context, status |
| **report** | Findings summary, pass/fail, evidence, recommendations | Project context, git state |

## Implementation Units

- [ ] **Unit 1: Skill scaffold, gstack conventions, and state gathering**

  **Goal:** Create the skill structure with gstack preamble, implement state gathering that collects git state (including HEAD SHA and worktree dirty flag), plan files, checkpoints, and project context. Include structured warnings for missing sources.

  **Requirements:** R1, R9

  **Dependencies:** None

  **Files:**
  - Create: `SKILL.md`
  - Create: `references/message-templates.md`
  - Create: `references/sanitization-patterns.md`

  **Approach:**
  - YAML frontmatter with gstack-compatible fields: `name: session-handoff`, description with trigger phrases, `preamble-tier: 1`
  - Minimal gstack preamble: slug resolution, timeline logging (skill start/complete), session tracking. No telemetry, no voice section, no lake intro.
  - Git state gathering: `git rev-parse --abbrev-ref HEAD`, `git rev-parse --short HEAD` (SHA), `git status --porcelain` (dirty check), `git status --short`, `git log --oneline -5`, `git diff --stat`
  - Plan discovery: `find docs/plans/ -name "*-plan.md" -exec grep -l "^status: active" {} \;` (match only YAML frontmatter lines starting with `status:`)
  - If multiple active plans found, include all with paths
  - Checkpoint: `find ~/.gstack/projects/*/checkpoints/ -name "*.md" -type f | xargs ls -t | head -1`
  - CLAUDE.md: `test -f CLAUDE.md && echo "found" || echo "not found"`
  - Each missing source emits: `[warning: {source} not available -- {reason} -- {what was skipped}]`
  - Conversation synthesis: SKILL.md must include explicit LLM instructions: "Review this conversation. List key decisions made in this session, each prefixed with `[inferred from session]`. List open questions or unresolved items. If you cannot recall specific decisions, write `[no session decisions captured -- conversation context unavailable]`. Do not fabricate decisions that were not discussed."

  **Patterns to follow:**
  - `checkpoint/SKILL.md` lines 566-584 for git state gathering
  - `ce-sessions/SKILL.md` for pre-resolved context in frontmatter backticks

  **Test scenarios:**
  - Happy path: project with git repo, active plan, recent commits -> state gathered with branch, SHA, modified files, plan path, recent history
  - Edge case: no git repo -> warning emitted, remaining sources still gathered
  - Edge case: multiple active plans -> all listed with paths
  - Edge case: plan file with `status: active` in prose (not frontmatter) -> not matched (grep anchors to line start)
  - Edge case: no CLAUDE.md -> warning emitted, section skipped
  - Edge case: no checkpoint files -> section omitted with note
  - Error path: `git` command not found -> warning: "git not installed -- branch/commit context omitted"

  **Verification:**
  - `SKILL.md` exists with valid gstack-compatible frontmatter
  - State gathering produces output for each available source
  - Missing sources produce structured warnings, not silent omission
  - HEAD SHA and worktree dirty flag are captured

- [ ] **Unit 2: Command parsing, message types, and role templates**

  **Goal:** Parse the two-axis command grammar (message type x target role), load the appropriate template, and handle additional instructions. Define all 5 message type templates and 5 role preambles.

  **Requirements:** R4, R5

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `SKILL.md` (add command parsing section)
  - Modify: `references/message-templates.md` (add all templates)

  **Approach:**
  - Parse arguments: first known message type (`handoff`, `brief`, `assign`, `review`, `report`), then known role (`coord`, `impl`, `qa`, `reviewer`, `general`), then everything after `--` is instructions
  - `review` is always a message type. The reviewer role is `reviewer` (no ambiguity).
  - Unknown first arg: check if it's a role (for backward compat with `/session-handoff qa`), default message type to `handoff`
  - Templates in `references/message-templates.md` structured as composable parts (DRY, not 25 separate templates):
    - `## Base Template` -- shared structure all messages use
    - `## Role Preambles` -- 5 role-specific opening paragraphs
    - `## Message Type Overrides` -- 5 section-ordering/emphasis rules per type
    - Runtime composes: base + role preamble + message-type section ordering
  - Role preambles are specific about what the receiving agent should do first:
    - **coord**: "You are the coordination agent. Read the briefing, update your phase tracker, decide next actions."
    - **impl**: "You are the implementation agent for {phase}. Read the plan at {path}, start with /ce:work."
    - **qa**: "You are the QA agent. Your job is to test, not fix. Read the playbook/assignment, execute tests, report findings."
    - **reviewer**: "You are a code reviewer. Read the diff, check for the specific concerns listed below."
    - **general**: "You are continuing work on this project. Here is the current state."

  **Patterns to follow:**
  - `checkpoint/SKILL.md` command detection pattern (parse input, detect subcommand)

  **Test scenarios:**
  - Happy path: `/session-handoff brief coord` -> briefing template with coordinator preamble
  - Happy path: `/session-handoff assign qa -- test the booking flow` -> QA task assignment with custom instructions
  - Happy path: `/session-handoff report coord -- phase 0 done` -> status report template
  - Happy path: `/session-handoff impl` -> backward-compat, defaults to handoff type with impl role
  - Happy path: `/session-handoff` (no args) -> general handoff, general role
  - Edge case: `/session-handoff unknown-thing` -> falls back to general handoff with warning
  - Happy path: `/session-handoff review` -> unambiguous: message type `review`, role `general` (no collision since role is `reviewer`)
  - Happy path: `/session-handoff handoff reviewer -- check auth` -> handoff to reviewer role
  - Edge case: `/session-handoff review reviewer -- check the PR` -> message type `review`, role `reviewer`, with instructions

  **Verification:**
  - All 5 message types produce structurally different output (composed from base + type overrides)
  - All 5 roles produce different preambles
  - Custom instructions after `--` are appended to the instructions section
  - Backward-compatible: `/session-handoff qa` still works (interpreted as handoff type, qa role)
  - No ambiguity: `review` is always a message type, `reviewer` is always a role

- [ ] **Unit 3: Sanitization pass**

  **Goal:** Implement the secret/credential sanitization pipeline that runs before any output is generated.

  **Requirements:** R6

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `SKILL.md` (add sanitization phase)
  - Modify: `references/sanitization-patterns.md` (add regex patterns)

  **Approach:**
  - Sanitization runs on the assembled content BEFORE output (between assemble and output phases)
  - Pattern categories in `sanitization-patterns.md`:
    - API key patterns: strings matching `sk-`, `key-`, `token-`, base64 blocks > 20 chars
    - Env var values: lines matching `=` preceded by names containing KEY, SECRET, TOKEN, PASSWORD, CREDENTIAL
    - Known service patterns: Supabase keys (`sb_`), Vercel tokens, AWS keys (`AKIA`), Anthropic keys (`sk-ant-`)
    - URLs with embedded credentials: `://user:pass@`
  - Replacement format: `[REDACTED -- see {original_filepath}]` when a source file path is known, otherwise `[REDACTED -- potential secret removed]`
  - The skill instructions tell the LLM to reference file paths to secrets (e.g., "API keys at api_keys.txt") rather than including the values

  **Patterns to follow:**
  - Standard regex-based secret scanning patterns from git-secrets / truffleHog

  **Test scenarios:**
  - Happy path: CLAUDE.md contains `SUPABASE_KEY=sb_publishable_xxx` -> replaced with `[REDACTED -- see CLAUDE.md]`
  - Happy path: conversation mentions "my API key is sk-ant-xxx" -> replaced in output
  - Edge case: false positive on a commit SHA that looks like a key -> acceptable (over-redact is safer than under-redact)
  - Edge case: no secrets found -> sanitization pass completes silently, no warnings
  - Error path: malformed regex in patterns file -> sanitization skipped with warning, output still generated

  **Verification:**
  - No raw API keys, tokens, or passwords appear in either the short prompt or the full artifact
  - File path references to secrets are preserved (the path itself is not a secret)
  - Over-redaction is preferred over under-redaction

- [ ] **Unit 4: Two-tier output and artifact management**

  **Goal:** Implement the split output (short clipboard prompt + full disk artifact), clipboard copy with fallback, artifact storage with 14-day auto-cleanup.

  **Requirements:** R2, R3, R7, R8

  **Dependencies:** Unit 1, Unit 2, Unit 3

  **Files:**
  - Modify: `SKILL.md` (add output phase)

  **Approach:**
  - **Short prompt** (~2000 chars target): role preamble + project/branch/SHA + status one-liner + plan path + decisions + open questions + key instructions. Must be self-contained (works without artifact). Ends with: "If on the same machine, read {artifact_path} for additional detail."
  - **Truncation priority** (when short prompt exceeds target): cut plan details first, then status details. Always keep: role preamble, branch/SHA, instructions, artifact path reference.
  - **Full artifact**: complete structured document with all sections, YAML frontmatter (schema_version: 1, type, role, branch, sha, timestamp, source_session_id), all gathered state, all warnings
  - Artifact path: `~/.claude/handoffs/{project-slug}/{timestamp}-{type}-{role}.md`
  - Auto-cleanup at skill start: `find ~/.claude/handoffs/{project-slug}/ -name "*.md" -mtime +14 -delete`
  - Clipboard: try `clip.exe` (Windows), `pbcopy` (Mac), `xclip -selection clipboard` (Linux). On failure: `[warning: clipboard copy failed -- {command} not found -- copy the prompt above manually]`
  - Print short prompt in a fenced code block with a header: "## Handoff Prompt (copy this)"
  - Print artifact path after: "Full artifact saved to: {path}"

  **Patterns to follow:**
  - `checkpoint/SKILL.md` lines 624-667 for structured markdown output with YAML frontmatter

  **Test scenarios:**
  - Happy path: full project -> short prompt is under 2500 chars, full artifact has all sections
  - Happy path: artifact saved to `~/.claude/handoffs/{slug}/` with correct naming
  - Happy path: stale artifacts (>14 days) deleted on next invocation
  - Edge case: `~/.claude/handoffs/{slug}/` doesn't exist -> created automatically
  - Edge case: clipboard command fails -> warning printed, prompt still displayed
  - Edge case: minimal project (no plan, no commits) -> short prompt still useful, just smaller
  - Integration: short prompt pasted into a new Claude Code session -> agent can read the artifact path and orient itself
  - Happy path: full artifact includes YAML frontmatter with branch, sha, timestamp, type, role

  **Verification:**
  - Short prompt fits in clipboard and is immediately actionable
  - Full artifact has complete context including all sources and warnings
  - No secrets in either output tier
  - Auto-cleanup runs without errors
  - Artifact YAML frontmatter enables future tooling to parse handoff history

- [ ] **Unit 5: Example output and quickstart documentation**

  **Goal:** Add a concrete example of generated output to the skill's documentation and create a one-command install path.

  **Requirements:** R9 (discoverability)

  **Dependencies:** Unit 1-4

  **Files:**
  - Modify: `SKILL.md` (add example output section and install instructions)

  **Approach:**
  - Add a "## Example Output" section to SKILL.md showing a realistic short prompt and artifact
  - Example should use a synthetic project (not real secrets/paths) that demonstrates all sections
  - Add a quickstart block at the top of SKILL.md (after frontmatter):
    ```
    ## Quick Start
    git clone <repo> ~/.claude/skills/session-handoff
    # Then in any project: /session-handoff
    ```
  - Add to SKILL.md description: trigger phrases including "handoff", "fresh context", "new session", "brief the coordinator", "create a playbook prompt"

  **Test expectation:** none -- documentation-only unit

  **Verification:**
  - Example output is realistic and demonstrates the two-tier split
  - Install instructions work from a clean machine (git clone + immediate use)
  - Trigger phrases cover the user's actual vocabulary from session history

## System-Wide Impact

- **Interaction graph:** Reads git state, plan files, CLAUDE.md, checkpoint files. Writes artifacts to `~/.claude/handoffs/`. Deletes stale artifacts older than 14 days. Attempts clipboard write. Logs to gstack timeline.
- **Error propagation:** Each data source fails independently with a structured warning. No single source failure blocks the overall output.
- **State lifecycle risks:** Auto-cleanup deletes files older than 14 days. If user needs a handoff from 3 weeks ago, it's gone. 14 days is generous for handoff artifacts (they're stale after hours, not weeks).
- **API surface parity:** Short prompt works in any LLM that accepts markdown. Role preambles reference specific skills (/ce:work, /qa) only when the target is known to be Claude Code. General role produces agent-neutral output.
- **Unchanged invariants:** Does not modify CLAUDE.md, plan files, or project source code. Does not commit or push.

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Conversation context is lossy/hallucinatory near context limits | Mark as `[inferred]`, source precedence model, optional user confirmation |
| Secret leakage in output | Sanitization pass with regex patterns, reference paths instead of values |
| Clipboard varies across platforms | Try 3 commands with structured fallback warning |
| Prompt too long for clipboard | Two-tier output: short prompt (~2K chars) + full artifact on disk |
| Platform ships native session persistence | Kill signal defined. Skill becomes obsolete gracefully. |
| Parallel sessions capture interleaved git state | Include HEAD SHA and worktree dirty flag. Document that parallel invocations on shared worktree reflect a point-in-time snapshot. |

## Documentation / Operational Notes

- Add to user's global CLAUDE.md routing: "handoff", "fresh context", "new session", "brief coordinator" -> invoke session-handoff
- Quickstart in SKILL.md for discoverability
- Example output in SKILL.md so users know what to expect before invoking

## Future: Path B Architecture (Reference Only)

This section documents the target architecture. V1 is designed so the message templates, artifact format, and command grammar extend naturally to V2.

### V2 additions
- `/session-receive` command for coordinator sessions to parse incoming briefings/reports
- Typed message schemas with required fields (e.g., `assign` requires: task_description, acceptance_criteria, scope)
- Session registry tracking active sessions and their roles
- Coordinator-side dependency graph: which phases are parallelizable, what's blocked
- Auto-generated QA playbook templates from plan files
- Round-trip validation: coordinator can verify that a report answers the original assignment

### V2 workflow example (polymarket-quant Phase 0)
```
Coordinator:  /session-handoff assign impl -- implement phase 0
              /session-handoff assign qa -- create playbook for phase 0

QA agent:     (receives assignment, creates playbook)
              /session-handoff review impl -- review my playbook

Impl agent:   (receives playbook, reviews)
              /session-handoff report qa -- skip test 3, add test for edge case X

QA agent:     (incorporates feedback, executes)
              /session-handoff report coord -- phase 0 QA complete, 2 findings

Impl agent:   (addresses findings)
              /session-handoff brief coord -- phase 0 implementation complete

Coordinator:  (receives both reports, decides)
              /session-handoff assign impl -- proceed to phase 1
```

## Sources & References

- Related skill: `~/.claude/skills/checkpoint/SKILL.md` (state capture pattern)
- Related skill: `compound-engineering/ce-sessions/SKILL.md` (pre-resolved context pattern)
- User session history analysis: 19+ manual handoff requests across 6 projects (Jan-Apr 2026)
- User's polymarket-quant multi-agent workflow: 5 handoff types per phase

<!-- /autoplan restore point: ~/.gstack/projects/claude-skills/HEAD-autoplan-restore-20260416.md -->

<!-- AUTONOMOUS DECISION LOG -->
## Decision Audit Trail

| # | Phase | Decision | Classification | Principle | Rationale | Rejected |
|---|-------|----------|---------------|-----------|-----------|----------|
| 1 | CEO | Accept "symptom not cause" framing | Mechanical | P6 (action) | Platform-level session persistence isn't available yet. Pragmatic to build now. | "Build zero-handoff instead" |
| 2 | CEO | Reject "extend checkpoint" alternative | Mechanical | P5 (explicit) | Different concerns (resume vs handoff), different output formats. Cleaner as separate skill. | Extend checkpoint with --prompt flag |
| 3 | CEO | Add kill signal to plan | Mechanical | P3 (pragmatic) | Zero cost, helps know when to deprecate if platform ships native persistence. | -- |
| 4 | CEO+User | Adopt gstack conventions | Resolved | User+P1 | User confirmed after understanding gstack-upgrade doesn't touch user skills. | Standalone |
| 5 | CEO+User | Build full skill, not shell-script MVP | Resolved | User choice | Message type system and sanitization justify the investment. | Shell script |
| 6 | Eng | Add secret sanitization pass | Mechanical | P1 (completeness) | Both models flagged as critical. Regex-based filter for API keys/tokens before output. | -- |
| 7 | Eng | Drop "read-only" claims, acknowledge writes | Mechanical | P5 (explicit) | Plan says read-only 5 times but writes artifacts. Misleading. | -- |
| 8 | Eng | Add HEAD SHA + worktree dirty flag | Mechanical | P1 (completeness) | Both models flagged: branch name alone doesn't identify exact state. | -- |
| 9 | Eng | Add source precedence model | Mechanical | P5 (explicit) | git state > plan file > checkpoint > CLAUDE.md > conversation. Both models flagged. | -- |
| 10 | Eng | Split short prompt + full artifact | Mechanical | P3 (pragmatic) | 4000-char cap contradicts R3 completeness. Two outputs solve both. | -- |
| 11 | Eng | Mark conversation-sourced sections as inferred | Mechanical | P5 (explicit) | Both models: conversation context is best-effort, not contractual. | -- |
| 12 | Eng+User | Artifacts to ~/.claude/handoffs/ + 14-day cleanup | Resolved | User+P3 | User confirmed after discussing cleanup strategy. | docs/handoffs/ in repo |
| 13 | DX | Add one-command installer + quickstart | Mechanical | P1 (completeness) | Both DX voices: TTHW is 6-8 steps, needs to be under 60s. | -- |
| 14 | DX | Replace silent omission with structured warnings | Mechanical | P5 (explicit) | Both voices: silent degradation kills trust. Specify error messages. | -- |
| 15 | DX | Add concrete output example in plan | Mechanical | P1 (completeness) | Both voices: no sample output means devs can't evaluate before building. | -- |
| 16 | DX | Define formal argument grammar | Mechanical | P5 (explicit) | Both voices: positional-arg-plus-freetext is fragile. | -- |
| 17 | User | Redesign as inter-agent communication primitive | User decision | -- | User's actual workflow is multi-agent with typed messages, not simple session continuation. | Original "session handoff" framing |

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 1 | resolved (via /autoplan) | 5 findings, all addressed in revision |
| CEO Voices | `/autoplan` dual | Independent challenge | 1 | complete | Claude + Codex: 5/6 confirmed |
| Eng Review | `/plan-eng-review` | Architecture & tests | 2 | CLEAR | 6 issues found, all 6 fixed: reviewer rename, self-contained prompt, honest V1 language, conversation instructions, schema_version, DRY templates |
| Eng Voices | `/autoplan` dual | Independent challenge | 1 | complete | Claude + Codex: 6/6 confirmed |
| Codex Review | `/codex review` | Independent 2nd opinion | 1 | issues_found | 7 findings: V1/V2 language, portability, Windows, plan coherence, sanitization strategy, gstack deps, scope |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | skipped | No UI scope |
| DX Review | `/plan-devex-review` | Developer experience | 1 | resolved (via /autoplan) | DX 4/10 -> addressed with quickstart, examples, warnings, grammar |
| DX Voices | `/autoplan` dual | Independent challenge | 1 | complete | Claude + Codex: 6/6 confirmed |

**CODEX:** 7 findings. Key tension: V1 claims "typed messages" but delivers templates. Sanitization approach debated (regex-scrub vs whitelist). Both resolved in findings below.
**CROSS-MODEL:** 5 overlapping concerns between eng review and Codex. Cross-machine artifact path flagged by both independently.
**UNRESOLVED:** 0
**VERDICT:** CEO + ENG + DX CLEARED. Ready to implement. Run `/ce:work` when ready.
