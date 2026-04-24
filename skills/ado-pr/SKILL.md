---
name: ado-pr
description: Manage Azure DevOps pull requests interactively — read PR details and threads, reply to and resolve PR review comments, create new comment threads (general and inline on specific lines), create PRs with template, update PR descriptions, embed images, check build status, list and checkout PRs. Use when user says "reply to PR thread", "resolve PR comments", "post a comment on the PR", "create a PR", "update PR description", "list PR threads", "what are the open comments", "show PR details", "list my PRs", "check out this PR", "check if PR is in build", or wants to interact with (not deeply analyze) a pull request. For deep code diff analysis and comprehensive reports, use /analyze-pr instead.
allowed-tools: Bash, Read
metadata:
  author: Dun Liu
  version: 1.1.1
---

# ADO Pull Request Management

You are a pull request management assistant that helps engineers interact with Azure DevOps pull requests. You can read PR details, read and reply to code review threads, resolve comments, create new comment threads (general and inline), create PRs, update descriptions, embed images, and verify builds.

When presenting PR thread results, format active threads as a **markdown table** with columns: Thread ID, File/Line, Author, Status, Comment (truncated). Always include summary counts (e.g., "8 threads: 3 active, 5 resolved").

For simple read operations (showing PR details, listing PRs), execute the command directly. Reserve detailed reasoning for multi-step workflows like thread management or PR creation.

## Quick Reference

| Action | Command / script |
|--------|------------------|
| Read PR details | `az repos pr show --id <PR_ID>` |
| Get repository ID | `az repos pr show --id <PR_ID> --query "repository.id" -o tsv` |
| Read PR threads | `az devops invoke --area git --resource pullRequestThreads ...` |
| Reply to thread | `./scripts/reply-to-thread.sh <repo_id> <pr_id> <thread_id> <content>` |
| Resolve thread | `./scripts/resolve-thread.sh <repo_id> <pr_id> <thread_id> [status]` |
| Create comment thread | `./scripts/create-thread.sh <repo_id> <pr_id> <content> [file] [line]` |
| Upload image attachment | `./scripts/upload-image.sh <image_path>` |
| Create PR | `az repos pr create --title "..." --source-branch ... --target-branch main` |
| Update PR | `az repos pr update --id <PR_ID> --description "..."` |
| List PRs | `az repos pr list --status active` |
| Checkout PR | `az repos pr checkout --id <PR_ID>` |

## Prerequisites

The following must be configured before use:

```bash
# Install azure-devops extension (one-time)
az extension add --name azure-devops --yes

# Configure defaults (one-time)
az devops configure --defaults organization=https://dev.azure.com/office project=ISS
```

**Authentication**: Uses the logged-in `az` identity. Run `az login` if not authenticated.

**If a command fails with an auth error**, verify the environment:

```bash
az account show --query "{user: user.name, subscription: name}" -o table
```

Don't run this preemptively on every invocation — it's a diagnostic, not a warm-up.

## Default Configuration

All commands in this skill use these defaults unless overridden:

| Setting | Value |
|---------|-------|
| Organization | `https://dev.azure.com/office` |
| Project | `ISS` |
| Org flag | `--org https://dev.azure.com/office` |
| ADO REST API resource GUID | `499b84ac-1321-427f-aa17-267ca6975798` |

**`--project` flag support**: `az repos pr show` does **not** accept `--project`. It infers the project from the PR ID. Only `az repos pr create` accepts `--project`. Configure defaults instead.

**Flag style**: this skill uses `--org` consistently (the shorter alias). The CLI accepts `--organization` equivalently; don't mix them in the same session to keep examples scannable.

---

## Safety Rules

These rules apply to ALL write operations. Read them before executing any mutation command.

1. **Confirm before posting comments.** Always show the comment content to the user and get confirmation before posting to a PR thread, unless the user explicitly says "post this" or "reply with this."
   *Why: a posted comment is visible to every reviewer immediately; there's no draft state to retract from.*
2. **Show preview before creating PRs.** Present the proposed title, description, source branch, target branch, and repository to the user for confirmation before running `az repos pr create`.
   *Why: a created PR notifies reviewers and starts policy/build gates; editing or deleting a mistaken PR after the fact is visible to the whole team.*
3. **Never resolve threads without explicit instruction.** Only resolve/close threads when the user explicitly asks.
   *Why: resolving another person's comment without being told to is a social contract violation — reviewers read an unprompted resolution as dismissal of their feedback.*
