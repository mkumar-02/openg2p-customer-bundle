# {{CUSTOMER_DISPLAY_NAME}} Bridge Connectors

Private G2P Bridge connector packages for **{{CUSTOMER_ORG}}**.

Layout mirrors [g2p-bridge-connectors](https://github.com/OpenG2P/g2p-bridge-connectors).
Implement connector interfaces in the packages below, then configure Bridge to
select your implementations via `G2P_BRIDGE_*_IMPL` / `*_IMPLS` environment
variables.

## Connector packages (seeded stubs)

{{CONNECTOR_LIST_MD}}

## Private Celery image

This repo builds a derived Celery image (`docker/celery/Dockerfile`) that
installs the connector packages above on top of
`openg2p/openg2p-bridge-celery:{{BP_VERSION}}`. Override the Bridge chart Celery
image to your private registry copy after CI publishes.

## CI

Seeded workflows publish on every push:

- Docker image → `{{CONTAINER_PREFIX}}/{{IMAGE_PREFIX}}-bridge-celery`
- Helm chart source → packaged to `{{HELM_REPO}}`
- Changelog → `{{VERSIONS_REPO}}` under `{{BRIDGE_REPO_NAME}}/`
