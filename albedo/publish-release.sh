#!/usr/bin/env bash
set -euo pipefail

metadata="$RUNNER_TEMP/release.json"
authfile="$RUNNER_TEMP/registry-auth.json"
trap 'rm -f "$authfile"' EXIT
image=$(jq -r .image "$metadata")
tag=$(jq -r .tag "$metadata")
printf '%s' "$REGISTRY_PASSWORD" | nix run ./albedo#skopeo -- login \
  --authfile "$authfile" --username "$REGISTRY_USER" --password-stdin ghcr.io
# trust the unsigned local nix archive; registry tls verification stays enabled.
nix run ./albedo#skopeo -- --insecure-policy copy --format oci --authfile "$authfile" \
  --digestfile "$RUNNER_TEMP/image-digest" \
  "docker-archive:$(readlink -f result)" "docker://$image"
jq --arg digest "$(cat "$RUNNER_TEMP/image-digest")" '. + {digest: $digest}' \
  "$metadata" > "$RUNNER_TEMP/release-with-digest.json"
mv "$RUNNER_TEMP/release-with-digest.json" "$metadata"
jq -r '"daily albedo image\n\n- image: `\(.image)@\(.digest)`\n- upstream commit: `\(.upstream_revision)`\n- packaging commit: `\(.packaging_revision)`\n\nthe attached lockfile records the exact build inputs. back up the persistent home before upgrading."' \
  "$metadata" > "$RUNNER_TEMP/release-notes.md"
gh release create "albedo-$tag" --repo "$GITHUB_REPOSITORY" --target "$GITHUB_SHA" \
  --prerelease --title "albedo $tag" --notes-file "$RUNNER_TEMP/release-notes.md" \
  albedo/flake.lock "$metadata"