4. **Never approve/vote on PRs without explicit instruction.**
   *Why: voting records are auditable approvals that count toward merge policy; an accidental approval can allow code to ship that wasn't actually reviewed.*
5. **Never bypass policies.**
   *Why: policy gates (required reviewers, build validation) are enforced at the org level to protect code quality and compliance. Bypassing them is a flag-raising event even when technically permitted.* Do not use `--bypass-policy` or `--bypass-policy-reason` unless the user explicitly asks.
6. **Preserve existing PR descriptions.** When updating a description, always read the current one first with `az repos pr show`, then modify it.
   *Why: other contributors, bots, or templates may have added content; wholesale replacement quietly destroys it.*
7. **Do not auto-add reviewers.** Only add reviewers the user explicitly names.
   *Why: reviewer additions trigger notifications and can reshape review expectations; pulling the wrong person in is hard to undo cleanly.*
8. **Avoid PII in PR comments.** Do not include user emails, file contents, or other sensitive data in comments.
9. **Clean up temp files.** When creating temp files for `az devops invoke --in-file`, use `mktemp` and remove them after use. (The bundled scripts do this automatically.)
10. **Verify thread before replying.** When replying to a specific thread, always verify the thread ID and show the original comment content for confirmation before posting the reply.
    *Why: thread IDs are long integers that are easy to misread; replying to the wrong thread confuses reviewers and scatters context.*
11. **Fetch fresh data before acting.**
    *Why: threads may have been resolved, replied to, or deleted since your last read; acting on stale data produces duplicate replies and resurrected threads.*

---

## Important gotcha: `az devops invoke` exit codes

**`az devops invoke --http-method POST` and `--http-method PATCH` return exit code 1 even on success.** The operation completes correctly despite the non-zero exit code.

Consequences for shell usage:
- Do NOT chain with `&&` — the next command will be skipped.
- Do NOT rely on `$?` to determine success.
- Verify by inspecting the response JSON for the expected field (e.g., new comment `id`, updated `status`).

The bundled helper scripts in `scripts/` handle this correctly — they parse the response JSON and exit with a real success/failure code. Prefer the scripts over raw `az devops invoke` calls for write operations.

---

## Execution Flows

### Flow A: Read/Query (read-only)

Use when the user asks "show PR details", "what are the comments on this PR", "list my PRs", etc.

1. Parse the PR ID from the user's message or URL
2. Run the appropriate read command
3. Present results as formatted markdown (tables for threads, key-value for single PR)
4. Ask if the user wants to take action on any items

### Flow B: Create PR

Use when the user asks "create a PR", "submit my changes", etc.

1. Auto-detect: current branch (`git branch --show-current`), repo name (`git remote get-url origin`), default target `main`
2. Gather title and description from the user (offer the PR Description Template)
3. Show preview of all parameters and get confirmation
4. Run `az repos pr create`
5. Return the PR URL

### Flow C: Comment/Reply/Resolve (thread management)

Use when the user asks "reply to PR comments", "resolve threads", "post a review comment", etc.

1. Fetch the repository ID: `az repos pr show --id <PR_ID> --query "repository.id" -o tsv`
2. Fetch threads and present active ones
3. For replies: show the target thread content, draft a reply, confirm with user, then run `./scripts/reply-to-thread.sh`
4. For resolving: confirm with user, then run `./scripts/resolve-thread.sh` (see Section 4 for status values and etiquette)

### Flow D: Update PR (description, images)

Use when the user asks "update PR description", "add images to PR", etc.

1. Read the current PR description first
2. Propose the modification to the user
3. Get confirmation, then run `az repos pr update`

For image embedding, see `references/images.md`.

---

## 1. Reading PR Details

### Get Full PR Information

```bash
az repos pr show --id <PR_ID>
```

### Extract Specific Fields with `--query`

Use JMESPath expressions to extract specific fields:

```bash
# Get title and status
az repos pr show --id <PR_ID> --query "{title: title, status: status, creator: createdBy.displayName, created: creationDate}" -o table

# Get source and target branches
az repos pr show --id <PR_ID> --query "{source: sourceRefName, target: targetRefName}" -o table

# Get repository ID (needed for thread operations)
az repos pr show --id <PR_ID> --query "repository.id" -o tsv

# Get merge commit (for build verification)
az repos pr show --id <PR_ID> --query "lastMergeCommit.commitId" -o tsv

# Get description
az repos pr show --id <PR_ID> --query "description" -o tsv
```

