#!/usr/bin/env bash

curl --location "${NIMBUS_SERVER}/deploy" \
--header "X-Api-Key: ${NIMBUS_API_KEY}" \
--form "file=@${NIMBUS_PATH}"
