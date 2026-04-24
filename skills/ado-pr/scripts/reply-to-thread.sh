#!/usr/bin/env bash
# Post a reply to an existing PR thread.
#
# Usage: reply-to-thread.sh <repo_id> <pr_id> <thread_id> <content>
#
# <content> may contain newlines and markdown. Pass via heredoc or $(cat file).
# Exits 0 on success (new comment id returned), 1 on failure.
#
# Why this script exists: `az devops invoke --http-method POST` returns exit
# code 1 even on success, so inline invocations can't be chained with &&.
# This wrapper parses the response JSON and produces a real exit code.

set -u

if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <repo_id> <pr_id> <thread_id> <content>" >&2
  exit 2
fi

REPO_ID="$1"
PR_ID="$2"
THREAD_ID="$3"
CONTENT="$4"
ORG="${ADO_ORG:-https://dev.azure.com/office}"
PROJECT="${ADO_PROJECT:-ISS}"

PAYLOAD_FILE=$(mktemp)
RESPONSE_FILE=$(mktemp)
trap 'rm -f "$PAYLOAD_FILE" "$RESPONSE_FILE"' EXIT

python -c "
import json, sys
json.dump({'content': sys.argv[1], 'commentType': 1}, open(sys.argv[2], 'w'))
" "$CONTENT" "$PAYLOAD_FILE"

az devops invoke \
  --area git \
  --resource pullRequestThreadComments \
  --route-parameters project="$PROJECT" repositoryId="$REPO_ID" pullRequestId="$PR_ID" threadId="$THREAD_ID" \
  --http-method POST \
  --api-version 7.0 \
  --in-file "$PAYLOAD_FILE" \
  --org "$ORG" > "$RESPONSE_FILE" || true

COMMENT_ID=$(python -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(d.get('id', ''))
except Exception:
    pass
" "$RESPONSE_FILE")

if [[ -n "$COMMENT_ID" ]]; then
  echo "OK: comment $COMMENT_ID posted to thread $THREAD_ID"
  exit 0
fi

echo "FAIL: no comment id in response" >&2
cat "$RESPONSE_FILE" >&2
exit 1
