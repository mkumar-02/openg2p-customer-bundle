#!/usr/bin/env bash
# Render all extension packs locally and verify expected paths exist.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${1:-$ROOT/schema/customer.manifest.yaml}"

"$ROOT/bootstrap/customer-bundle" render-all "$MANIFEST"

python3 - <<'PY' "$MANIFEST" "$ROOT/out"
import json
import re
import subprocess
import sys
from pathlib import Path

manifest, out_root = sys.argv[1:3]
plan = json.loads(
    subprocess.check_output(
        ["python3", str(Path(manifest).parent.parent / "bootstrap/manifest.py"), manifest, "plan"],
        text=True,
    )
)

checks: list[tuple[Path, str]] = []
failed = 0


def ok(path: Path, label: str) -> None:
    global failed
    if path.exists():
        print(f"OK  {label}: {path}")
    else:
        print(f"FAIL {label}: missing {path}", file=sys.stderr)
        failed += 1


for ext in plan["extensions"]:
    kind = ext["kind"]
    if kind == "registry":
        out = Path(out_root) / "registry"
    elif kind == "bridge-connectors":
        out = Path(out_root) / "bridge-connectors"
    elif kind == "pbms-connectors":
        out = Path(out_root) / "pbms-connectors"
    else:
        raise SystemExit(f"unknown kind: {kind}")

    ok(out / ".github/workflows/build-publish.yml", f"{kind} CI")
    ok(out / ".openg2p/ci.env", f"{kind} ci.env")

    wf = (out / ".github/workflows/build-publish.yml").read_text(encoding="utf-8")
    if "paths-ignore:" not in wf:
        print(f"FAIL {kind}: missing paths-ignore in build-publish.yml", file=sys.stderr)
        failed += 1
    else:
        print(f"OK  {kind} paths-ignore")

    for connector in ext.get("connectors") or []:
        ok(out / connector / "pyproject.toml", f"{kind}/{connector}")

cid = plan["variables"]["CUSTOMER_ID"]
if any(e["kind"] == "registry" for e in plan["extensions"]):
    ok(Path(out_root) / "registry" / f"{cid}-extension", "registry extension dir")
    ok(
        Path(out_root) / "registry" / "helm" / f"openg2p-{cid}-registry" / "Chart.yaml",
        "registry chart",
    )
if any(e["kind"] == "bridge-connectors" for e in plan["extensions"]):
    ok(
        Path(out_root) / "bridge-connectors" / "helm" / f"openg2p-{cid}-bridge" / "Chart.yaml",
        "bridge chart",
    )
    docker = (Path(out_root) / "bridge-connectors" / "docker/celery/Dockerfile").read_text()
    if "COPY bank-connectors/" not in docker and plan["extensions"]:
        # only assert when bank-connectors is in the plan
        connectors = next(e["connectors"] for e in plan["extensions"] if e["kind"] == "bridge-connectors")
        if "bank-connectors" in connectors:
            print("FAIL bridge Dockerfile missing connector COPY", file=sys.stderr)
            failed += 1
        else:
            print("OK  bridge Dockerfile connectors")
    else:
        print("OK  bridge Dockerfile connectors")
if any(e["kind"] == "pbms-connectors" for e in plan["extensions"]):
    ok(
        Path(out_root) / "pbms-connectors" / "helm" / f"openg2p-{cid}-pbms" / "Chart.yaml",
        "pbms chart",
    )

# No unresolved {{PLACEHOLDER}} left in rendered text files (except intentional none)
placeholder_re = re.compile(r"\{\{[A-Z0-9_]+\}\}")
for root in Path(out_root).iterdir():
    if not root.is_dir() or root.name == "__pycache__":
        continue
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix in {".png", ".svg", ".ico"}:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        hits = placeholder_re.findall(text)
        if hits:
            print(f"FAIL unresolved placeholders in {path}: {hits}", file=sys.stderr)
            failed += 1

if failed:
    raise SystemExit(f"{failed} check(s) failed")
print("smoke-render: all checks passed")
PY
