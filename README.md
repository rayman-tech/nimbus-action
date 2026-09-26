# Nimbus Action

An action for the Nimbus service that deploys projects to your self-hosted servers.

## Usage

Here's an example of how to use this action in a workflow file:

### Simple (no Docker build)

If your services use pre-built images, a single job handles both deploy and cleanup:

```yaml
name: Nimbus Deploy
on:
  push:
  delete:

jobs:
  nimbus:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: rayman-tech/nimbus-action@v2
        with:
          api-key: ${{ secrets.NIMBUS_API_KEY }}
          nimbus-server: ${{ secrets.NIMBUS_URL }}
          nimbus-path: nimbus.yaml
```

### With Docker build

If your workflow builds a Docker image before deploying, split into two jobs so the `delete` event skips the build:

```yaml
name: Build and Deploy
on:
  push:
  delete:

jobs:
  build-and-deploy:
    if: github.event_name != 'delete'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        with:
          registry: registry.example.com
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}

      - uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: registry.example.com/my-app:${{ github.sha }}

      - uses: rayman-tech/nimbus-action@v2
        with:
          api-key: ${{ secrets.NIMBUS_API_KEY }}
          nimbus-server: ${{ secrets.NIMBUS_URL }}
          nimbus-path: nimbus.yaml

  cleanup:
    if: github.event_name == 'delete'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: rayman-tech/nimbus-action@v2
        with:
          api-key: ${{ secrets.NIMBUS_API_KEY }}
          nimbus-server: ${{ secrets.NIMBUS_URL }}
          nimbus-path: nimbus.yaml
```

Adding the `delete` event enables automatic cleanup of branch preview deployments when branches are deleted (e.g., after merging a PR). Tag deletions are ignored.

## Routing with Envoy Gateway

The Nimbus server creates Gateway API routes and Envoy policies for public
`http` services. The action uploads your configuration to Nimbus; it does not
create Kubernetes resources itself. Existing action inputs, service URL outputs,
and the `ingress` hostname field remain unchanged.

Configure Envoy Gateway and certificate management on the Nimbus server before
upgrading it. Services using external authentication or the `spa` feature also
require the server's `NIMBUS_ROUTE_HELPER_IMAGE` to point to a digest-pinned Nimbus
image containing the route helper.

Use `envoy.nimbus.dev/*` annotations in `nimbus.yaml` to configure Nimbus-generated
Envoy routes and policies. These are Nimbus settings, not native Envoy Gateway
annotations. Unsupported settings and conflicts with deprecated NGINX aliases are
rejected. For example, external authentication:

```yaml
services:
  - name: web
    template: http
    public: true
    image: registry.example.com/web:latest
    network:
      ports: [8080]
    annotations:
      envoy.nimbus.dev/ssl-redirect: "true"
      envoy.nimbus.dev/auth-url: "https://idp.example.com/sessions/whoami"
      envoy.nimbus.dev/auth-signin: "https://proxy.example.com/oauth2/start?rd=$scheme://$host$request_uri"
```

For gRPC, keep `features: [grpc]` and use explicit Envoy settings:

```yaml
annotations:
  envoy.nimbus.dev/backend-protocol: "h2c"
  envoy.nimbus.dev/connect-timeout: "5s"
  envoy.nimbus.dev/stream-idle-timeout: "300s"
  envoy.nimbus.dev/request-timeout: "0s"
```

Nimbus also supports `grpc-service` / `grpc-method` exact matching and opt-in
`grpc-retry-count`, `grpc-retry-on`, and `grpc-per-retry-timeout` settings under
the same prefix. Enable retries only for operations safe to repeat. Backend TLS
and multiple routing rules are not exposed by this interface. Supported old
NGINX keys remain deprecated aliases; use explicit Envoy keys for new configuration.

See the sample [`nimbus.yaml`](./nimbus.yaml) and the
[Nimbus routing documentation](https://github.com/rayman-tech/nimbus#envoy-gateway-routing)
for supported options and server prerequisites. Existing deployments migrate when
redeployed through the updated server; updating this action alone does not migrate
any routes.

## Inputs

| Environment       | Default       | Description                                    |
| ----------------- | ------------- | ---------------------------------------------- |
| `nimbus-server`   |     N/A       | The URL of the Nimbus server                   |
| `api-key`         |     N/A       | The API key for the Nimbus project             |
| `nimbus-path`     | `nimbus.yaml` | The path to the nimbus file in your repository |

## Outputs

| Input          | Description                                |
| -------------- | ------------------------------------------ |
| `service-urls` | List of URLs created from the nimbus file |

## PR deployment comments

The action creates or updates one comment per Nimbus server, config path, and
branch on matching open PRs. Comments include deployment status, commit, workflow
link, and public service URLs. Private services are listed without a public URL.
The Actions summary remains available. Comment failures produce a warning and do
not change the deployment result; failed deployments still fail the step.

Grant the deployment job permission to comment:

```yaml
permissions:
  contents: read
  pull-requests: write
```

The new `github-token` input defaults to `${{ github.token }}`. No caller token
input is needed when using the standard Actions token. Set `pr-comment: 'false'`
to disable comments. The updater identifies comments authored by
`github-actions[bot]`; use the standard Actions token for automatic updates.

Push workflows find open PRs for their branch and deployed commit. If the PR is
opened after the first deployment finishes, the next push or manual workflow
rerun creates the comment. `pull_request` events are also supported using the
head branch and head SHA; callers must build and deploy that same head commit.
Older commits do not replace a newer PR's deployment comment. Branch deletion
continues to clean up the preview without posting a deployment comment.

After merging a compatible action release, publish a version such as `v2.1.0`
and move the floating `v2` tag to that commit. Existing `@v2` callers then receive
the feature, subject to their token permissions. Merging into `main` alone does
not update the `v2` tag.
