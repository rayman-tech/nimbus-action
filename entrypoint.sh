#!/usr/bin/env bash

set -euo pipefail

BRANCH_NAME="${GITHUB_REF##*/}"

# Make the request and capture both the body and status code
HTTP_RESPONSE=$(envsubst < "${NIMBUS_PATH}" | curl --silent --location "${NIMBUS_SERVER}/deploy" --write-out "HTTPSTATUS:%{http_code}" \
    --header "X-Api-Key: ${NIMBUS_API_KEY}" \
    --form "file=@-" \
    --form "branch=${BRANCH_NAME}")

# Extract the body and the status code
HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed -e 's/HTTPSTATUS\:.*//g')
HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

# Check HTTP status
if [ "$HTTP_STATUS" -ne 200 ]; then
    echo "::error ::Deployment failed with status $HTTP_STATUS"
    echo "::error ::Response body: $HTTP_BODY"

    echo "### ❌ Deployment Failed" >> "$GITHUB_STEP_SUMMARY"
    echo "Status Code: $HTTP_STATUS" >> "$GITHUB_STEP_SUMMARY"
    echo "" >> "$GITHUB_STEP_SUMMARY"
    echo '```\n'"$HTTP_BODY"'\n```' >> "$GITHUB_STEP_SUMMARY"
    exit 1
fi

# Success output
echo "### 🚀 Deployed Service URLs" >> "$GITHUB_STEP_SUMMARY"
echo "| Service | URLs |" >> "$GITHUB_STEP_SUMMARY"
echo "|---------|------|" >> "$GITHUB_STEP_SUMMARY"

echo "$HTTP_BODY" | jq -r '.services | to_entries[] | "| \(.key) | \(.value | join("<br>")) |"' >> "$GITHUB_STEP_SUMMARY"
