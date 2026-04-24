# Embedding Images in PR Descriptions

Local file paths and base64 data URIs do not work in ADO PR descriptions.
Images must be uploaded as ADO attachments first, then referenced by their
hosted URL.

## Quick path: use the bundled script

```bash
URL=$(./scripts/upload-image.sh /path/to/image.png)
# Embed in markdown:
echo "![Before](${URL})"
```

## Manual upload

```bash
TOKEN=$(az account get-access-token \
  --resource "499b84ac-1321-427f-aa17-267ca6975798" \
  --query accessToken -o tsv)

curl -sS -X POST \
  "https://dev.azure.com/office/ISS/_apis/wit/attachments?fileName=my_image.png&api-version=7.0" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @/path/to/local/image.png
```

The response JSON contains the hosted `url`. Reference it with standard
markdown: `![Alt text](<url>)`.

## Notes

- The `wit/attachments` endpoint is the reliable way to host images for ADO
  markdown. Other endpoints (e.g., build artifacts) are not accessible from
  PR description rendering.
- PR descriptions have a **4000 character limit**. Image URLs are ~170
  characters each, so budget accordingly.
- Use `--data-binary` (not `--data`) to preserve binary content — `--data`
  performs line-ending normalization and will corrupt images.
- The resource GUID `499b84ac-1321-427f-aa17-267ca6975798` is the fixed
  Azure DevOps REST API resource identifier; it is not per-org.
