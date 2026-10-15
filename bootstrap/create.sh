#!/usr/bin/env bash
# Create customer destination + extension repos from a manifest.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/render.sh
source "$SCRIPT_DIR/lib/render.sh"
# shellcheck source=lib/pack.sh
source "$SCRIPT_DIR/lib/pack.sh"
# shellcheck source=lib/github.sh
source "$SCRIPT_DIR/lib/github.sh"

DRY_RUN=0
MANIFEST="$ROOT/schema/customer.manifest.yaml"
WORK="${TMPDIR:-/tmp}/openg2p-customer-bundle-$$"
trap 'rm -rf "$WORK"' EXIT

usage() {
  cat <<EOF
Usage: bootstrap/create.sh [options]

Options:
  --manifest PATH   customer.manifest.yaml (default: schema/customer.manifest.yaml)
  --dry-run         print plan only; do not call GitHub API
  -h, --help        show help

Creates private destination repos (helm, versions) and extension repos with
seeded CI, then pushes initial content.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --manifest)
      MANIFEST="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"
require_cmds python3 git

manifest_py "$MANIFEST" validate
PLAN_JSON="$(manifest_py "$MANIFEST" plan)"
mkdir -p "$WORK"
VARS_FILE="$WORK/template.env"
write_template_env "$MANIFEST" "$VARS_FILE"

echo "Bootstrap plan for manifest: $MANIFEST"
echo "$PLAN_JSON" | python3 -m json.tool

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  echo "[dry-run] No GitHub changes made."
  print_secrets_checklist
  exit 0
fi

require_cmd gh
gh auth status >/dev/null 2>&1 || die "gh not authenticated — run: gh auth login"

render_skeleton() {
  local skel="$1"
  local dest="$2"
  render_pack "$skel" "$dest" "$VARS_FILE"
}

# --- destination repos ---
while IFS= read -r line; do
  kind="$(echo "$line" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['kind'])")"
  full_name="$(echo "$line" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['full_name'])")"
  branch="$(echo "$line" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['branch'])")"
  skeleton="$(echo "$line" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['skeleton'])")"
  tmp="$WORK/dest-$kind"
  render_skeleton "$ROOT/$skeleton" "$tmp"
  org="${full_name%%/*}"
  repo="${full_name#*/}"
  echo "Creating destination: $full_name (branch $branch)"
  gh_create_repo "$org" "$repo" private
  gh_push_dir "$tmp" "$full_name" "$branch" "chore: bootstrap destination from openg2p-customer-bundle"
done < <(python3 -c "import json,sys; [print(json.dumps(d)) for d in json.load(sys.stdin)['destinations']]" <<<"$PLAN_JSON")

# --- extension repos ---
while IFS= read -r line; do
  kind="$(echo "$line" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['kind'])")"
  full_name="$(echo "$line" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['full_name'])")"
  branch="$(echo "$line" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['branch'])")"
  pack="$(echo "$line" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['pack'])")"
  pack_dir="$ROOT/$pack"
  [ -d "$pack_dir" ] || die "pack not found: $pack_dir"
  tmp="$WORK/ext-$kind"
  render_extension_pack "$pack_dir" "$tmp" "$VARS_FILE" "$MANIFEST" "$kind"
  write_ci_env "$MANIFEST" "$tmp/.openg2p/ci.env"
  org="${full_name%%/*}"
  repo="${full_name#*/}"
  echo "Creating extension repo: $full_name (branch $branch)"
  gh_create_repo "$org" "$repo" private
  gh_push_dir "$tmp" "$full_name" "$branch" "chore: bootstrap extension from openg2p-customer-bundle"
  gh_set_repo_variables "$full_name" "$tmp/.openg2p/ci.env"
done < <(python3 -c "import json,sys; [print(json.dumps(e)) for e in json.load(sys.stdin)['extensions']]" <<<"$PLAN_JSON")

print_secrets_checklist
echo "Bootstrap complete."
