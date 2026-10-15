#!/usr/bin/env python3
"""Load and validate customer.manifest.yaml; derive bootstrap variables."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError as e:  # pragma: no cover
    print("PyYAML required: pip install -r requirements.txt", file=sys.stderr)
    raise SystemExit(1) from e

SLUG_RE = re.compile(r"^[a-z][a-z0-9-]{0,62}$")
SCHEMA_PATH = Path(__file__).resolve().parent.parent / "schema" / "customer.manifest.schema.json"


def load_manifest(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as f:
        data = yaml.safe_load(f)
    if not isinstance(data, dict):
        raise ValueError("manifest root must be a mapping")
    return data


def _require(data: dict[str, Any], *keys: str) -> Any:
    cur: Any = data
    for key in keys:
        if not isinstance(cur, dict) or key not in cur:
            raise ValueError(f"missing required field: {'.'.join(keys)}")
        cur = cur[key]
    return cur


def validate_against_schema(data: dict[str, Any]) -> None:
    """Optional JSON Schema check when jsonschema is installed."""
    if not SCHEMA_PATH.is_file():
        return
    try:
        import jsonschema
    except ImportError:
        return
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    try:
        jsonschema.validate(instance=data, schema=schema)
    except jsonschema.ValidationError as e:
        path = ".".join(str(p) for p in e.absolute_path) or "(root)"
        raise ValueError(f"schema validation failed at {path}: {e.message}") from e


def validate_manifest(data: dict[str, Any]) -> None:
    validate_against_schema(data)

    customer = _require(data, "customer")
    customer_id = _require(customer, "id")
    if not isinstance(customer_id, str) or not SLUG_RE.match(customer_id):
        raise ValueError("customer.id must be lowercase slug (a-z, 0-9, hyphen)")

    org = _require(customer, "org")
    if not isinstance(org, str) or not org.strip():
        raise ValueError("customer.org is required")

    git_host = customer.get("git_host", "github")
    if git_host != "github":
        raise ValueError("only git_host: github is supported in v1")

    products = data.get("products") or {}
    if not any(products.get(k) for k in ("registry", "bridge_connectors", "pbms_connectors")):
        raise ValueError("at least one product must be enabled")

    repos = _require(data, "repos")
    for key in ("helm", "versions"):
        name = repos.get(key)
        if not isinstance(name, str) or not name.strip():
            raise ValueError(f"repos.{key} is required")

    if products.get("registry") and not repos.get("registry"):
        raise ValueError("repos.registry required when products.registry is true")
    if products.get("bridge_connectors") and not repos.get("bridge_connectors"):
        raise ValueError("repos.bridge_connectors required when products.bridge_connectors is true")
    if products.get("pbms_connectors") and not repos.get("pbms_connectors"):
        raise ValueError("repos.pbms_connectors required when products.pbms_connectors is true")

    for key in ("bridge_connectors", "pbms_connectors"):
        items = data.get(key) or []
        if not isinstance(items, list):
            raise ValueError(f"{key} must be a list of connector directory names")
        for item in items:
            if not isinstance(item, str) or not re.match(r"^[a-z][a-z0-9-]*$", item):
                raise ValueError(f"{key} entry must be lowercase slug: {item!r}")

    prefix = _require(_require(data, "artifacts"), "container_registry", "prefix")
    if not isinstance(prefix, str) or "/" not in prefix:
        raise ValueError("artifacts.container_registry.prefix must look like ghcr.io/org")

    ci = data.get("ci") or {}
    for pin in ("registry_platform_version", "bridge_platform_version", "pbms_platform_version"):
        if pin in ci and not str(ci[pin]).strip():
            raise ValueError(f"ci.{pin} must be non-empty when set")


def derive_vars(data: dict[str, Any]) -> dict[str, str]:
    customer = data["customer"]
    repos = data["repos"]
    ci = data.get("ci") or {}
    reg = data["artifacts"]["container_registry"]

    customer_id = customer["id"]
    org = customer["org"]
    helm_repo = f"{org}/{repos['helm']}"
    versions_repo = f"{org}/{repos['versions']}"
    helm_branch = ci.get("helm_branch", "main")
    versions_branch = ci.get("versions_branch", "develop")
    prefix = reg["prefix"].rstrip("/")

    # ghcr.io/moz-openg2p -> registry ghcr.io, namespace moz-openg2p
    if prefix.startswith("ghcr.io/"):
        container_registry = "ghcr.io"
        container_namespace = prefix.removeprefix("ghcr.io/")
    else:
        container_registry = prefix.split("/")[0]
        container_namespace = "/".join(prefix.split("/")[1:])

    return {
        "CUSTOMER_ID": customer_id,
        "CUSTOMER_ORG": org,
        "CUSTOMER_DISPLAY_NAME": customer.get("display_name", customer_id),
        "HELM_REPO": helm_repo,
        "HELM_BRANCH": helm_branch,
        "HELM_REPO_URL": f"https://raw.githubusercontent.com/{helm_repo}/{helm_branch}",
        "VERSIONS_REPO": versions_repo,
        "VERSIONS_BRANCH": versions_branch,
        "CONTAINER_REGISTRY": container_registry,
        "CONTAINER_NAMESPACE": container_namespace,
        "CONTAINER_PREFIX": prefix,
        "IMAGE_PREFIX": ci.get("image_prefix", customer_id),
        "PACKAGING_REF": ci.get("packaging_ref", "v1"),
        "DEFAULT_BRANCH": ci.get("default_branch", "develop"),
        "HELM_REPO_NAME": repos["helm"],
        "VERSIONS_REPO_NAME": repos["versions"],
        "REGISTRY_REPO_NAME": repos.get("registry", f"{customer_id}-registry"),
        "BRIDGE_REPO_NAME": repos.get("bridge_connectors", f"{customer_id}-bridge-connectors"),
        "PBMS_REPO_NAME": repos.get("pbms_connectors", f"{customer_id}-pbms-connectors"),
        "SLUG": customer_id,
        "CHART_NAME": f"openg2p-{customer_id}-registry",
        "EXTENSION_DIR": f"{customer_id}-extension",
        "EXTENSION_MODULE": f"openg2p_registry_{customer_id.replace('-', '_')}_extension",
        "RP_VERSION": ci.get("registry_platform_version", "1.2.2-rc.489"),
        "BP_VERSION": ci.get("bridge_platform_version", "develop"),
        "PBMS_VERSION": ci.get("pbms_platform_version", "develop"),
        "BRIDGE_CHART_NAME": f"openg2p-{customer_id}-bridge",
        "PBMS_CHART_NAME": f"openg2p-{customer_id}-pbms",
    }


def connector_module(connector_dir: str, product: str) -> str:
    slug = connector_dir.replace("-", "_")
    if product == "bridge":
        return f"openg2p_g2p_bridge_{slug}"
    return f"openg2p_pbms_{slug}"


def connector_package(connector_dir: str, customer_id: str, product: str) -> str:
    if product == "bridge":
        return f"openg2p-{customer_id}-g2p-bridge-{connector_dir}"
    return f"openg2p-{customer_id}-pbms-{connector_dir}"


def plan(data: dict[str, Any]) -> dict[str, Any]:
    """Return structured bootstrap plan."""
    vars_ = derive_vars(data)
    products = data.get("products") or {}
    repos = data["repos"]
    org = data["customer"]["org"]

    destinations = [
        {
            "kind": "helm",
            "name": repos["helm"],
            "full_name": f"{org}/{repos['helm']}",
            "branch": vars_["HELM_BRANCH"],
            "skeleton": "destinations/helm",
        },
        {
            "kind": "versions",
            "name": repos["versions"],
            "full_name": f"{org}/{repos['versions']}",
            "branch": vars_["VERSIONS_BRANCH"],
            "skeleton": "destinations/versions",
        },
    ]

    extensions = []
    if products.get("registry"):
        extensions.append(
            {
                "kind": "registry",
                "name": repos["registry"],
                "full_name": f"{org}/{repos['registry']}",
                "branch": vars_["DEFAULT_BRANCH"],
                "pack": "packs/registry",
                "versions_folder": repos["registry"],
            }
        )
    if products.get("bridge_connectors"):
        extensions.append(
            {
                "kind": "bridge-connectors",
                "name": repos["bridge_connectors"],
                "full_name": f"{org}/{repos['bridge_connectors']}",
                "branch": vars_["DEFAULT_BRANCH"],
                "pack": "packs/bridge-connectors",
                "versions_folder": repos["bridge_connectors"],
                "connectors": data.get("bridge_connectors") or [],
            }
        )
    if products.get("pbms_connectors"):
        extensions.append(
            {
                "kind": "pbms-connectors",
                "name": repos["pbms_connectors"],
                "full_name": f"{org}/{repos['pbms_connectors']}",
                "branch": vars_["DEFAULT_BRANCH"],
                "pack": "packs/pbms-connectors",
                "versions_folder": repos["pbms_connectors"],
                "connectors": data.get("pbms_connectors") or [],
            }
        )

    return {
        "variables": vars_,
        "destinations": destinations,
        "extensions": extensions,
    }


def all_template_vars(vars_: dict[str, str]) -> dict[str, str]:
    """All placeholders available in pack templates."""
    return dict(vars_)


def env_file_content(vars_: dict[str, str], header: str = "") -> str:
    lines: list[str] = []
    if header:
        lines.append(header)
    for key, value in sorted(all_template_vars(vars_).items()):
        lines.append(f"{key}={value}")
    return "\n".join(lines) + "\n"


def ci_env_content(vars_: dict[str, str]) -> str:
    keys = (
        "CUSTOMER_ID",
        "PACKAGING_REF",
        "HELM_REPO",
        "HELM_BRANCH",
        "HELM_REPO_URL",
        "VERSIONS_REPO",
        "VERSIONS_BRANCH",
        "CONTAINER_REGISTRY",
        "CONTAINER_NAMESPACE",
        "IMAGE_PREFIX",
    )
    lines = ["# Generated by openg2p-customer-bundle — do not edit by hand."]
    for key in keys:
        lines.append(f"{key}={vars_[key]}")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Customer manifest utilities")
    parser.add_argument("manifest", type=Path, help="Path to customer.manifest.yaml")
    parser.add_argument(
        "command",
        choices=("validate", "vars", "plan", "ci-env", "export-env"),
        help="Operation",
    )
    args = parser.parse_args()

    data = load_manifest(args.manifest)
    validate_manifest(data)
    vars_ = derive_vars(data)

    if args.command == "validate":
        print("OK")
    elif args.command == "vars":
        print(json.dumps(vars_, indent=2))
    elif args.command == "plan":
        print(json.dumps(plan(data), indent=2))
    elif args.command == "ci-env":
        print(ci_env_content(vars_), end="")
    elif args.command == "export-env":
        print(
            env_file_content(
                vars_,
                "# Template variables for openg2p-customer-bundle render",
            ),
            end="",
        )


if __name__ == "__main__":
    main()
