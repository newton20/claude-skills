# Sanitization Patterns (session-handoff)

Regex patterns for stripping API keys, tokens, passwords, and other
secrets from the short prompt and full artifact before output. This
file is the source of truth for what Phase 3 of `SKILL.md` treats as a
secret. Phase 3 loads this file, verifies every regex compiles, then
applies the patterns between Phase 4 assembly and Phase 5 output.

## How to read this file

Each category lists:

- **Regex** — a POSIX-extended / PCRE regex. Patterns are written so
  they work with both JavaScript and Python `re` engines without
  modification. All patterns are case-sensitive except where
  `(?i)` is explicitly written.
- **Match example** — an input fragment that must be redacted.
- **Replacement** — one of the two templates defined in SKILL.md
  Phase 3: `[REDACTED -- see {original_filepath}]` (when provenance
  is known) or `[REDACTED -- potential secret removed]` (when not).
  The examples below show the attributed form with a synthetic path.

Patterns are inspired by the `git-secrets` and `truffleHog` regex
libraries. Over-redaction is preferred to under-redaction — see
SKILL.md Phase 3 for the rationale and the list of acceptable false
positives (commit SHAs, UUIDs, base64-shaped build hashes).

---

## 1. API key shapes

Generic prefix-plus-payload patterns. Catch the common "human-writes-a-
token" shape before any service-specific pattern has a chance to run.

**Regexes:**

```regex
\bsk-[A-Za-z0-9_-]{16,}\b
\bkey-[A-Za-z0-9_-]{16,}\b
\btoken-[A-Za-z0-9_-]{16,}\b
\b[A-Za-z0-9+/_-]{20,}={0,2}\b
```

The first three catch prefix-labelled keys. The fourth catches long
base64 / base64url blocks (20+ chars, optional `=` padding). The
base64 pattern is deliberately broad: it will also match commit SHAs,
UUIDs, build hashes, and some diff-stat content. That is acceptable —
see SKILL.md Phase 3, "Over-redaction is preferred."

**Match examples:**

- `sk-1234567890abcdefGHIJKL` → `[REDACTED -- see CLAUDE.md]`
- `key-abcdef0123456789ABCDEF` → `[REDACTED -- see .env.example]`
- `token-XYZ1234567890abcdefg` → `[REDACTED -- potential secret removed]`
- `aGVsbG93b3JsZGJhc2U2NGJsb2Nr` → `[REDACTED -- potential secret removed]`

## 2. Env-var values

Lines of the form `NAME=VALUE` (or `NAME: VALUE` in YAML) where `NAME`
contains any of the secret-suggesting tokens. The entire value side is
replaced; the name is preserved so the receiving agent sees which env
var was elided.

**Regex (case-insensitive on the name):**

```regex
(?i)\b([A-Z0-9_]*?(?:KEY|SECRET|TOKEN|PASSWORD|PASSWD|CREDENTIAL|CREDENTIALS)[A-Z0-9_]*)\s*[:=]\s*\S.*
```

Replacement preserves the `NAME=` (or `NAME:`) prefix and redacts
everything after the separator:

- `SUPABASE_KEY=sb_publishable_Xyz123abc456` →
  `SUPABASE_KEY=[REDACTED -- see CLAUDE.md]`
- `API_SECRET: "abcd-efgh-ijkl"` →
  `API_SECRET: [REDACTED -- see docs/plans/foo-plan.md]`
- `ANTHROPIC_API_KEY = sk-ant-api03-ZZZZZZZZ` →
  `ANTHROPIC_API_KEY = [REDACTED -- potential secret removed]`
- `db_password=hunter2hunter2hunter2` →
  `db_password=[REDACTED -- see .env]`

**Tokens that trigger this pattern** (case-insensitive, substring
match inside the variable name):

- `KEY`
- `SECRET`
- `TOKEN`
- `PASSWORD` / `PASSWD`
- `CREDENTIAL` / `CREDENTIALS`

## 3. Known service patterns

Vendor-specific shapes. Each one is narrower than the generic API-key
category and catches formats the generic patterns may miss.

**Regexes:**

