#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

apply_pack_renames() {
  local pack_dir="$1"
  local rendered_dir="$2"
  local vars_file="$3"
  local pack_yaml="$pack_dir/pack.yaml"

  [ -f "$pack_yaml" ] || return 0
  python3 - <<'PY' "$pack_yaml" "$rendered_dir" "$vars_file"
import sys
from pathlib import Path

pack_yaml, rendered_dir, vars_file = map(Path, sys.argv[1:4])
text = pack_yaml.read_text()
if "renames:" not in text:
    raise SystemExit(0)

vars = {}
for line in vars_file.read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    vars[k] = v

import yaml  # type: ignore
data = yaml.safe_load(text) or {}
renames = data.get("renames") or {}
root = Path(rendered_dir)
for src, dst_tpl in renames.items():
    dst_name = dst_tpl
    for k, v in vars.items():
        dst_name = dst_name.replace("{{" + k + "}}", v)
    src_path = root / src
    dst_path = root / dst_name
    if src_path.exists():
        src_path.rename(dst_path)
PY
}

render_extension_pack() {
  local pack_dir="$1"
  local rendered_dir="$2"
  local vars_file="$3"
  local manifest="$4"
  local kind="$5"

  render_pack "$pack_dir" "$rendered_dir" "$vars_file"
  apply_pack_renames "$pack_dir" "$rendered_dir" "$vars_file"
  apply_connector_stubs "$manifest" "$kind" "$pack_dir" "$rendered_dir" "$vars_file"
}

apply_connector_stubs() {
  local manifest="$1"
  local kind="$2"
  local pack_dir="$3"
  local rendered_dir="$4"
  local vars_file="$5"

  python3 - <<'PY' "$manifest" "$kind" "$pack_dir" "$rendered_dir" "$vars_file"
import re
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
kind = sys.argv[2]
pack_dir = Path(sys.argv[3])
rendered_dir = Path(sys.argv[4])
vars_file = Path(sys.argv[5])

sys.path.insert(0, str(manifest_path.parent.parent / "bootstrap"))
from manifest import connector_module, connector_package, load_manifest  # noqa: E402

data = load_manifest(manifest_path)
customer_id = data["customer"]["id"]

if kind == "bridge-connectors":
    connectors = data.get("bridge_connectors") or []
    product = "bridge"
elif kind == "pbms-connectors":
    connectors = data.get("pbms_connectors") or []
    product = "pbms"
else:
    raise SystemExit(0)

vars_ = {}
for line in vars_file.read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    vars_[k] = v

stub_root = pack_dir / "_stub" / "connector"
if not stub_root.is_dir():
    raise SystemExit(f"connector stub missing: {stub_root}")

def render_text(content: str, extra: dict[str, str]) -> str:
    merged = {**vars_, **extra}
    for key, val in merged.items():
        content = content.replace("{{" + key + "}}", val)
    return content

root = Path(rendered_dir)
install_lines: list[str] = []
check_lines: list[str] = []
readme_lines: list[str] = []

for connector_dir in connectors:
    module = connector_module(connector_dir, product)
    package = connector_package(connector_dir, customer_id, product)
    extra = {
        "CONNECTOR_DIR": connector_dir,
        "CONNECTOR_MODULE": module,
        "CONNECTOR_PACKAGE": package,
    }
    dest = root / connector_dir
    dest.mkdir(parents=True, exist_ok=True)

    for src in stub_root.rglob("*"):
        if src.is_dir():
            continue
        rel = src.relative_to(stub_root)
        rel_parts = [render_text(p, extra) for p in rel.parts]
        out = dest.joinpath(*rel_parts)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(render_text(src.read_text(encoding="utf-8"), extra), encoding="utf-8")

    install_lines.append(f"COPY {connector_dir}/ /app/{connector_dir}/")
    install_lines.append(f"RUN pip install --no-cache-dir /app/{connector_dir}/")
    check_lines.append(f"          test -d {connector_dir}")
    readme_lines.append(f"- `{connector_dir}/` — stub package `{package}`")

install_block = "\n".join(install_lines) if install_lines else "# No connectors configured in manifest"
check_block = "\n".join(check_lines) if check_lines else '          echo "no connectors in manifest"'
readme_block = "\n".join(readme_lines) if readme_lines else "- _(none configured in manifest)_"

for path in root.rglob("*"):
    if not path.is_file():
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    if "{{CONNECTOR_INSTALL_BLOCK}}" in text or "{{CONNECTOR_CHECKS}}" in text or "{{CONNECTOR_LIST_MD}}" in text:
        text = text.replace("{{CONNECTOR_INSTALL_BLOCK}}", install_block)
        text = text.replace("{{CONNECTOR_CHECKS}}", check_block)
        text = text.replace("{{CONNECTOR_LIST_MD}}", readme_block)
        path.write_text(text, encoding="utf-8")
PY
}
