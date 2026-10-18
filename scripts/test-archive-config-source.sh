#!/usr/bin/env bash
set -Eeuo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
fixture="$(mktemp -d /tmp/spawnpoint-source-history.XXXXXXXX)"
trap 'rm -rf -- "${fixture}"' EXIT
git -C "${fixture}" init --quiet
git -C "${fixture}" config user.name Test
git -C "${fixture}" config user.email test@example.invalid
mkdir -p -- "${fixture}/profiles/first" "${fixture}/profiles/second"
printf '{}\n' >"${fixture}/profiles/first/profile.json"
printf '{}\n' >"${fixture}/profiles/second/profile.json"
git -C "${fixture}" add profiles
git -C "${fixture}" commit --quiet -m initial
first="$(git -C "${fixture}" rev-parse HEAD)"
printf 'changed\n' >"${fixture}/profiles/second/options.txt"
git -C "${fixture}" add profiles
git -C "${fixture}" commit --quiet -m second
second="$(git -C "${fixture}" rev-parse HEAD)"
git -C "${fixture}" commit --quiet --allow-empty -m unrelated
head="$(git -C "${fixture}" rev-parse HEAD)"
cd -- "${fixture}"
bash "${script_directory}/archive-config-source.sh" "${head}" "${fixture}/one.tar.gz"
bash "${script_directory}/archive-config-source.sh" "${head}" "${fixture}/two.tar.gz"
cmp "${fixture}/one.tar.gz" "${fixture}/two.tar.gz"
tar -xOzf "${fixture}/one.tar.gz" profiles/.source-revisions.json |
  jq -e --arg first "${first}" --arg second "${second}" '. == {first: $first, second: $second}' >/dev/null
# Selecting an older snapshot must not leak later path history into it.
bash "${script_directory}/archive-config-source.sh" "${first}" "${fixture}/old.tar.gz"
tar -xOzf "${fixture}/old.tar.gz" profiles/.source-revisions.json |
  jq -e --arg first "${first}" '. == {first: $first, second: $first}' >/dev/null
printf 'result=passed\n'
