# Customer bundle runbook

## Prerequisites

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt   # PyYAML + jsonschema
```

The `bootstrap/customer-bundle` CLI prefers `.venv/bin` when present.

- [GitHub CLI](https://cli.github.com/) (`gh auth login`) with permission to create private repos in the customer org
- `git`

## 1. Prepare manifest

```bash
cp schema/customer.manifest.yaml my-customer.manifest.yaml
# edit: customer.id, org, repos.*, artifacts.container_registry.prefix, ci.* pins
```

Schema: [`schema/customer.manifest.schema.json`](../schema/customer.manifest.schema.json)

Validate and preview:

```bash
./bootstrap/customer-bundle validate my-customer.manifest.yaml
./bootstrap/customer-bundle plan my-customer.manifest.yaml
```

## 2. Local smoke (recommended before create)

```bash
./bootstrap/customer-bundle smoke my-customer.manifest.yaml
# inspect out/registry out/bridge-connectors out/pbms-connectors
```

## 3. Dry-run bootstrap

```bash
./bootstrap/customer-bundle create --manifest my-customer.manifest.yaml --dry-run
```

## 4. Create repos

```bash
./bootstrap/customer-bundle create --manifest my-customer.manifest.yaml
```

Creates:

| Repo | Role |
|------|------|
| `{repos.helm}` | Destination: packaged `.tgz` + `index.yaml` |
| `{repos.versions}` | Destination: changelogs |
| `{repos.registry}` | Extension + seeded CI (if enabled) |
| `{repos.bridge_connectors}` | Extension + seeded CI (if enabled) |
| `{repos.pbms_connectors}` | Extension + seeded CI (if enabled) |

## 5. Set secrets and Actions policy

Printed again at end of `create`. Minimum:

1. Org or repo secret **`OPENG2P_BOT_GITHUB_PAT`** — Contents write on helm + versions
2. Each extension repo → Settings → Actions → **Allow all actions and reusable workflows**
3. Confirm GHCR package publish is allowed for the org

Optional: `OPENROUTER_API_KEY` for AI changelog summaries.

Re-sync Actions variables after editing the manifest:

```bash
./bootstrap/customer-bundle update-vars --manifest my-customer.manifest.yaml
```

## 6. First publish verification

1. Clone an extension repo, make a tiny change under the extension/connector tree, push to `develop`
2. Confirm Actions succeeds
3. Confirm image(s) in GHCR
4. Confirm `.tgz` + `index.yaml` in `{customer}-helm`
5. Confirm changelog under `{customer}-versions/<extension-repo>/`

Docs-only pushes are skipped via `paths-ignore` on `**.md`.

## 7. Add a connector later

```bash
# into a local clone or rendered out/ tree
./bootstrap/customer-bundle add-connector \
  --product bridge \
  --name my-bank-connector \
  --target ./out/bridge-connectors \
  --manifest my-customer.manifest.yaml
```

Also add the name under `bridge_connectors:` / `pbms_connectors:` in the manifest for future bootstraps, and extend the Docker `COPY`/`RUN` lines if the image was already rendered.

## 8. Platform version pins (frozen tags)

In the manifest `ci:` section:

| Field | Used for |
|-------|----------|
| `registry_platform_version` | Registry Docker `FROM` + helm dependency |
| `bridge_platform_version` | Bridge Celery `FROM` + helm dependency |
| `pbms_platform_version` | PBMS API `FROM` + helm dependency |
| `packaging_ref` | `openg2p-packaging` reusable workflow ref |

Prefer concrete versions (e.g. `1.2.2-rc.489`) over floating `develop` for production customers.

## 9. Helm overlay note

Wrapper charts follow the [farmer-registry](https://github.com/OpenG2P/farmer-registry/tree/1.2) pattern: dependency aliased (`registry` / `bridge` / `pbms`) with image tag paths under `.Values.<alias>.*`. If an upstream chart renames keys, update both `values.yaml` and `chart-image-paths` in the seeded workflow.

## Implementation status

| Phase | Component | Status |
|-------|-----------|--------|
| 1 | Destination skeletons | Done |
| 2 | Registry pack + CI | Done |
| 3 | Bridge / PBMS packs | Done |
| 4 | Bootstrap CLI (`create`, `update-vars`, `add-connector`) | Done |
| 5 | Hardening (schema, path filters, secrets checklist, runbook) | Done |