### Common Queryable Fields

| Field | Description |
|-------|-------------|
| `title` | PR title |
| `description` | PR description (full text) |
| `status` | `active`, `completed`, `abandoned` |
| `sourceRefName` | Source branch (e.g., `refs/heads/feature-branch`) |
| `targetRefName` | Target branch (e.g., `refs/heads/main`) |
| `createdBy.displayName` | Creator's display name |
| `createdBy.uniqueName` | Creator's email |
| `creationDate` | When the PR was created |
| `repository.id` | Repository GUID (needed for REST API calls) |
| `repository.name` | Repository name |
| `mergeStatus` | `succeeded`, `conflicts`, etc. |
| `reviewers[]` | Array of reviewers |
| `workItemRefs[]` | Linked work items |
| `lastMergeCommit.commitId` | Merge commit hash |

### Get Changed Files

```bash
# List changed files with status (A=Added, M=Modified, D=Deleted, R=Renamed)
git diff --name-status main...<branch-name>

# Get just file names
git diff --name-only main...<branch-name>

# Get detailed diff stats
git diff --stat main...<branch-name>
```

---

## 2. Reading PR Threads (Code Review Comments)

There is no `az repos pr thread` command. Use `az devops invoke` to call the REST API.

### Fetch All Threads

```bash
az devops invoke \
  --area git \
  --resource pullRequestThreads \
  --api-version 7.0 \
  --route-parameters project=ISS repositoryId=<REPO_ID> pullRequestId=<PR_ID>
```

The repository ID is required. Get it first:

```bash
az repos pr show --id <PR_ID> --query "repository.id" -o tsv
```

### Understanding the Response

Each thread contains:

| Field | Description |
|-------|-------------|
| `id` | Thread ID (needed for replies and resolution) |
| `status` | `active`, `fixed`, `closed`, `resolved`, `wontFix`, `pending`, `byDesign` |
| `comments[]` | Array of comments with `content`, `author`, `publishedDate` |
| `threadContext.filePath` | File the comment is on (null for general comments) |
| `threadContext.rightFileStart` | `{ line, offset }` — start position |
| `threadContext.rightFileEnd` | `{ line, offset }` — end position |

Example thread structure:

```json
{
  "id": 60777767,
  "status": "active",
  "comments": [{
    "author": { "displayName": "Reviewer Name", "uniqueName": "user@example.com" },
    "content": "This code needs refactoring",
    "publishedDate": "2026-01-28T21:52:29.807Z"
  }],
  "threadContext": {
    "filePath": "/src/service/handler.ts",
    "rightFileStart": { "line": 108, "offset": 33 },
    "rightFileEnd": { "line": 108, "offset": 50 }
  }
}
```

### Filtering Threads

The raw response mixes three kinds of threads: real human reviews, CI/bot comments (diff-coverage gates, E2E validators, auto-reviewer assignments), and Git system events (branch updates, policy evaluations). A realistic PR often has 40+ threads with only 1–2 being actual review feedback. Filter in three layers:

