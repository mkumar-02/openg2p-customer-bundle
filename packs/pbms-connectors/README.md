# {{CUSTOMER_DISPLAY_NAME}} PBMS Connectors

Private PBMS connector packages for **{{CUSTOMER_ORG}}**.

The PBMS product core ([pbms](https://github.com/OpenG2P/pbms)) stays upstream.
This repo holds customer connector implementations and builds derived runtime
images that install them.

## Connector packages (seeded stubs)

{{CONNECTOR_LIST_MD}}

## Private API image

`docker/apis/Dockerfile` extends `openg2p/openg2p-pbms-apis:{{PBMS_VERSION}}` and
installs the connector packages above.

## CI

Seeded workflows publish on every push:

- Docker image → `{{CONTAINER_PREFIX}}/{{IMAGE_PREFIX}}-pbms-apis`
- Helm chart source → packaged to `{{HELM_REPO}}`
- Changelog → `{{VERSIONS_REPO}}` under `{{PBMS_REPO_NAME}}/`
