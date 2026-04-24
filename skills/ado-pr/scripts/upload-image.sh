#!/usr/bin/env bash
# Upload a local image as an ADO attachment and print the hosted URL.
#
# Usage: upload-image.sh <image_path> [filename]
#
# The hosted URL can be embedded in PR descriptions with standard markdown:
#   ![Alt text](<url>)
#
# Why this script exists: the upload requires an auth token, a specific
# endpoint (wit/attachments), and --data-binary (not --data). Easy to get
# wrong; encapsulating it keeps invocations reliable.

set -u

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <image_path> [filename]" >&2
  exit 2
fi

IMAGE_PATH="$1"
FILENAME="${2:-$(basename "$IMAGE_PATH")}"
ORG="${ADO_ORG:-https://dev.azure.com/office}"
PROJECT="${ADO_PROJECT:-ISS}"
ADO_RESOURCE_GUID="499b84ac-1321-427f-aa17-267ca6975798"

if [[ ! -f "$IMAGE_PATH" ]]; then
  echo "FAIL: image not found: $IMAGE_PATH" >&2
  exit 1
fi

TOKEN=$(az account get-access-token --resource "$ADO_RESOURCE_GUID" --query accessToken -o tsv)
if [[ -z "$TOKEN" ]]; then
  echo "FAIL: could not get access token (run 'az login'?)" >&2
  exit 1
fi

RESPONSE_FILE=$(mktemp)
trap 'rm -f "$RESPONSE_FILE"' EXIT

curl -sS -X POST \
  "$ORG/$PROJECT/_apis/wit/attachments?fileName=$FILENAME&api-version=7.0" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary "@$IMAGE_PATH" \
  -o "$RESPONSE_FILE"

URL=$(python -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(d.get('url', ''))
except Exception:
    pass
" "$RESPONSE_FILE")

if [[ -n "$URL" ]]; then
  echo "$URL"
  exit 0
fi

echo "FAIL: no url in response" >&2
cat "$RESPONSE_FILE" >&2
exit 1
