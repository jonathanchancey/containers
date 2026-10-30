#!/usr/bin/env bash
set -euo pipefail

upstream=https://tangled.org/okami.mom/albedo
revision=${UPSTREAM_REVISION:-}
if [[ -z "$revision" ]]; then
  revision=$(git ls-remote "$upstream" refs/heads/main | cut -f1)
fi
if [[ ! "$revision" =~ ^[0-9a-f]{40}$ ]]; then
  echo 'expected a full upstream commit sha' >&2
  exit 1
fi

# unrelated repository commits do not require an image rebuild.
packaging=$(git ls-tree HEAD albedo .github/workflows/albedo.yaml | sha256sum | cut -d' ' -f1)
previous=$(gh release list --repo "$GITHUB_REPOSITORY" --limit 100 \
  --json tagName,isDraft --jq '[.[] | select(.isDraft | not) | select(.tagName | startswith("albedo-"))][0].tagName // empty')
if [[ -n "$previous" && "${FORCE_RELEASE:-false}" != true ]]; then
  gh release download "$previous" --repo "$GITHUB_REPOSITORY" \
    --pattern release.json --output "$RUNNER_TEMP/previous-release.json"
  if jq -e --arg revision "$revision" --arg packaging "$packaging" \
    '.upstream_revision == $revision and .packaging_hash == $packaging' \
    "$RUNNER_TEMP/previous-release.json" >/dev/null; then
    echo 'upstream and packaging unchanged; skipping release'
    echo 'publish=false' >> "$GITHUB_OUTPUT"
    exit 0
  fi
fi

# preserve the committed pin for pr builds; retain the resolved release lock as an asset.
nix flake lock ./albedo --override-input albedo "git+$upstream?rev=$revision"
resolved=$(jq -r '.nodes[.nodes.root.inputs.albedo].locked.rev' albedo/flake.lock)
test "$resolved" = "$revision"
tag="$(date -u +%Y%m%d).${GITHUB_RUN_NUMBER}.${GITHUB_RUN_ATTEMPT}"
jq -n --arg tag "$tag" --arg revision "$revision" --arg packaging "$packaging" \
  --arg commit "$GITHUB_SHA" \
  '{tag: $tag, upstream_revision: $revision, packaging_hash: $packaging, packaging_revision: $commit,
    image: ("ghcr.io/jonathanchancey/albedo:" + $tag)}' > "$RUNNER_TEMP/release.json"
echo 'publish=true' >> "$GITHUB_OUTPUT"
