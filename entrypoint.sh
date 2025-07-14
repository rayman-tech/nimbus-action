#!/usr/bin/env bash

set -euo pipefail

BRANCH_NAME="${GITHUB_REF##*/}"

# Make the request and capture both the body and status code
HTTP_RESPONSE=$(curl --location "${NIMBUS_SERVER}/deploy" --write-out "HTTPSTATUS:%{http_code}" \
    --header "X-Api-Key: ${NIMBUS_API_KEY}" \
    --form "file=@${NIMBUS_PATH}" \
    --form "branch=${BRANCH_NAME}")

# Extract the body and the status code
HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed -e 's/HTTPSTATUS\:.*//g')
HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

# Check HTTP status
if [ "$HTTP_STATUS" -ne 200 ]; then
    echo "::error ::Deployment failed with status $HTTP_STATUS"
    echo "::error ::Response body: $HTTP_BODY"

    {
        echo "### ❌ Deployment Failed"
        echo "Status Code: $HTTP_STATUS"
        echo ""
        echo '```'"$HTTP_BODY"'```'
    } >> "$GITHUB_STEP_SUMMARY"
    exit 1
fi

# Determine if any service URLs were returned
SERVICE_COUNT=$(echo "$HTTP_BODY" | jq -r '[.services[] | length] | add // 0')

if [ "$SERVICE_COUNT" -eq 0 ]; then
    echo "### ✅ Deployment Successful" >> "$GITHUB_STEP_SUMMARY"
    exit 0
fi

# Success output with URLs
{
    echo "### 🚀 Deployed Service URLs"
    echo "| Service | URLs |"
    echo "|---------|------|"
    echo "$HTTP_BODY" | jq -r '.services | to_entries[] | "| \(.key) | \(.value | join("<br>")) |"'
} >> "$GITHUB_STEP_SUMMARY"
