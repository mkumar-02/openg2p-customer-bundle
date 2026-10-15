#!/usr/bin/env bash
# Scaffold a new connector package stub into a local extension checkout (or rendered out/).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PRODUCT=""
NAME=""
TARGET=""
MANIFEST="$ROOT/schema/customer.manifest.yaml"

usage() {
  cat <<EOF
Usage: bootstrap/add-connector.sh --product bridge|pbms --name NAME --target DIR [options]

Options:
  --product bridge|pbms   which connector pack
  --name NAME             connector directory slug (e.g. bank-connectors)
  --target DIR            existing rendered/extension checkout to add into
  --manifest PATH         used for customer display name / id (default: schema/...)
  -h, --help

Creates a stub package under TARGET/NAME from the pack _stub/connector template.
Does not modify the manifest — add the name to bridge_connectors / pbms_connectors
yourself if you want future bootstraps to include it.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --product) PRODUCT="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --manifest) MANIFEST="$2"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$PRODUCT" ] || die "--product is required"
[ -n "$NAME" ] || die "--name is required"
[ -n "$TARGET" ] || die "--target is required"
[ -d "$TARGET" ] || die "target not found: $TARGET"
[[ "$NAME" =~ ^[a-z][a-z0-9-]*$ ]] || die "name must be lowercase slug: $NAME"
[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"

case "$PRODUCT" in
  bridge) pack="bridge-connectors"; kind_product="bridge" ;;
  pbms) pack="pbms-connectors"; kind_product="pbms" ;;
  *) die "--product must be bridge or pbms" ;;
esac

stub="$ROOT/packs/$pack/_stub/connector"
[ -d "$stub" ] || die "stub missing: $stub"

dest="$TARGET/$NAME"
[ ! -e "$dest" ] || die "already exists: $dest"

require_cmds python3
manifest_py "$MANIFEST" validate

python3 - <<PY
from pathlib import Path
import sys

sys.path.insert(0, "$ROOT/bootstrap")
from manifest import connector_module, connector_package, derive_vars, load_manifest

data = load_manifest(Path("$MANIFEST"))
vars_ = derive_vars(data)
customer_id = vars_["CUSTOMER_ID"]
product = "$kind_product"
connector_dir = "$NAME"
extra = {
    **vars_,
    "CONNECTOR_DIR": connector_dir,
    "CONNECTOR_MODULE": connector_module(connector_dir, product),
    "CONNECTOR_PACKAGE": connector_package(connector_dir, customer_id, product),
}

stub = Path("$stub")
dest = Path("$dest")

def render(text: str) -> str:
    for k, v in extra.items():
        text = text.replace("{{" + k + "}}", v)
    return text

for src in stub.rglob("*"):
    if src.is_dir():
        continue
    rel = src.relative_to(stub)
    out_parts = [render(p) for p in rel.parts]
    out = dest.joinpath(*out_parts)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(render(src.read_text(encoding="utf-8")), encoding="utf-8")

print(f"Created {dest}")
print(f"  package: {extra['CONNECTOR_PACKAGE']}")
print(f"  module:  {extra['CONNECTOR_MODULE']}")
print()
print("Next:")
print(f"  1. Add '{connector_dir}' to {product}_connectors in the manifest (for future bootstraps)")
print("  2. Update docker/*/Dockerfile COPY/RUN lines if this checkout was already rendered")
print("  3. Commit and push — seeded CI will publish")
PY
