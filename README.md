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
