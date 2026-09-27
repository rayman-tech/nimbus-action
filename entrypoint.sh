#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/pr-comment.sh"

if [ "$GITHUB_EVENT_NAME" = "delete" ]; then
    # --- Delete flow: clean up branch preview deployments ---

    REF_TYPE=$(jq -r '.ref_type' "$GITHUB_EVENT_PATH")
    if [ "$REF_TYPE" != "branch" ]; then
        echo "Ignoring delete event for ref_type=$REF_TYPE (not a branch)"
        exit 0
    fi

    BRANCH_NAME=$(jq -r '.ref' "$GITHUB_EVENT_PATH")
    PROJECT_NAME=$(grep '^app:' "$NIMBUS_PATH" | awk '{print $2}')

    if [ -z "$PROJECT_NAME" ]; then
        echo "::error ::Could not parse project name from $NIMBUS_PATH"
        exit 1
    fi

    ENCODED_PROJECT=$(printf '%s' "$PROJECT_NAME" | jq -sRr @uri)
    ENCODED_BRANCH=$(printf '%s' "$BRANCH_NAME" | jq -sRr @uri)

    HTTP_RESPONSE=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" \
        -X DELETE "${NIMBUS_SERVER}/branch?project=${ENCODED_PROJECT}&branch=${ENCODED_BRANCH}" \
        --header "X-Api-Key: ${NIMBUS_API_KEY}")

    HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed -e 's/HTTPSTATUS\:.*//g')
    HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

    if [ "$HTTP_STATUS" -eq 204 ] || [ "$HTTP_STATUS" -eq 200 ]; then
        echo "### ✅ Branch cleanup successful for \`$BRANCH_NAME\`" >> "$GITHUB_STEP_SUMMARY"
    else
        echo "::error ::Branch cleanup failed with status $HTTP_STATUS"
        {
            echo "### ❌ Branch Cleanup Failed"
            echo "Branch: \`$BRANCH_NAME\` | Status Code: $HTTP_STATUS"
            echo ""
            echo '```'"$HTTP_BODY"'```'
        } >> "$GITHUB_STEP_SUMMARY"
        exit 1
    fi
else
    # --- Push flow: deploy (existing behavior) ---

    REPORT=$(mktemp)
    trap 'rm -f "$REPORT"' EXIT
    publish_report() {
        cat "$REPORT" >> "$GITHUB_STEP_SUMMARY"
        # Keep comment failures independent from the deployment result.
        set +e
        post_pr_comment "$REPORT"
        comment_status=$?
        set -e
        if [[ "$comment_status" -ne 0 ]]; then
            echo '::warning ::Could not update the Nimbus PR comment. Check pull-requests: write permissions.'
        fi
    }

    DEPLOY_COMMIT="$GITHUB_SHA"
    REF="${GITHUB_REF}"
    if [[ "$GITHUB_EVENT_NAME" == "pull_request" ]]; then
        BRANCH_NAME=$(jq -r '.pull_request.head.ref' "$GITHUB_EVENT_PATH")
        DEPLOY_COMMIT=$(jq -r '.pull_request.head.sha' "$GITHUB_EVENT_PATH")
    elif [[ "$REF" == refs/heads/* ]]; then
        BRANCH_NAME="${REF#refs/heads/}"
    elif [[ "$REF" == refs/tags/* ]]; then
        BRANCH_NAME="${REF#refs/tags/}"
    else
        echo "::error ::Unsupported GITHUB_REF format: $REF"
        exit 1
    fi

    # Preserve the real commit for PR reports even when using prebuilt images.
    COMMIT_ARGS=()
    case "${TAG_IMAGES:-true}" in
        true) COMMIT_ARGS=(--form "commit=${DEPLOY_COMMIT}") ;;
        false) ;;
        *) echo '::error ::tag-images must be true or false'; exit 1 ;;
    esac

    HTTP_RESPONSE=$(curl --silent --location "${NIMBUS_SERVER}/deploy" --write-out "HTTPSTATUS:%{http_code}" \
        --header "X-Api-Key: ${NIMBUS_API_KEY}" \
        --form "file=@${NIMBUS_PATH}" \
        --form "branch=${BRANCH_NAME}" \
        "${COMMIT_ARGS[@]}")

    HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed -e 's/HTTPSTATUS\:.*//g')
    HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

    if [ "$HTTP_STATUS" -ne 200 ]; then
        echo "::error ::Deployment failed with status $HTTP_STATUS"
        echo "::error ::Response body: $HTTP_BODY"

        {
            echo "### ❌ Deployment Failed"
            echo "Status Code: $HTTP_STATUS"
            echo ""
            echo '```'"$HTTP_BODY"'```'
        } >> "$REPORT"
        publish_report
        exit 1
    fi

    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        printf 'service-urls=%s\n' "$(jq -c '.services' <<< "$HTTP_BODY")" >> "$GITHUB_OUTPUT"
    fi

    SERVICE_COUNT=$(echo "$HTTP_BODY" | jq -r '.services | length')

    if [ "$SERVICE_COUNT" -eq 0 ]; then
        echo "### ✅ Deployment Successful" >> "$REPORT"
        publish_report
        exit 0
    fi

    {
        echo "### 🚀 Deployed Service URLs"
        echo "| Service | URLs |"
        echo "|---------|------|"
        echo "$HTTP_BODY" | jq -r '
            .services | to_entries[] |
            "| \(.key) | \((.value | if length > 0 then join("<br>") else "No public URL" end)) |"
        '
    } >> "$REPORT"
    publish_report
fi
