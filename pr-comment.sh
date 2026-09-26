#!/usr/bin/env bash

post_pr_comment() (
    set -euo pipefail

    [[ "${PR_COMMENT:-true}" == "true" && -n "${GH_TOKEN:-}" ]] || exit 0
    [[ "${GITHUB_REF:-}" == refs/heads/* || "${GITHUB_EVENT_NAME:-}" == "pull_request" ]] || exit 0

    api="${GITHUB_API_URL:-https://api.github.com}/repos/${GITHUB_REPOSITORY}"
    github_api() {
        curl --silent --show-error --fail \
            --header "Authorization: Bearer ${GH_TOKEN}" \
            --header 'Accept: application/vnd.github+json' \
            --header 'Content-Type: application/json' "$@"
    }

    head="${GITHUB_REPOSITORY%%/*}:${BRANCH_NAME}"
    pulls=$(github_api --get "${api}/pulls" \
        --data-urlencode 'state=open' --data-urlencode "head=$head" --data-urlencode 'per_page=100')
    numbers=$(jq -r --arg sha "$DEPLOY_COMMIT" --arg repo "$GITHUB_REPOSITORY" \
        '.[] | select(.head.sha == $sha and .head.repo.full_name == $repo) | .number' <<< "$pulls")
    [[ -n "$numbers" ]] || exit 0

    key=$(printf '%s\n' "$NIMBUS_SERVER" "$NIMBUS_PATH" "$BRANCH_NAME" | sha256sum | cut -d' ' -f1)
    marker="<!-- nimbus-deployment:${key} -->"
    report=$(mktemp)
    trap 'rm -f "$report"' EXIT
    {
        echo "$marker"
        echo '### Nimbus deployment'
        echo
        printf 'Config: `%s` · Commit: `%s` · [Workflow run](%s/%s/actions/runs/%s)\n\n' \
            "$NIMBUS_PATH" "$DEPLOY_COMMIT" "${GITHUB_SERVER_URL:-https://github.com}" \
            "$GITHUB_REPOSITORY" "$GITHUB_RUN_ID"
        if [[ "$HTTP_STATUS" == 200 ]]; then
            cat "$1"
        else
            printf '**Deployment failed** (HTTP %s). See the workflow run for details.\n' "$HTTP_STATUS"
        fi
    } > "$report"
    payload=$(jq -Rs '{body: .}' < "$report")

    for number in $numbers; do
        comment_id=''
        page=1
        while :; do
            comments=$(github_api "${api}/issues/${number}/comments?per_page=100&page=${page}")
            comment_id=$(jq -r --arg marker "$marker" \
                '.[] | select(.user.login == "github-actions[bot]" and (.body | startswith($marker))) | .id' \
                <<< "$comments" | head -n1)
            [[ -n "$comment_id" || $(jq 'length' <<< "$comments") -lt 100 ]] && break
            page=$((page + 1))
        done
        # A newer push may have landed while this deployment was running.
        current_sha=$(github_api "${api}/pulls/${number}" | jq -r '.head.sha')
        [[ "$current_sha" == "$DEPLOY_COMMIT" ]] || continue
        if [[ -n "$comment_id" ]]; then
            github_api -X PATCH "${api}/issues/comments/${comment_id}" --data "$payload" > /dev/null
        else
            github_api -X POST "${api}/issues/${number}/comments" --data "$payload" > /dev/null
        fi
    done
)
