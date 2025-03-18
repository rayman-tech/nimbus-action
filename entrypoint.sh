#!/usr/bin/env bash

envsubst < "${NIMBUS_PATH}" | curl --location "${NIMBUS_SERVER}/deploy" \
    --header "X-Api-Key: ${NIMBUS_API_KEY}" \
    --form "file=@-"

echo "service-urls=[]" >> $GITHUB_OUTPUT
