import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1]


class ActionTests(unittest.TestCase):
    def setUp(self):
        self.requests = []
        self.comments = []
        self.pulls = [{"number": 7, "head": {"sha": "abc123", "repo": {"full_name": "owner/repo"}}}]
        self.services = {"web": ["https://preview.example.com"], "admin": []}
        self.deploy_status = 200
        self.github_status = 200
        case = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def handle_request(self):
                body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
                case.requests.append((self.command, self.path, body))
                status = 200
                if self.path == "/deploy":
                    status = case.deploy_status
                    response = {"services": case.services} if status == 200 else {"error": "private diagnostic"}
                elif self.path.startswith("/branch?"):
                    response = {}
                elif case.github_status != 200:
                    status, response = case.github_status, {"message": "Forbidden"}
                elif "/issues/comments/" in self.path and self.command == "PATCH":
                    case.comments[0]["body"] = json.loads(body)["body"]
                    response = case.comments[0]
                elif "/comments" in self.path:
                    if self.command == "POST":
                        comment = {"id": 8, "body": json.loads(body)["body"], "user": {"login": "github-actions[bot]"}}
                        case.comments.append(comment)
                        status, response = 201, comment
                    else:
                        response = case.comments
                elif "/pulls?" in self.path:
                    response = case.pulls
                else:
                    response = case.pulls[0]
                self.send_response(status)
                self.end_headers()
                self.wfile.write(json.dumps(response).encode())

            do_GET = do_POST = do_PATCH = do_DELETE = handle_request

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        folder = Path(self.tmp.name)
        (folder / "nimbus.yaml").write_text("app: sample\n")
        self.event = folder / "event.json"
        self.event.write_text(json.dumps({"ref_type": "branch", "ref": "feature/test"}))
        self.summary = folder / "summary.md"
        self.output = folder / "output"
        self.env = dict(os.environ, GITHUB_EVENT_NAME="push", GITHUB_REF="refs/heads/feature/test",
                        GITHUB_SHA="abc123", GITHUB_REPOSITORY="owner/repo", GITHUB_RUN_ID="42",
                        GITHUB_EVENT_PATH=str(self.event), GITHUB_STEP_SUMMARY=str(self.summary),
                        GITHUB_OUTPUT=str(self.output),
                        NIMBUS_PATH="nimbus.yaml", NIMBUS_SERVER=f"http://127.0.0.1:{self.server.server_port}",
                        NIMBUS_API_KEY="test-key", GH_TOKEN="test-token", PR_COMMENT="true")
        self.env.pop("TAG_IMAGES", None)
        self.env["GITHUB_API_URL"] = self.env["NIMBUS_SERVER"]

    def run_action(self):
        return subprocess.run(["bash", str(ROOT / "entrypoint.sh")], env=self.env,
                              cwd=self.tmp.name, capture_output=True, text=True)

    def test_create_then_update_comment_and_keep_summary(self):
        self.assertEqual(self.run_action().returncode, 0)
        self.assertIn("https://preview.example.com", self.comments[0]["body"])
        self.assertIn("No public URL", self.comments[0]["body"])
        self.assertIn("actions/runs/42", self.comments[0]["body"])
        self.assertIn("Deployed Service URLs", self.summary.read_text())
        self.services = {"web": ["https://new.example.com"]}
        self.assertEqual(self.run_action().returncode, 0)
        self.assertEqual(len(self.comments), 1)
        self.assertIn("https://new.example.com", self.comments[0]["body"])
        self.assertTrue(any(method == "PATCH" for method, _, _ in self.requests))

    def test_configurations_have_separate_comments(self):
        self.run_action()
        self.env["NIMBUS_PATH"] = "admin.yaml"
        (Path(self.tmp.name) / "admin.yaml").write_text("app: admin\n")
        self.assertEqual(self.run_action().returncode, 0)
        self.assertEqual(len(self.comments), 2)

    def test_permission_failure_does_not_fail_deploy(self):
        self.github_status = 403
        result = self.run_action()
        self.assertEqual(result.returncode, 0)
        self.assertIn("::warning", result.stdout)
        self.assertIn("Deployed Service URLs", self.summary.read_text())

    def test_failed_deploy_posts_status_without_private_response(self):
        self.deploy_status = 500
        self.assertEqual(self.run_action().returncode, 1)
        self.assertIn("Deployment failed", self.comments[0]["body"])
        self.assertNotIn("private diagnostic", self.comments[0]["body"])

    def test_no_open_pr(self):
        self.pulls = []
        self.assertEqual(self.run_action().returncode, 0)
        self.assertFalse(self.comments)

    def test_stale_commit_does_not_comment(self):
        self.pulls[0]["head"]["sha"] = "newer"
        self.assertEqual(self.run_action().returncode, 0)
        self.assertFalse(self.comments)

    def test_private_only_services_are_reported(self):
        self.services = {"admin": []}
        self.assertEqual(self.run_action().returncode, 0)
        self.assertIn("No public URL", self.comments[0]["body"])

    def test_no_services(self):
        self.services = {}
        self.assertEqual(self.run_action().returncode, 0)
        self.assertIn("Deployment Successful", self.comments[0]["body"])

    def test_opt_out(self):
        self.env["PR_COMMENT"] = "false"
        self.assertEqual(self.run_action().returncode, 0)
        self.assertEqual(len(self.requests), 1)

    def test_pull_request_uses_head_branch_and_commit(self):
        self.env.update(GITHUB_EVENT_NAME="pull_request", GITHUB_REF="refs/pull/7/merge", GITHUB_SHA="merge-sha")
        self.event.write_text(json.dumps({"pull_request": {"head": {"ref": "feature/test", "sha": "abc123"}}}))
        self.assertEqual(self.run_action().returncode, 0)
        self.assertIn(b"abc123", self.requests[0][2])
        self.assertIn("abc123", self.comments[0]["body"])

    def test_commit_tagging_stays_enabled_by_default(self):
        self.assertEqual(self.run_action().returncode, 0)
        self.assertIn(b'name="commit"\r\n\r\nabc123', self.requests[0][2])

    def test_prebuilt_images_omit_commit_without_losing_report_identity(self):
        self.env["TAG_IMAGES"] = "false"
        (Path(self.tmp.name) / "nimbus.yaml").write_text(
            "app: sample\nservices:\n  - name: echo\n    image: hashicorp/http-echo:1.0.0\n")
        self.assertEqual(self.run_action().returncode, 0)
        body = self.requests[0][2]
        self.assertNotIn(b'name="commit"', body)
        self.assertIn(b'hashicorp/http-echo:1.0.0', body)
        self.assertIn(b'name="branch"\r\n\r\nfeature/test', body)
        self.assertIn("abc123", self.comments[0]["body"])

    def test_invalid_tagging_option_does_not_deploy(self):
        self.env["TAG_IMAGES"] = "typo"
        self.assertNotEqual(self.run_action().returncode, 0)
        self.assertFalse(self.requests)

    def test_service_urls_output_is_json(self):
        self.assertEqual(self.run_action().returncode, 0)
        key, value = self.output.read_text().strip().split("=", 1)
        self.assertEqual(key, "service-urls")
        self.assertEqual(json.loads(value), self.services)

    def test_branch_delete_only_cleans_up(self):
        self.env["GITHUB_EVENT_NAME"] = "delete"
        self.assertEqual(self.run_action().returncode, 0)
        self.assertEqual(len(self.requests), 1)
        self.assertEqual(self.requests[0][0], "DELETE")
        self.assertIn("cleanup successful", self.summary.read_text())

    def test_tag_delete_is_ignored(self):
        self.env["GITHUB_EVENT_NAME"] = "delete"
        self.event.write_text('{"ref_type":"tag","ref":"v2"}')
        self.assertEqual(self.run_action().returncode, 0)
        self.assertFalse(self.requests)


if __name__ == "__main__":
    unittest.main()
