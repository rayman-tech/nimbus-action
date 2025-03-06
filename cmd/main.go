package main

import (
	"os"
	"os/exec"

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

	log.Debug("File contents: " + string(filecontents))

	cmd := "echo \"service-urls\"=[] >> $GITHUB_OUTPUT"
	_, err = exec.Command("sh", "-c", cmd).Output()
	if err != nil {
		log.Error("Error writing to github output", "msg", err)
		os.Exit(1)
	}
}
