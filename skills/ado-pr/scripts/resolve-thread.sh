#!/usr/bin/env bash
# Resolve (or otherwise change the status of) a PR thread.
#
# Usage: resolve-thread.sh <repo_id> <pr_id> <thread_id> [status]
#
# Default status is "fixed". Valid values: fixed, resolved, closed, wontFix,
# byDesign, pending, active (reopens a thread).
#
# Why this script exists: `az devops invoke --http-method PATCH` returns exit
# code 1 even on success. This wrapper verifies the response status and
# produces a real exit code.

set -u

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <repo_id> <pr_id> <thread_id> [status]" >&2
  exit 2
fi

REPO_ID="$1"
PR_ID="$2"
THREAD_ID="$3"
STATUS="${4:-fixed}"
ORG="${ADO_ORG:-https://dev.azure.com/office}"
PROJECT="${ADO_PROJECT:-ISS}"

PAYLOAD_FILE=$(mktemp)
RESPONSE_FILE=$(mktemp)
trap 'rm -f "$PAYLOAD_FILE" "$RESPONSE_FILE"' EXIT

python -c "
import json, sys
json.dump({'status': sys.argv[1]}, open(sys.argv[2], 'w'))
" "$STATUS" "$PAYLOAD_FILE"

az devops invoke \
  --area git \
  --resource pullRequestThreads \
  --route-parameters project="$PROJECT" repositoryId="$REPO_ID" pullRequestId="$PR_ID" threadId="$THREAD_ID" \
  --http-method PATCH \
  --api-version 7.0 \
  --in-file "$PAYLOAD_FILE" \
  --org "$ORG" > "$RESPONSE_FILE" || true

NEW_STATUS=$(python -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(d.get('status', ''))
except Exception:
    pass
" "$RESPONSE_FILE")

if [[ "$NEW_STATUS" == "$STATUS" ]]; then
  echo "OK: thread $THREAD_ID status -> $NEW_STATUS"
  exit 0
fi

echo "FAIL: thread status did not update (got '$NEW_STATUS', wanted '$STATUS')" >&2
cat "$RESPONSE_FILE" >&2
exit 1
