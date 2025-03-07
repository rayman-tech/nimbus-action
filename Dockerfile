# FROM golang:alpine AS build
# WORKDIR /app
# COPY . .
# RUN apk update && apk add make
# RUN make build

FROM alpine:latest
WORKDIR /app
RUN apk add --no-cache --upgrade bash
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
