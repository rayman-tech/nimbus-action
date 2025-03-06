# Nimbus Action

An action for the Nimbus service that deploys projects to your self-hosted servers.

## Usage

Here's an example of how to use this action in a workflow file:

```yaml
name: Nimbus Example

on:
  push:
    branches:
      - main

jobs:
  nimbus-deploy:
    name: Deploy with Nimbus
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        id: checkout
        uses: actions/checkout@v4

      # Change @main to a specific commit SHA or version tag, e.g.:
      # rayman-tech/nimbus-action@e76147da8e5c81eaf017dede5645551d4b94427b
      # rayman-tech/nimbus-action@v0.0.1
      - name: Deploy
        uses: rayman-tech/nimbus-action@main
        with:
          nimbus-path: deploy/nimbus.yaml # Optional
      - name: Deploy
        uses: rayman-tech/nimbus-action@main
        with:
          nimbus-path: nimbus.yaml
```

## Inputs

| Input         | Default       | Description                                    |
| ------------- | ------------- | ---------------------------------------------- |
| `nimbus-path` | `nimbus.yaml` | The path to the nimbus file in your repository |

## Outputs

| Input          | Description                                |
| -------------- | ------------------------------------------ |
| `service-urls` | List of URLs created from the nimbus file |
