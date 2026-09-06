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

For compatibility, the server translates supported legacy NGINX annotations in
`nimbus.yaml` into Envoy policies. It rejects unsupported NGINX annotations instead
of silently dropping their behavior. Annotations are not an unrestricted way to
configure Envoy. For example, this external authentication configuration remains
supported:

```yaml
services:
  - name: web
    template: http
    public: true
    image: registry.example.com/web:latest
    network:
      ports: [8080]
    annotations:
      nginx.ingress.kubernetes.io/ssl-redirect: "true"
      nginx.ingress.kubernetes.io/auth-url: "https://idp.example.com/sessions/whoami"
      nginx.ingress.kubernetes.io/auth-signin: "https://proxy.example.com/oauth2/start?rd=$scheme://$host$request_uri"
```

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
