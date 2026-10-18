#!/usr/bin/env bash

# Build the same immutable source snapshot for catalog and release publishing.
# Git history is needed here only; AWS receives data, never executable scripts.
set -Eeuo pipefail

[[ $# == 2 ]] || { printf 'usage: archive-config-source.sh <commit> <output.tar.gz>\n' >&2; exit 2; }
revision="$1"
output="$2"
[[ "${revision}" =~ ^[0-9a-f]{40}$ ]]
[[ "$(git rev-parse --is-shallow-repository)" == false ]] || {
  printf 'error: full Git history is required for profile provenance\n' >&2
  exit 1
}

revisions='{}'
while IFS= read -r path; do
  [[ "${path}" =~ ^profiles/([a-z0-9][a-z0-9-]{0,31})/profile.json$ ]] || continue
  id="${BASH_REMATCH[1]}"
  commit="$(git log -1 --format=%H "${revision}" -- "profiles/${id}/")"
  [[ "${commit}" =~ ^[0-9a-f]{40}$ ]]
  revisions="$(jq -c --arg id "${id}" --arg commit "${commit}" '. + {($id): $commit}' <<<"${revisions}")"
done < <(git ls-tree -r --name-only "${revision}" -- profiles)
[[ "${revisions}" != '{}' ]]

git archive --format=tar.gz --output="${output}" \
  --add-virtual-file="profiles/.source-revisions.json:${revisions}" "${revision}" profiles
