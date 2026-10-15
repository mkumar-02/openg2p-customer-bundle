#!/usr/bin/env bash
# Update GitHub Actions variables on existing extension repos from a manifest.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/github.sh
source "$SCRIPT_DIR/lib/github.sh"

MANIFEST="$ROOT/schema/customer.manifest.yaml"
DRY_RUN=0

usage() {
  cat <<EOF
Usage: bootstrap/update-vars.sh [options]

Options:
  --manifest PATH   customer.manifest.yaml (default: schema/customer.manifest.yaml)
  --dry-run         print repos/vars only; do not call GitHub API
  -h, --help        show help

Recomputes .openg2p/ci.env from the manifest and sets GitHub Actions variables
on each enabled extension repo.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --manifest) MANIFEST="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"
require_cmds python3

manifest_py "$MANIFEST" validate
PLAN_JSON="$(manifest_py "$MANIFEST" plan)"
CI_ENV="$(manifest_py "$MANIFEST" ci-env)"

echo "Variables to set:"
echo "$CI_ENV"

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  echo "[dry-run] Would update variables on:"
  python3 -c "import json,sys; [print(' -', e['full_name']) for e in json.load(sys.stdin)['extensions']]" <<<"$PLAN_JSON"
  exit 0
fi

require_cmd gh
gh auth status >/dev/null 2>&1 || die "gh not authenticated — run: gh auth login"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
printf '%s' "$CI_ENV" >"$TMP"

while IFS= read -r full_name; do
  echo "Updating variables: $full_name"
  gh_set_repo_variables "$full_name" "$TMP"
done < <(python3 -c "import json,sys; [print(e['full_name']) for e in json.load(sys.stdin)['extensions']]" <<<"$PLAN_JSON")

echo "update-vars complete."
