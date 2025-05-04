FROM alpine:latest

WORKDIR /app
RUN apk update && apk add --no-cache --upgrade bash curl gettext jq
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
