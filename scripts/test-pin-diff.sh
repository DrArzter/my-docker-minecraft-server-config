#!/usr/bin/env bash
# Markdown backticks in the expected lines are intentionally literal.
# shellcheck disable=SC2016
set -Eeuo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
fixture="$(mktemp -d /tmp/spawnpoint-pin-diff.XXXXXXXX)"
trap 'rm -rf -- "${fixture}"' EXIT

fail() {
  printf 'FAIL: %s\n%s\n' "$1" "${output:-}" >&2
  exit 1
}
expect_line() {
  grep -Fxq -- "$1" <<<"${output}" || fail "missing line: $1"
}

sha_a="$(printf 'a%.0s' {1..128})"
sha_b="$(printf 'b%.0s' {1..128})"
profile() {
  local root="$1" id="$2"
  mkdir -p -- "${root}/profiles/${id}/extras"
  printf '{"schema_version":1,"id":"%s","mods":{"source":"extras/pack.json","resolver":"curseforge-modpack","addons":"extras/addons.json"}}\n' \
    "${id}" >"${root}/profiles/${id}/profile.json"
}
pack() {
  local file="$1" file_id="$2" server_id="$3" sha="$4"
  jq -n --argjson file "${file_id}" --argjson server "${server_id}" --arg sha "${sha}" \
    '{schema_version:1,project_id:466901,file_id:$file,server_pack_file_id:$server,
      client_mirror:{url:"https://cdn.modrinth.invalid/pack.mrpack",sha512:$sha,bytes:100}}' >"${file}"
}
modrinth() {
  jq -n --arg name "$1" --arg project "$2" --arg version "$3" --arg sha "$4" \
    '{name:$name,side:"both",modrinth:{project_id:$project,version_id:$version,file:"\($name).jar",sha512:$sha,bytes:10}}'
}

profile "${fixture}/base" prominence
pack "${fixture}/base/profiles/prominence/extras/pack.json" 9184727 9184730 "${sha_a}"
jq -n --argjson kept "$(modrinth Backpacks ouNrBQtq Jk6o7s4h "${sha_a}")" \
  --argjson gone "$(modrinth Core 9jxwkYQL BP3CQI2v "${sha_a}")" \
  '{schema_version:1,mods:[$kept,$gone]}' >"${fixture}/base/profiles/prominence/extras/addons.json"
# A curseforge-files profile has no release pins to compare.
mkdir -p "${fixture}/base/profiles/main"
printf '{"schema_version":1,"id":"main","mods":{"source":"extras/cf-mods.txt"}}\n' >"${fixture}/base/profiles/main/profile.json"

cp -R -- "${fixture}/base" "${fixture}/same"
output="$(bash "${script_directory}/pin-diff.sh" "${fixture}/base" "${fixture}/same")"
expect_line 'No modpack or addon pin changes.'

cp -R -- "${fixture}/base" "${fixture}/head"
pack "${fixture}/head/profiles/prominence/extras/pack.json" 9200000 9200001 "${sha_b}"
jq -n --argjson bumped "$(modrinth Backpacks ouNrBQtq Zz9y8x7W "${sha_b}")" \
  '{schema_version:1,mods:[$bumped,
    {name:"Pipe | name",side:"server",curseforge:{project_id:123,file_id:456}}]}' \
  >"${fixture}/head/profiles/prominence/extras/addons.json"
profile "${fixture}/head" fresh
pack "${fixture}/head/profiles/fresh/extras/pack.json" 1 2 "${sha_a}"
printf 'not json\n' >"${fixture}/head/profiles/fresh/extras/addons.json"
# A source path that leaves the profile is never read.
profile "${fixture}/head" escape
jq '.mods.source = "../../../etc/passwd"' "${fixture}/head/profiles/escape/profile.json" >"${fixture}/escape.json"
mv -- "${fixture}/escape.json" "${fixture}/head/profiles/escape/profile.json"
printf '{"schema_version":1,"mods":[]}\n' >"${fixture}/head/profiles/escape/extras/addons.json"

output="$(bash "${script_directory}/pin-diff.sh" "${fixture}/base" "${fixture}/head")"
expect_line '### Release pin diff'
expect_line '#### `prominence`'
expect_line '| Modpack file | `9184727` | `9200000` |'
expect_line '| Server pack file | `9184730` | `9200001` |'
expect_line '| Client mirror | `aaaaaaaaaaaa… 100 bytes` | `bbbbbbbbbbbb… 100 bytes` |'
expect_line '| `Backpacks` | changed | `Modrinth Jk6o7s4h Backpacks.jar aaaaaaaaaaaa… (both)` | `Modrinth Zz9y8x7W Backpacks.jar bbbbbbbbbbbb… (both)` |'
expect_line '| `Core` | removed | `Modrinth BP3CQI2v Core.jar aaaaaaaaaaaa… (both)` | – |'
expect_line '| `Pipe   name` | added | – | `CurseForge 123/456 (server)` |'
expect_line '#### `fresh` (new profile)'
expect_line '| Modpack file | – | `1` |'
[[ "$(grep -c 'Modpack project' <<<"${output}")" == 1 ]] || fail "an unchanged pin is listed"
! grep -q 'main' <<<"${output}" || fail "a curseforge-files profile is listed"
! grep -q 'escape' <<<"${output}" || fail "a profile with an unsafe source path has pins"

output="$(bash "${script_directory}/pin-diff.sh" "${fixture}/head" "${fixture}/base")"
expect_line '#### `fresh` (profile removed)'
printf 'result=passed\n'
