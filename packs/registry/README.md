# {{CUSTOMER_DISPLAY_NAME}} Registry

Customer registry extension for **{{CUSTOMER_DISPLAY_NAME}}**, built on
[OpenG2P registry-platform](https://github.com/OpenG2P/registry-platform).

This repo was bootstrapped by [openg2p-customer-bundle](https://github.com/OpenG2P/openg2p-customer-bundle).

## What you implement

| Path | Purpose |
|------|---------|
| `{{EXTENSION_DIR}}/` | Domain extension (models, schemas, seed metadata) |
| `docker/` | Thin images: platform base + your extension |
| `helm/{{CHART_NAME}}/` | Helm chart source (packaged to `{{HELM_REPO}}` by CI) |

## CI

Push to this repo triggers **Build & Publish** (seeded by the bundle):

1. Compute version
2. Build & push Docker images to `{{CONTAINER_PREFIX}}`
3. Package helm chart → `{{HELM_REPO}}` (branch `{{HELM_BRANCH}}`)
4. Append changelog → `{{VERSIONS_REPO}}` (branch `{{VERSIONS_BRANCH}}`)

## Next steps

1. Implement your domain in `{{EXTENSION_DIR}}/`
2. Adjust `docker/` and `helm/` values for your environment
3. Push to `{{DEFAULT_BRANCH}}` and verify artifacts in destination repos
