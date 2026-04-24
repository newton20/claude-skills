# Checking if a PR / Commit is in a Build

Common question: "did my PR make it into build X?" The reliable way to
answer it is to compare the PR's merge commit against the build's source
commit using `git merge-base --is-ancestor`.

## Get the build's source commit

```bash
BUILD_COMMIT=$(az pipelines build show --id <BUILD_ID> \
  --org https://dev.azure.com/office --project ISS \
  --query "sourceVersion" -o tsv)
```

## Get the PR's merge commit

```bash
PR_COMMIT=$(az repos pr show --id <PR_ID> --query "lastMergeCommit.commitId" -o tsv)
```

`lastMergeCommit` is populated once the PR is merged. For active PRs, this
field may be null — ask about the merge commit specifically once the PR
completes.

## Check ancestry

```bash
git fetch origin main
git merge-base --is-ancestor $PR_COMMIT $BUILD_COMMIT \
  && echo "YES - PR is included in build" \
  || echo "NO - PR is NOT included in build"
```

Why this works: `--is-ancestor` returns 0 if the first commit is reachable
from the second. If the PR's merge commit is an ancestor of the build's
source commit, the build contains the PR.

## Useful build queries

```bash
# Build number, version, result
az pipelines build show --id <BUILD_ID> \
  --query "{buildNumber: buildNumber, version: triggerInfo.version, result: result}" \
  -o table

# Source branch and commit
az pipelines build show --id <BUILD_ID> \
  --query "{branch: sourceBranch, commit: sourceVersion, status: status}" \
  -o table
```
