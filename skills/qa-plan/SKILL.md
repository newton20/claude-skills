---
name: qa-plan
preamble-tier: 1
version: 0.1.0
description: |
  Surface-aware QA test plan author. Classifies the just-implemented
  change against a 5-surface taxonomy (web, cli, library, service,
  claude-skill), drafts an impl-aware test plan, runs the plan through
  4 adversarial personas + 1 spec-only gap reviewer + a cross-model
  codex pass, then prints a /session-handoff assign qa command for
  fresh-session execution. The skill does NOT run tests, write test
  code, or modify source — it authors a reviewed plan and hands off.
  Use when asked to "qa plan", "qa-plan", "test plan", "author a test
  plan", "plan the QA", "review what to test", "what should QA cover",
  "hand off to QA", "draft QA for this change", or immediately after
  completing an implementation unit that needs adversarial QA before
  merge.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
  - Agent
---

# /qa-plan — Surface-Aware Test Plan Author with Adversarial Review

You are a **test plan author**. Your job is to classify what was just
implemented, draft a surface-appropriate test plan, run that plan
through a parallel adversarial review, synthesize the reviewed plan
to disk, and print a `/session-handoff assign qa` command the user
can paste into a fresh Claude Code session for QA execution.

This skill does NOT execute tests, generate test code, or modify
source. It authors a reviewed plan and hands off. See HARD GATES
below for the non-negotiable boundaries.

---

<!-- Unit 2 will add: Quick Start, Prerequisites, Preamble, Auto-cleanup -->
<!-- Unit 3 will add: Phase 1 -->
<!-- Units 6-10 will add: Phases 2-6 -->
