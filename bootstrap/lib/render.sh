#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

render_placeholders() {
  local content="$1"
  local vars_file="$2"
  local line key val
  while IFS= read -r line || [ -n "$line" ]; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    key="${line%%=*}"
    val="${line#*=}"
    content="${content//\{\{$key\}\}/$val}"
  done <"$vars_file"
  printf '%s' "$content"
}

apply_path_placeholders() {
  local root="$1"
  local vars_file="$2"
  local pass changed=1 path base dir new

  while [ "$changed" -eq 1 ]; do
    changed=0
    while IFS= read -r -d '' path; do
      base="$(basename "$path")"
      dir="$(dirname "$path")"
      new="$(render_placeholders "$base" "$vars_file")"
      if [ "$base" != "$new" ]; then
        mv "$path" "$dir/$new"
        changed=1
      fi
    done < <(find "$root" -depth -name '*{{*' -print0 2>/dev/null || true)
  done
}

render_pack() {
  local src="$1"
  local dest="$2"
  local vars_file="$3"
  local rel out file

  rm -rf "$dest"
  mkdir -p "$dest"

  while IFS= read -r -d '' file; do
    rel="${file#"$src"/}"
    out="$dest/$rel"
    mkdir -p "$(dirname "$out")"
    cp "$file" "$out"
  done < <(find "$src" -type f ! -name 'pack.yaml' ! -path '*/_stub/*' -print0)

  apply_path_placeholders "$dest" "$vars_file"

  while IFS= read -r -d '' file; do
    if file "$file" | grep -qE 'text|empty|ASCII'; then
      render_placeholders "$(cat "$file")" "$vars_file" >"${file}.tmp"
      mv "${file}.tmp" "$file"
    fi
  done < <(find "$dest" -type f -print0)
}

write_ci_env() {
  local manifest="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  python3 "$ROOT/bootstrap/manifest.py" "$manifest" ci-env >"$dest"
}

write_template_env() {
  local manifest="$1"
  local dest="$2"
  python3 "$ROOT/bootstrap/manifest.py" "$manifest" export-env >"$dest"
}
