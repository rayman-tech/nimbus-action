#!/usr/bin/env sh

curl --location '${NIMBUS_SERVER}' \
--header 'X-Api-Key: ${NIMBUS_API_KEY}' \
--form 'file=${NIMBUS_PATH}'
