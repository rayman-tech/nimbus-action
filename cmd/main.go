package main

import (
	"bytes"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"os/exec"

	"github.com/rayman-tech/nimbus-action/internal/logger"
)

var log = logger.GetLogger()

const numArgs = 3

func main() {
	/* Read arguments */
	if len(os.Args) < 3 {
		log.Error("Usage: go run main.go <filename> ")
		os.Exit(1)
	}
	nimbusfile, nimbusServerUrl := os.Args[1], os.Args[2]

	/* Create multipart form to attach nimbus file */
	bodyBuf := &bytes.Buffer{}
	bodyWriter := multipart.NewWriter(bodyBuf)
	fileWriter, err := bodyWriter.CreateFormFile("file", nimbusfile)
	if err != nil {
		log.Error("Error creating form file", "msg", err)
		os.Exit(1)
	}

	/* Copy file to multipart form */
	fileContents, err := os.Open(nimbusfile)
	if err != nil {
		log.Error("Error opening file", "msg", err)
		os.Exit(1)
	}

	_, err = io.Copy(fileWriter, fileContents)
	if err != nil {
		log.Error("Error copying file", "msg", err)
		os.Exit(1)
	}

	err = bodyWriter.Close()
	if err != nil {
		log.Error("Error closing body writer", "msg", err)
		os.Exit(1)
	}

	/* Send request to Nimbus server */
	req, err := http.NewRequest("POST", nimbusServerUrl+"/deploy", bodyBuf)
	if err != nil {
		log.Error("Error creating request", "msg", err)
		os.Exit(1)
	}
	req.Header.Set("Content-Type", bodyWriter.FormDataContentType())
	req.Header.Set("X-Api-Key", os.Getenv("NIMBUS_API_KEY"))

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		log.Error("Error sending request", "msg", err)
		os.Exit(1)
	}
	defer resp.Body.Close()

	/* Check response */
	if resp.StatusCode != http.StatusOK {
		log.Error("Error response from server", "status", resp.Status)
		os.Exit(1)
	}

	log.Info("Successfully deployed to nimbus server", "status", resp.Status)

	cmd := "echo \"service-urls\"=[] >> $GITHUB_OUTPUT"
	_, err = exec.Command("sh", "-c", cmd).Output()
	if err != nil {
		log.Error("Error writing to github output", "msg", err)
		os.Exit(1)
	}
}
