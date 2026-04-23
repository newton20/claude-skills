# Analytics Schema (qa-plan)

Every `/qa-plan` invocation appends one JSON Lines entry to
`~/.gstack/analytics/skill-usage.jsonl`. This file is the
authoritative schema: downstream consumers (dogfood metric
rollups, future v0.2 telemetry dashboards) parse against this
shape.

Entries are built with `jq -n` (NOT string concat) per SKILL.md
Phase 6a. Local-only; never transmitted to any external service.

---

## Current schema version: 1

Bumping: new required fields, type changes, or removed fields are
breaking and require `schema_version: 2`. New optional fields
(nullable, additive) do NOT bump the version.

---

## Fields

| Field             | Type                       | Required | Notes                                                                                 |
|-------------------|----------------------------|----------|---------------------------------------------------------------------------------------|
| `skill`           | string, literal `"qa-plan"`| yes      | Identifies the skill that wrote the entry.                                            |
| `ts`              | string, ISO-8601 UTC       | yes      | Entry write time. Format: `YYYY-MM-DDTHH:MM:SSZ`.                                      |
| `surface`         | string (enum, see below)   | yes      | Phase 1 classified surface.                                                           |
| `personas_run`    | integer, 0-4               | yes      | Count of persona outputs actually received in Phase 3 (after observable dispatch check). |
| `codex_ran`       | boolean                    | yes      | `true` iff `codex exec` succeeded. Fallback-Claude-subagent-ran is NOT counted here.   |
| `spec_only_ran`   | boolean                    | yes      | `true` iff the spec-only gap reviewer dispatched (not skipped by starvation gate).     |
| `total_cases`     | integer, ≥0                | yes      | Count of cases in the final REVIEWED plan (axis sections + Top-10 dedup resolved).     |
| `outcome`         | string (enum, see below)   | yes      | `"success"` or `"error"`.                                                             |
| `failure_phase`   | string (enum) or `null`    | yes      | Non-null only when `outcome: "error"`; see Phase 6b enum.                              |
| `plan_path`       | string, absolute path      | yes      | Path to the REVIEWED plan artifact. For error outcomes, may point to the partial DRAFT. |
| `warnings`        | array of objects           | yes      | Every canonical 3-segment warning emitted during the run; see shape below.            |
| `schema_version`  | integer, currently `1`     | yes      | Schema version for forward compatibility.                                              |

### `surface` enum

- `"web"`
- `"cli"`
- `"library"`
- `"service"`
- `"claude-skill"`
- `"mixed"` — Phase 1 detected multiple surfaces and user picked full multi-surface (Phase 1h option B)
- `"unknown"` — surface classification failed; emitted only with `outcome: "error"`

### `outcome` enum

- `"success"` — REVIEWED plan authored, handoff emitted, analytics on completion path
- `"error"` — any `exit 1` abort path; `failure_phase` identifies where

### `failure_phase` enum

- `"preamble"` — session / slug / timeline setup failed
- `"phase_1"` — diff resolution, surface classification, or user-scoping failed
- `"phase_2"` — DRAFT author write or mirror write failed
- `"phase_3"` — parallel dispatch or codex sub-chain failed catastrophically (fallback-to-persona-only does NOT count as failure; that is a warned success)
- `"phase_4"` — synthesis / in-place edit / Top-10 generation failed
- `"phase_5"` — handoff emission failed (rare; failure here is mostly a shell error)
- `null` — only for `outcome: "success"` entries

### `warnings` array shape

Each array entry is a JSON object built from the canonical
3-segment warning `[warning: {source} not available -- {reason} -- {what was skipped}]`:

```json
{
  "source": "codex",
  "reason": "not authenticated (run 'codex login')",
  "skipped": "falling back to Claude subagent for cross-model pass"
}
```

Empty array `[]` = no warnings emitted that run (clean execution).

---

## Example entries

### Success, all reviewers ran

```json
{"skill":"qa-plan","ts":"2026-04-22T22:15:30Z","surface":"claude-skill","personas_run":4,"codex_ran":true,"spec_only_ran":true,"total_cases":37,"outcome":"success","failure_phase":null,"plan_path":"/home/user/proj/docs/qa-plans/20260422-221530-feat-foo-qa-plan.md","warnings":[],"schema_version":1}
```

### Success with warned fallbacks

```json
{"skill":"qa-plan","ts":"2026-04-22T22:20:00Z","surface":"web","personas_run":3,"codex_ran":false,"spec_only_ran":false,"total_cases":24,"outcome":"success","failure_phase":null,"plan_path":"/home/user/proj/docs/qa-plans/20260422-222000-feat-bar-qa-plan.md","warnings":[{"source":"codex","reason":"not authenticated","skipped":"falling back to Claude subagent for cross-model pass"},{"source":"persona","reason":"Confused User timed out after 120s","skipped":"persona-specific gaps not surveyed, proceeding with other reviewers"},{"source":"spec-only reviewer","reason":"insufficient spec context (800 tokens under 1500 threshold)","skipped":"skipping, relying on impl-aware draft + personas + codex for coverage"}],"schema_version":1}
```

### Failure in Phase 2

```json
{"skill":"qa-plan","ts":"2026-04-22T22:25:10Z","surface":"service","personas_run":0,"codex_ran":false,"spec_only_ran":false,"total_cases":0,"outcome":"error","failure_phase":"phase_2","plan_path":"/home/user/proj/docs/qa-plans/20260422-222510-feat-baz-qa-plan.md","warnings":[{"source":"filename collision","reason":"20260422-222510-feat-baz-qa-plan.md and 20260422-222510-feat-baz-qa-plan-2.md both exist","skipped":"aborting to avoid data loss"}],"schema_version":1}
```

---

## Consumer contracts

- `jq '.skill == "qa-plan"' skill-usage.jsonl` filters to qa-plan entries
- `jq 'select(.outcome == "error") | .failure_phase' skill-usage.jsonl`
  groups failures by phase (dogfood metric)
- `jq 'select(.codex_ran) | .total_cases' skill-usage.jsonl` measures
  codex-ran run sizes (compare against AC4 Criterion 4)
- v0.2 cleanup logic may prune entries older than N days; do not
  rely on the file being unbounded

v0.2 evolution: add `codex_value_score` (Criterion 4 pass rule
result as integer) when `scripts/codex-value-check.sh` is automated
(currently manual; cut from v0.1 per simplicity review).
