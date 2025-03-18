#!/usr/bin/env bash

tmpfile=$(mktemp)
envsubst < "${NIMBUS_PATH}" > "${tmpfile}"

curl --location "${NIMBUS_SERVER}/deploy" \
--header "X-Api-Key: ${NIMBUS_API_KEY}" \
--form "file=@${tmpfile}"

echo "service-urls=[]" >> $GITHUB_OUTPUT
rm -f "${tmpfile}"
