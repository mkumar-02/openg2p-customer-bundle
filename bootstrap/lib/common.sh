#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export ROOT

die() {
  echo "error: $*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
}

require_cmds() {
  local cmd
  for cmd in "$@"; do
    require_cmd "$cmd"
  done
}

manifest_py() {
  python3 "$ROOT/bootstrap/manifest.py" "$@"
}

load_vars() {
  local manifest="$1"
  MANIFEST="$manifest"
  VARS_JSON="$(manifest_py "$manifest" vars)"
  export MANIFEST VARS_JSON
}

var() {
  python3 -c "import json,sys; print(json.load(sys.stdin)['$1'])" <<<"$VARS_JSON"
}
