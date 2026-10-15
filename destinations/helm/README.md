# {{CUSTOMER_ORG}}/{{HELM_REPO_NAME}}

Private Helm chart repository for **{{CUSTOMER_DISPLAY_NAME}}**.

This repo holds **packaged chart archives only** (`.tgz` + `index.yaml`). Chart source
lives in the extension repos; CI pushes here on every publish.

## Layout

```text
index.yaml
<chart>-<version>.tgz
```

## Consumption

- **Rancher / Helm**: add this private git repository (branch: `{{HELM_BRANCH}}`).
- No public GitHub Pages site is required.

## Who writes here

Extension-repo CI only (via `OPENG2P_BOT_GITHUB_PAT`). Customers do not commit charts manually.
