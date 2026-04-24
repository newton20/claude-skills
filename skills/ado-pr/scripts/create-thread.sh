#!/usr/bin/env bash
# Create a new PR comment thread — general (PR-level) or inline (file+line).
#
# Usage:
#   create-thread.sh <repo_id> <pr_id> <content>
#       -- general PR-level comment
#   create-thread.sh <repo_id> <pr_id> <content> <file_path> <line>
#       -- inline comment at a specific file+line (whole-line)
#   create-thread.sh <repo_id> <pr_id> <content> <file_path> <line_start> <line_end>
#       -- inline comment spanning a line range
#
# <content> may contain newlines and markdown.
# <file_path> is the path from repo root (with or without leading /).
#
# Why this script exists: `az devops invoke --http-method POST` returns exit
# code 1 even on success. This wrapper parses the response JSON for the new
# thread id and produces a real exit code.

set -u

if [[ $# -lt 3 ]]; then
  cat >&2 <<USAGE
Usage:
  $0 <repo_id> <pr_id> <content>                                       # general
  $0 <repo_id> <pr_id> <content> <file_path> <line>                    # inline
  $0 <repo_id> <pr_id> <content> <file_path> <line_start> <line_end>   # range
USAGE
  exit 2
fi

REPO_ID="$1"
PR_ID="$2"
CONTENT="$3"
FILE_PATH="${4:-}"
LINE_START="${5:-}"
LINE_END="${6:-$LINE_START}"
ORG="${ADO_ORG:-https://dev.azure.com/office}"
PROJECT="${ADO_PROJECT:-ISS}"

# Normalize file path: ensure leading slash if provided
if [[ -n "$FILE_PATH" && "${FILE_PATH:0:1}" != "/" ]]; then
  FILE_PATH="/$FILE_PATH"
fi

PAYLOAD_FILE=$(mktemp)
RESPONSE_FILE=$(mktemp)
trap 'rm -f "$PAYLOAD_FILE" "$RESPONSE_FILE"' EXIT

python -c "
import json, sys
content, file_path, line_start, line_end = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
payload = {
    'comments': [{'parentCommentId': 0, 'content': content, 'commentType': 1}],
    'status': 'active',
}
if file_path:
    line_start = int(line_start)
    line_end = int(line_end)
    payload['threadContext'] = {
        'filePath': file_path,
        'rightFileStart': {'line': line_start, 'offset': 1},
        'rightFileEnd': {'line': line_end, 'offset': 1},
    }
json.dump(payload, open(sys.argv[5], 'w'))
" "$CONTENT" "$FILE_PATH" "$LINE_START" "$LINE_END" "$PAYLOAD_FILE"

az devops invoke \
  --area git \
  --resource pullRequestThreads \
  --route-parameters project="$PROJECT" repositoryId="$REPO_ID" pullRequestId="$PR_ID" \
  --http-method POST \
  --api-version 7.0 \
  --in-file "$PAYLOAD_FILE" \
  --org "$ORG" > "$RESPONSE_FILE" || true

THREAD_ID=$(python -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(d.get('id', ''))
except Exception:
    pass
" "$RESPONSE_FILE")

if [[ -n "$THREAD_ID" ]]; then
  if [[ -n "$FILE_PATH" ]]; then
    echo "OK: thread $THREAD_ID created at $FILE_PATH:$LINE_START-$LINE_END"
  else
    echo "OK: thread $THREAD_ID created (PR-level)"
  fi
  exit 0
fi

echo "FAIL: no thread id in response" >&2
cat "$RESPONSE_FILE" >&2
exit 1
