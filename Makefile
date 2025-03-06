.PHONY: all server build

all:
	go run cmd/*.go

server:
	go run cmd/*.go server

build:
	go build -o bin/nimbus-action cmd/*.go
