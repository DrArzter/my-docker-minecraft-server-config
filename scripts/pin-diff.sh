#!/usr/bin/env bash
# Print, as Markdown, how the release pins of each modpack profile differ
# between two trees that each hold a profiles/ folder: the modpack file and
# server pack ids, the client mirror, and addons added, removed and changed.
# It reads JSON as data only and needs no network and no secret.
set -Eeuo pipefail

base_root="${1:-}"
head_root="${2:-}"
[[ -d "${base_root}" && -d "${head_root}" ]] || {
  printf 'usage: pin-diff.sh <base-tree> <head-tree>\n' >&2
  exit 2
}

# A JSON file inside the profile, or null when it is absent, unsafe or invalid.
read_json() {
  local directory="$1" relative="$2"
  [[ -n "${relative}" && "${relative}" =~ ^[A-Za-z0-9._/-]+$ && "${relative}" != /* && "${relative}" != *..* ]] ||
    { printf 'null\n'; return; }
  [[ -f "${directory}/${relative}" && ! -L "${directory}/${relative}" ]] || { printf 'null\n'; return; }
  jq -c . "${directory}/${relative}" 2>/dev/null || printf 'null\n'
}

# {"<profile>": {"modpack": {...}|null, "addons": [...]}} for one tree.
pins() {
  local root="$1" directory id profile
  for directory in "${root}"/profiles/*/; do
    directory="${directory%/}"
    id="${directory##*/}"
    [[ "${id}" =~ ^[a-z0-9][a-z0-9-]{0,31}$ ]] || continue
    profile="$(read_json "${directory}" profile.json)"
    [[ "$(jq -r '.mods.resolver? // ""' <<<"${profile}")" == curseforge-modpack ]] || continue
    jq -cn --arg id "${id}" \
      --argjson modpack "$(read_json "${directory}" "$(jq -r '.mods.source // ""' <<<"${profile}")")" \
      --argjson addons "$(read_json "${directory}" "$(jq -r '.mods.addons // ""' <<<"${profile}")")" \
      '{key: $id, value: {modpack: $modpack, addons: (($addons // {}).mods? // [])}}'
  done | jq -cs 'from_entries'
}

jq -rn --argjson base "$(pins "${base_root}")" --argjson head "$(pins "${head_root}")" '
  def cell: if . == null then "–" else tostring | gsub("[`|\r\n]"; " ") | "`" + . + "`" end;
  def mirror: if . == null then null else "\(.sha512 | tostring | .[0:12])… \(.bytes) bytes" end;
  def key: if .curseforge then "curseforge:\(.curseforge.project_id)" else "modrinth:\(.modrinth.project_id)" end;
  def pin:
    (if .curseforge then "CurseForge \(.curseforge.project_id)/\(.curseforge.file_id)" +
        (if .curseforge.mirror then " mirror \(.curseforge.mirror.sha512 | tostring | .[0:12])…" else "" end)
     else "Modrinth \(.modrinth.version_id) \(.modrinth.file) \(.modrinth.sha512 | tostring | .[0:12])…" end) +
    " (\(.side))";
  def addon_map: map(select(type == "object" and (has("curseforge") or has("modrinth"))) | {key: key, value: .}) | from_entries;
  def row($label; $old; $new): if $old == $new then empty else "| \($label) | \($old | cell) | \($new | cell) |" end;

  [($base + $head) | keys[] as $id |
    ($base[$id] // {}) as $b | ($head[$id] // {}) as $h |
    ([row("Modpack file"; $b.modpack.file_id; $h.modpack.file_id),
      row("Server pack file"; $b.modpack.server_pack_file_id; $h.modpack.server_pack_file_id),
      row("Modpack project"; $b.modpack.project_id; $h.modpack.project_id),
      row("Client mirror"; $b.modpack.client_mirror | mirror; $h.modpack.client_mirror | mirror)]) as $pack |
    (($b.addons // []) | addon_map) as $old | (($h.addons // []) | addon_map) as $new |
    ([($old + $new) | keys[] as $k |
      if $old[$k] == null then "| \($new[$k].name | cell) | added | – | \($new[$k] | pin | cell) |"
      elif $new[$k] == null then "| \($old[$k].name | cell) | removed | \($old[$k] | pin | cell) | – |"
      elif $old[$k] != $new[$k] then "| \($new[$k].name | cell) | changed | \($old[$k] | pin | cell) | \($new[$k] | pin | cell) |"
      else empty end]) as $addons |
    select(($pack + $addons) | length > 0) |
    "#### `\($id)`" +
      (if $b == {} then " (new profile)" elif $h == {} then " (profile removed)" else "" end) + "\n" +
      (if ($pack | length) > 0 then "\n| Pin | Base | Head |\n| --- | --- | --- |\n" + ($pack | join("\n")) + "\n" else "" end) +
      (if ($addons | length) > 0 then "\n| Addon | Change | Base | Head |\n| --- | --- | --- | --- |\n" + ($addons | join("\n")) + "\n" else "" end)
  ] as $sections |
  "### Release pin diff\n\n" +
  (if ($sections | length) == 0 then "No modpack or addon pin changes.\n" else ($sections | join("\n")) end)
'
