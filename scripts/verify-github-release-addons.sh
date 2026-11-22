#!/usr/bin/env bash
# Checks every github_release addon pin (ADR-0079 in Spawnpoint) against
# GitHub: the repository is allow-listed, the release is immutable, the asset
# matches the pinned size and digests, and its build provenance attestation
# names the pinned workflow, tag and commit. Reads the profile files as data.

set -Eeuo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# Keep in step with GITHUB_RELEASE_REPOSITORIES in Spawnpoint.
allowed_repositories="${ALLOWED_REPOSITORIES:-DrArzter/SophisticatedBackpacks}"

for command in gh jq sha256sum sha512sum; do
  command -v "${command}" >/dev/null 2>&1 || {
    printf 'error: required command not found: %s\n' "${command}" >&2
    exit 1
  }
done

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

fail() {
  printf 'error: %s: %s\n' "${pin_name}" "$1" >&2
  exit 1
}

pin_count=0
while IFS= read -r addons; do
  while IFS= read -r pin; do
    pin_name="$(jq -r '.name' <<<"${pin}")"
    repository="$(jq -r '.github_release.repository' <<<"${pin}")"
    tag="$(jq -r '.github_release.tag' <<<"${pin}")"
    asset="$(jq -r '.github_release.asset' <<<"${pin}")"
    commit="$(jq -r '.github_release.commit' <<<"${pin}")"
    sha512="$(jq -r '.github_release.sha512' <<<"${pin}")"
    bytes="$(jq -r '.github_release.bytes' <<<"${pin}")"
    workflow="$(jq -r '.github_release.workflow' <<<"${pin}")"

    [[ " ${allowed_repositories} " == *" ${repository} "* ]] ||
      fail "repository ${repository} is not allow-listed"

    release="$(gh api "repos/${repository}/releases/tags/${tag}")" ||
      fail "release ${tag} not found in ${repository}"
    jq -e '.immutable == true and .draft == false and .prerelease == false' <<<"${release}" >/dev/null ||
      fail "release ${tag} must be published, immutable and not a prerelease"
    asset_record="$(jq -c --arg asset "${asset}" '[.assets[] | select(.name == $asset)] | first // empty' <<<"${release}")"
    [[ -n "${asset_record}" ]] || fail "release ${tag} has no asset ${asset}"
    [[ "$(jq -r '.size' <<<"${asset_record}")" == "${bytes}" ]] ||
      fail "asset size differs from the pinned ${bytes} bytes"

    download="${work}/${pin_count}"
    mkdir -p -- "${download}"
    gh release download "${tag}" --repo "${repository}" --pattern "${asset}" --dir "${download}"
    file="${download}/${asset}"

    [[ "$(wc -c <"${file}" | tr -d " ")" == "${bytes}" ]] || fail "downloaded size differs from the pin"
    [[ "$(sha512sum -- "${file}" | cut -d' ' -f1)" == "${sha512}" ]] || fail "SHA-512 differs from the pin"
    [[ "$(jq -r '.digest' <<<"${asset_record}")" == "sha256:$(sha256sum -- "${file}" | cut -d' ' -f1)" ]] ||
      fail "SHA-256 differs from the release asset digest"

    gh attestation verify "${file}" \
      --repo "${repository}" \
      --signer-workflow "${repository}/${workflow}" \
      --source-ref "refs/tags/${tag}" \
      --source-digest "${commit}" \
      --deny-self-hosted-runners >/dev/null ||
      fail "build provenance does not match ${workflow} at ${tag} (${commit})"

    printf 'addon=%s repository=%s tag=%s result=verified\n' "${pin_name}" "${repository}" "${tag}"
    pin_count=$((pin_count + 1))
  done < <(jq -c '.mods[] | select(has("github_release"))' "${addons}")
done < <(find "${repository_root}/profiles" -path '*/extras/addons.json' -type f | sort)

printf 'result=passed github_release_pins=%d\n' "${pin_count}"
