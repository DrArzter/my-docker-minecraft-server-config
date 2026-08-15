#!/usr/bin/env bash

set -Eeuo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
schema="${repository_root}/profiles/schema.json"

for command in docker jq; do
  command -v "${command}" >/dev/null 2>&1 || {
    printf 'error: required command not found: %s\n' "${command}" >&2
    exit 1
  }
done

declare -A seen_ids=()
profile_count=0

while IFS= read -r profile; do
  profile_directory="$(dirname -- "${profile}")"
  profile_id="$(jq -er '.id' "${profile}")"
  directory_id="$(basename -- "${profile_directory}")"

  jq -e --slurpfile schema "${schema}" '
    .schema_version == $schema[0].properties.schema_version.const
    and (.id | test($schema[0].properties.id.pattern))
    and (.display_name | type == "string" and length > 0)
    and (.gameplay == "modded" or .gameplay == "vanilla-like")
    and (.loader.type == "vanilla" or .loader.type == "forge" or .loader.type == "neoforge" or .loader.type == "fabric" or .loader.type == "quilt")
    and .compose_file == "compose.yaml"
  ' "${profile}" >/dev/null

  [[ "${profile_id}" == "${directory_id}" ]] || {
    printf 'error: profile id %s must match directory %s\n' "${profile_id}" "${directory_id}" >&2
    exit 1
  }
  [[ -z "${seen_ids[${profile_id}]:-}" ]] || {
    printf 'error: duplicate profile id: %s\n' "${profile_id}" >&2
    exit 1
  }
  seen_ids["${profile_id}"]=1

  compose_file="${profile_directory}/$(jq -r '.compose_file' "${profile}")"
  [[ -f "${compose_file}" ]] || {
    printf 'error: missing Compose file for %s\n' "${profile_id}" >&2
    exit 1
  }

  mods_source="$(jq -r '.mods.source // empty' "${profile}")"
  if [[ -n "${mods_source}" ]]; then
    [[ -f "${profile_directory}/${mods_source}" ]] || {
      printf 'error: missing mod source for %s: %s\n' "${profile_id}" "${mods_source}" >&2
      exit 1
    }
  fi

  rendered="$({
    CF_API_KEY=validation-only RCON_PASSWORD=validation-only \
      docker compose \
        --project-directory "${profile_directory}" \
        -f "${compose_file}" \
        config --format json
  })"
  minecraft_version="$(jq -r '.minecraft_version' "${profile}")"
  loader_type="$(jq -r '.loader.type | ascii_upcase' "${profile}")"
  loader_version="$(jq -r '.loader.version // empty' "${profile}")"
  expected_data_directory="$(realpath -m -- "${profile_directory}/data")"

  jq -e \
    --arg minecraft_version "${minecraft_version}" \
    --arg loader_type "${loader_type}" \
    --arg expected_data_directory "${expected_data_directory}" '
      .services.mc.environment.VERSION == $minecraft_version
      and .services.mc.environment.TYPE == $loader_type
      and any(.services.mc.volumes[]; .target == "/data" and .source == $expected_data_directory)
    ' <<<"${rendered}" >/dev/null

  if [[ "${loader_type}" == "FORGE" && -n "${loader_version}" ]]; then
    jq -e --arg loader_version "${loader_version}" \
      '.services.mc.environment.FORGE_VERSION == $loader_version' \
      <<<"${rendered}" >/dev/null
  fi

  if [[ -n "${mods_source}" ]]; then
    jq -e --arg expected_mod_source "@/${mods_source}" '
      .services.mc.environment.CURSEFORGE_FILES == $expected_mod_source
      and any(.services.mc.volumes[]; .target == "/extras" and .read_only == true)
    ' <<<"${rendered}" >/dev/null
  else
    jq -e '.services.mc.environment | has("CURSEFORGE_FILES") | not' \
      <<<"${rendered}" >/dev/null
  fi

  printf 'profile=%s result=valid\n' "${profile_id}"
  profile_count=$((profile_count + 1))
done < <(find "${repository_root}/profiles" -mindepth 2 -maxdepth 2 -name profile.json -type f | sort)

(( profile_count > 0 )) || {
  printf 'error: no profiles found\n' >&2
  exit 1
}

printf 'result=passed profiles=%d\n' "${profile_count}"
