#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

gh_repo_exists() {
  local full_name="$1"
  gh repo view "$full_name" >/dev/null 2>&1
}

gh_create_repo() {
  local org="$1"
  local name="$2"
  local visibility="${3:-private}"
  if gh_repo_exists "$org/$name"; then
    echo "repo exists: $org/$name"
    return 0
  fi
  if ! gh repo create "$org/$name" --"$visibility" --description "Bootstrapped by openg2p-customer-bundle" >/dev/null; then
    echo "error: failed to create repo: $org/$name" >&2
    return 1
  fi
  echo "created: $org/$name"
}

gh_push_dir() {
  local dir="$1"
  local full_name="$2"
  local branch="$3"
  local message="${4:-Initial commit from openg2p-customer-bundle}"

  (
    cd "$dir"
    if [ ! -d .git ]; then
      git init -b "$branch"
      git add .
      git -c user.email="${GIT_AUTHOR_EMAIL:-bootstrap@openg2p.org}" \
        -c user.name="${GIT_AUTHOR_NAME:-openg2p-customer-bundle}" \
        commit -m "$message"
      git remote add origin "https://github.com/$full_name.git"
      git push -u origin "$branch"
    else
      git add .
      git commit -m "$message" || true
      git push origin "$branch"
    fi
  )
}

gh_set_repo_variables() {
  local full_name="$1"
  local vars_file="$2"
  local key value
  while IFS='=' read -r key value || [ -n "${key:-}" ]; do
    [[ -z "${key:-}" || "$key" =~ ^# ]] && continue
    echo "  set variable $key on $full_name"
    gh variable set "$key" --repo "$full_name" --body "$value"
  done <"$vars_file"
}

print_secrets_checklist() {
  cat <<'EOF'

--- Org / repo secrets checklist (set manually in GitHub) ---

Required for extension-repo CI (seeded by this bundle):
  OPENG2P_BOT_GITHUB_PAT   — push to {customer}-helm and {customer}-versions
                             (classic PAT or fine-grained with Contents: write
                              on helm + versions repos)
  GITHUB_TOKEN             — provided by Actions for GHCR (packages: write)

If using Docker Hub instead of GHCR:
  docker_hub_actor
  docker_hub_token

Optional:
  OPENROUTER_API_KEY       — AI changelog summaries

Per extension repo (Settings → Actions → General):
  - "Allow all actions and reusable workflows"
  - Workflow permissions: Read and write (if packaging needs it)

Org settings:
  - Packages / GHCR: allow workflow tokens to publish packages for the org

After first push, verify:
  1. Actions run succeeded on the extension repo
  2. Image(s) appear under the org Packages / GHCR
  3. .tgz + updated index.yaml landed in {customer}-helm
  4. Changelog folder landed in {customer}-versions/<extension-repo>/

EOF
}