```regex
\bsb_(?:publishable|secret)_[A-Za-z0-9_-]{16,}\b
\bvercel_[A-Za-z0-9_-]{16,}\b
\bAKIA[0-9A-Z]{16}\b
\bsk-ant-(?:api03-)?[A-Za-z0-9_-]{32,}\b
\bsk-proj-[A-Za-z0-9_-]{16,}\b
\bgh[pousr]_[A-Za-z0-9]{36,}\b
\bxox[baprs]-[A-Za-z0-9-]{10,}\b
```

| Service   | Shape                                     | Example (synthetic)                                 |
|-----------|-------------------------------------------|-----------------------------------------------------|
| Supabase  | `sb_publishable_...` / `sb_secret_...`    | `sb_publishable_ABCDEFGH12345678`                   |
| Vercel    | `vercel_...` token                        | `vercel_abcdef1234567890xyz`                        |
| AWS       | `AKIA` + 16 uppercase alphanum            | `AKIAIOSFODNN7EXAMPLE`                              |
| Anthropic | `sk-ant-api03-...`                        | `sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`     |
| OpenAI    | `sk-proj-...`                             | `sk-proj-abcdef1234567890`                          |
| GitHub    | `ghp_` / `gho_` / `ghu_` / `ghs_` / `ghr_` | `ghp_abcdefghijklmnopqrstuvwxyzABCDEFGHIJ`          |
| Slack     | `xoxb-` / `xoxa-` / `xoxp-` / `xoxr-` / `xoxs-` | `xoxb-1234567890-abcdefghij`                   |

Match examples:

- `sb_publishable_Xyz123abcDEF` → `[REDACTED -- see CLAUDE.md]`
- `AKIAIOSFODNN7EXAMPLE` → `[REDACTED -- see .env]`
- `sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA` → `[REDACTED -- potential secret removed]`
- `ghp_abcdefghijklmnopqrstuvwxyzABCDEFGHIJ` → `[REDACTED -- see docs/plans/foo-plan.md]`

## 4. URLs with embedded credentials

URL form `scheme://user:pass@host...`. Replace the credentials
segment; preserve the scheme, host, and path (the host and path are
navigational, not secret).

**Regex:**

```regex
\b([a-zA-Z][a-zA-Z0-9+.-]*)://([^\s:@/]+):([^\s:@/]+)@
```

**Replacement form:** substitute the matched user + password with
`REDACTED:REDACTED`. Output shape:
`{scheme}://REDACTED:REDACTED@{host}{path}`.

Match examples:

- `https://admin:hunter2@db.example.com/app` →
  `https://REDACTED:REDACTED@db.example.com/app`
- `postgres://dbuser:s3cret@localhost:5432/mydb` →
  `postgres://REDACTED:REDACTED@localhost:5432/mydb`
- `ssh://deploy:abc123def456@bastion.internal/` →
  `ssh://REDACTED:REDACTED@bastion.internal/`

Unlike the first three categories, this category uses a structural
rewrite (`REDACTED:REDACTED`) rather than the `[REDACTED -- ...]`
template, because the surrounding URL context is still useful to the
receiving agent. The `[REDACTED -- ...]` templates apply to the other
three categories.

---

## Fallback contract (malformed regex / missing file)

Phase 3 verifies every regex in this file compiles before applying
any of them. If this file is absent, unreadable, or any regex above
is malformed, Phase 3 emits the canonical warning:

```
[warning: sanitization skipped -- malformed pattern in references/sanitization-patterns.md -- output emitted without redaction]
```

Alternate reasons (same 3-segment shape) are listed in SKILL.md
Phase 3. The skill still produces output — a warned, unredacted
output is preferred to a silent failure.

## Out of scope (do NOT add patterns for)

- **Quoted tokens in Phase 2 warnings** (e.g. `"unknown-thing"`,
  `"qa"`). These are echoed user input, not secrets. Adding a quoted-
  string pattern would over-redact the diagnostic output Unit 2
  emits. See SKILL.md Phase 3, "What sanitization must NOT touch."
- **File paths.** Paths are not secrets; the replacement templates
  deliberately include the source file path so the receiving agent
  can fetch the real value locally.
- **Short commit SHAs in isolation.** The generic base64-block
  pattern may catch 7–40 char hex SHAs; that false positive is
  acceptable (see SKILL.md Phase 3). Do NOT add a separate SHA
  pattern, and do NOT narrow the base64 pattern to exclude hex.
