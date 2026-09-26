FROM alpine:latest

WORKDIR /app
RUN apk update && apk add --no-cache --upgrade bash curl gettext jq
COPY entrypoint.sh pr-comment.sh /

ENTRYPOINT ["/entrypoint.sh"]
