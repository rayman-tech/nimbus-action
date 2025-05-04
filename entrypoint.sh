#!/usr/bin/env bash

RESPONSE=$(envsubst < "${NIMBUS_PATH}" | curl --silent --location "${NIMBUS_SERVER}/deploy" \
    --header "X-Api-Key: ${NIMBUS_API_KEY}" \
    --form "file=@-")

echo "### 🚀 Deployed Service URLs" >> $GITHUB_STEP_SUMMARY
echo "| Service | URLs |" >> $GITHUB_STEP_SUMMARY
echo "|---------|------|" >> $GITHUB_STEP_SUMMARY

echo "$RESPONSE" | jq -r '.services | to_entries[] | "| \(.key) | \(.value | join("<br>")) |"' >> $GITHUB_STEP_SUMMARY
