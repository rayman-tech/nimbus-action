FROM golang:alpine AS build
WORKDIR /app
COPY . .
RUN apk update && apk add make
RUN make build

FROM alpine:latest
WORKDIR /app
COPY --from=build /app/bin/nimbus-action /app/nimbus-action
ENTRYPOINT ["/app/nimbus-action"]
