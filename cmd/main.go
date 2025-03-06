package main

import (
	"os"

	"github.com/rayman/nimbus-action/internal/logger"
)

var log = logger.GetLogger()

func main() {
	if len(os.Args) < 2 {
		log.Error("Usage: go run main.go <filename> ")
		return
	}

	nimbusfile := os.Args[1]
	filecontents, err := os.ReadFile(nimbusfile)
	if err != nil {
		log.Error("Error reading file", "msg", err)
		os.Exit(1)
	}

	log.Info("File contents: " + string(filecontents))
}