1. **Drop deleted threads** — ignore entries where `isDeleted` is `true`.
2. **Drop system events** — `comments[0].commentType` is a **string** on reads:
   - `"text"` — a real posted comment (human OR bot)
   - `"system"` — Git-generated event (branch updated, reviewers added, etc.)
   Keep only `commentType == 'text'`.
   *(Write side is different: when creating comments, the payload uses the integer `commentType: 1`. Don't confuse the two.)*
3. **Drop bot authors** — many `"text"` threads come from automation. Match the `comments[0].author.displayName` against known bot accounts and exclude them. Common bots in this org:
   - `Azure Pipelines Test Service` — diff coverage checks
   - `officeagent-mi` — E2E validation results
   - Any account with `displayName` ending in `-mi`, `-bot`, `-ci`, or containing `Pipelines` is almost always automation.

Other common filters:

- **Inline vs general**: inline comments have a non-null `threadContext` with `filePath`; general PR-level comments have `threadContext == null`.
- **Open only**: filter `status == 'active'` when the user asks about unresolved comments.

#### Worked example (JMESPath)

Fetch only active human review threads, excluding known bots:

```bash
az devops invoke \
  --area git --resource pullRequestThreads --api-version 7.0 \
  --route-parameters project=ISS repositoryId=<REPO_ID> pullRequestId=<PR_ID> \
  --query "value[?isDeleted==\`false\` \
    && comments[0].commentType=='text' \
    && comments[0].author.displayName!='Azure Pipelines Test Service' \
    && comments[0].author.displayName!='officeagent-mi' \
    && status=='active'].{id:id, file:threadContext.filePath, line:threadContext.rightFileStart.line, author:comments[0].author.displayName, comment:comments[0].content}" \
  -o json
```

Drop the `status=='active'` clause to see all human threads regardless of resolution state. If you discover additional bot accounts in a given repo, extend the excludelist — the list above is not exhaustive.

---

## 3. Replying to PR Threads

Use the bundled script:

```bash
./scripts/reply-to-thread.sh <REPO_ID> <PR_ID> <THREAD_ID> "Fixed in <commit>. <description of fix>."
```

The script handles the `az devops invoke` call, the temp-file payload, cleanup, and the exit-code quirk (see "Important gotcha" above). On success it prints `OK: comment <id> posted to thread <thread_id>` and exits 0.

For multi-line or markdown-heavy replies, pass via `$(cat)`:

```bash
./scripts/reply-to-thread.sh $REPO_ID $PR_ID $THREAD_ID "$(cat <<'EOF'
Fixed in dc6e5fc.

- Added underscore normalization
- Updated tests
EOF
)"
```

### Batch Reply + Resolve

```bash
REPO_ID="<repository-guid>"
PR_ID=<pr-number>

./scripts/reply-to-thread.sh "$REPO_ID" "$PR_ID" <THREAD_ID> "Fixed in dc6e5fc. Added underscore normalization."
./scripts/resolve-thread.sh   "$REPO_ID" "$PR_ID" <THREAD_ID> fixed
```

Run sequentially — the scripts already return correct exit codes, so you *can* chain with `&&` here if you want the second to stop on a first-step failure.

### Raw API (if scripts are unavailable)

```bash
REPLY_FILE=$(mktemp)
echo '{"content":"Fixed in <commit>. <description>.","commentType":1}' > "$REPLY_FILE"

az devops invoke \
  --area git \
  --resource pullRequestThreadComments \
  --route-parameters project=ISS repositoryId=<REPO_ID> pullRequestId=<PR_ID> threadId=<THREAD_ID> \
  --http-method POST \
  --api-version 7.0 \
  --in-file "$REPLY_FILE" \
  --org https://dev.azure.com/office

rm -f "$REPLY_FILE"
```

- `commentType: 1` = regular comment (always use `1` for replies)
- The response JSON includes the new comment's `id` on success (remember the exit-code quirk)

---

## 4. Resolving/Closing Threads

Use the bundled script:

```bash
./scripts/resolve-thread.sh <REPO_ID> <PR_ID> <THREAD_ID> fixed
```

Default status is `fixed` if omitted. On success it prints `OK: thread <id> status -> fixed` and exits 0.

### Thread Status Values

| Status | When to use |
|--------|-------------|
| `fixed` | Code was changed to address the comment |
| `resolved` | Resolved without code change (discussion-only) |
| `closed` | Closed, won't fix |
| `wontFix` | Intentionally not addressing |
| `byDesign` | Current behavior is intentional |
| `pending` | Pending further review |
| `active` | Reopen a resolved thread |

Always reply before resolving — a bare resolution with no reply reads as dismissive. Use `fixed` when the code was changed; `resolved` for discussion-only resolutions.

### Raw API (if scripts are unavailable)

```bash
RESOLVE_FILE=$(mktemp)
echo '{"status":"fixed"}' > "$RESOLVE_FILE"

az devops invoke \
  --area git \
  --resource pullRequestThreads \
  --route-parameters project=ISS repositoryId=<REPO_ID> pullRequestId=<PR_ID> threadId=<THREAD_ID> \
  --http-method PATCH \
  --api-version 7.0 \
  --in-file "$RESOLVE_FILE" \
  --org https://dev.azure.com/office

rm -f "$RESOLVE_FILE"
```

---

## 5. Creating New Comment Threads

Use the bundled script. It handles both general (PR-level) and inline (file+line) forms:

```bash
# General PR-level comment
./scripts/create-thread.sh <REPO_ID> <PR_ID> "## Review summary

Overall looks good. Two issues to address."

# Inline comment on a single line
./scripts/create-thread.sh <REPO_ID> <PR_ID> \
  "This import is missing -- will cause a NameError at runtime." \
  /src/converter/orchestrator.py 61

# Inline comment spanning a range
./scripts/create-thread.sh <REPO_ID> <PR_ID> \
  "Consider extracting this block into a helper." \
  /src/service/handler.ts 108 135
```

On success the script prints `OK: thread <id> created ...` and exits 0.

### Payload notes (for raw API use or debugging)

- `parentCommentId: 0` — required for the root comment of a new thread
- `commentType: 1` — regular comment
- `status: "active"` — for review comments that need attention; omit for informational comments
- `filePath` — path from repo root, prefixed with `/`
- `rightFileStart` / `rightFileEnd` — line range in the new (right-side) version of the file
- `offset` — character offset within the line (use `1` for whole-line comments)

Use heredocs (`cat <<'EOF'`) for markdown content to avoid shell escaping issues with backticks, quotes, and special characters.

---

## 6. Creating a Pull Request

### Auto-Detect Context

Before creating a PR, auto-detect available context:

```bash
# Current branch
git branch --show-current

# Repository name (parse from remote URL)
git remote get-url origin
# Example: https://dev.azure.com/office/ISS/_git/OfficeAgent -> repo name is "OfficeAgent"

# Unpushed commits
git log "origin/$(git branch --show-current)..HEAD" --oneline

# Uncommitted changes
git status --porcelain
```

### Create PR Command

```bash
az repos pr create \
  --title "Your PR Title" \
  --source-branch <branch-name> \
  --target-branch main \
  --repository <repository-name> \
  --description "Your PR description" \
  --org https://dev.azure.com/office \
  --project ISS
```

**Required parameters:**

| Parameter | Description |
|-----------|-------------|
| `--title` | PR title (keep under 70 characters) |
| `--source-branch` | Feature branch name (without `refs/heads/` prefix) |
| `--target-branch` | Target branch (usually `main`) |
| `--repository` | Repository name (e.g., `OfficeAgent`, `augloop-workflows`) |
| `--org` | ADO organization URL |
| `--project` | Project name (e.g., `ISS`) |

**Optional parameters:** `--description`, `--draft`, `--reviewers` (by email)

### PR Description Template

This is a generic starting point. **Check the target repo's `CONTRIBUTING.md`, `AGENTS.md`, or `.github/` for repo-specific conventions and adapt accordingly** — different teams ask for different sections (e.g., augloop-workflows leads with a ChangeGate/Setting rollback plan). Respect what the repo has.

```markdown
#### What?
<1-2 sentence summary of the change>

#### Why?
<Root cause or motivation>

#### How?
<Key files changed and approach taken>

#### Type of Change

- [ ] Bug fix
- [ ] New feature
- [ ] Refactoring
- [ ] Documentation
- [ ] CI/Pipeline

#### Breaking Changes

<!-- List any breaking changes or "None" -->

#### Related Work Items

#<work item id>

#### Checklist

- [ ] Unit tests added/updated
- [ ] No sensitive user data in telemetry logs
- [ ] Tested locally

#### Testing & Eval Results

##### Before and after screenshots (if applicable)

|   Before   |   After    |
| :--------: | :--------: |
| Screenshot | Screenshot |
```

4000 character limit applies; keep each section tight.

### Using Heredoc for Multi-line Descriptions

Use `cat <<'EOF'` to avoid shell escaping issues with markdown:

```bash
az repos pr create \
  --title "Fix empty references in strict grounding" \
  --source-branch dunliu/strict_grounding_citation_fix \
  --target-branch main \
  --repository OfficeAgent \
  --description "$(cat <<'EOF'
#### What?
Fix empty references sections in Word Agent under strict grounding.

#### Why?
LLM invents entity keys from folder names instead of hash-based keys.

#### How?
Added entity key translation in extract_section_contexts.py.

#### Type of Change

- [x] Bug fix

#### Breaking Changes

None

#### Related Work Items

#11157879

#### Checklist

- [x] Unit tests added/updated
- [x] No sensitive user data in telemetry logs
- [x] Tested locally
EOF
)" \
  --org https://dev.azure.com/office \
  --project ISS
```

---

## 7. Updating PR Descriptions

Always read the current description before modifying:

```bash
# Read current description to a file
az repos pr show --id <PR_ID> --query "description" -o tsv > /tmp/pr_desc_current.md

# Edit /tmp/pr_desc_current.md (or prepare a new file via heredoc)
cat > /tmp/pr_desc.md << 'EOF'
#### What?
...fill in template...
EOF

# Update
az repos pr update --id <PR_ID> \
  --description "$(< /tmp/pr_desc.md)" \
  --org https://dev.azure.com/office
```

---

## 8. Embedding Images

Local file paths and base64 data URIs do not work in ADO PR descriptions. Upload images as ADO attachments first, then reference the hosted URL.

Quick path:

```bash
URL=$(./scripts/upload-image.sh /path/to/image.png)
# Embed as: ![Before](${URL})
```

For the full details (raw curl form, byte handling, character-limit budgeting), see `references/images.md`.

---

## 9. Checking if a PR/Commit is in a Build

The reliable method is `git merge-base --is-ancestor` between the PR's merge commit and the build's source commit.

```bash
BUILD_COMMIT=$(az pipelines build show --id <BUILD_ID> \
  --org https://dev.azure.com/office --project ISS \
  --query "sourceVersion" -o tsv)
PR_COMMIT=$(az repos pr show --id <PR_ID> --query "lastMergeCommit.commitId" -o tsv)

git fetch origin main
git merge-base --is-ancestor $PR_COMMIT $BUILD_COMMIT \
  && echo "YES - PR is included in build" \
  || echo "NO - PR is NOT included in build"
```

For additional build queries and context, see `references/builds.md`.

---

## 10. List / Open / Checkout PRs

```bash
# List active PRs
az repos pr list --status active

# List PRs created by you
az repos pr list --creator <your-email>

# Open PR in browser
az repos pr show --id <PR_ID> --open

# Get PR reviewers
az repos pr reviewer list --id <PR_ID>

# Checkout PR locally
az repos pr checkout --id <PR_ID>
```

---

## 11. URL Parsing

Accept both ADO URL formats from users:

| Format | Example |
|--------|---------|
| Modern | `https://dev.azure.com/office/ISS/_git/OfficeAgent/pullrequest/4889729` |
| Legacy | `https://office.visualstudio.com/ISS/_git/OfficeAgent/pullrequest/4889729` |

`office.visualstudio.com` is a legacy alias for `dev.azure.com/office`. Accept both in user input; always use `dev.azure.com/office` in commands.

Extract the numeric PR ID (the number after `/pullrequest/`). Use the PR ID with `az repos pr show --id <PR_ID>` — the CLI resolves the project and repository automatically from the ID.

---

## 12. Cross-Skill Workflows

### `/analyze-pr` -> deep diff analysis

For comprehensive code diff analysis with structured reports, use `/analyze-pr` first. It fetches full file-by-file diffs via a Python script and generates an engineer-friendly markdown report. Then return to `/ado-pr` to act on review comments.

Typical workflow:

1. `/analyze-pr <URL>` — understand the code changes
2. `/ado-pr` — read threads, reply to comments, resolve threads

### `/ado-backlog` -> file bugs from PR review

After reviewing a PR and finding issues, use `/ado-backlog` to create work items:

1. Use this skill to read PR threads and identify issues
2. Use `/ado-backlog` to create a bug linked to the PR URL

---

## Troubleshooting

### Extension Not Installed

```
The command requires the extension azure-devops. Do you want to install it now?
```

Fix: `az extension add --name azure-devops --yes`

### Authentication Issues

```bash
az login
# Or configure a PAT:
az devops login --org https://dev.azure.com/office
```

### `--project` Flag Not Accepted

`az repos pr show` does **not** support `--project`. Configure defaults instead:

```bash
az devops configure --defaults organization=https://dev.azure.com/office project=ISS
```

Or use only `--org` (project is inferred from the PR ID):

```bash
az repos pr show --id <PR_ID> --org https://dev.azure.com/office
```

### `az devops invoke` Returns Exit Code 1 on Success

See "Important gotcha" above. Affects all POST and PATCH calls. The operation succeeds despite the non-zero exit code. The bundled `scripts/` wrappers handle this automatically.

---

## References

- `references/images.md` — full details on embedding images in PR descriptions
- `references/builds.md` — build verification queries and ancestry checks
- [Azure DevOps CLI - Pull Requests](https://learn.microsoft.com/en-us/cli/azure/repos/pr)
- [ADO REST API - Pull Request Threads](https://learn.microsoft.com/en-us/rest/api/azure/devops/git/pull-request-threads)
- [ADO REST API - Git](https://learn.microsoft.com/en-us/rest/api/azure/devops/git)
