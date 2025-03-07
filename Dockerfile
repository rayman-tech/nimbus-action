# FROM golang:alpine AS build
# WORKDIR /app
# COPY . .
# RUN apk update && apk add make
# RUN make build

FROM alpine:latest
WORKDIR /app
RUN apk update && apk add --no-cache --upgrade bash curl
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
