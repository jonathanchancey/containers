# albedo

the [flake](flake.nix) packages the pinned upstream albedo flake with nix's
`dockerTools.buildLayeredImage`. it includes the daemon, terminal and web clients,
python, bash, kubectl, git, curl, and ripgrep. builds need nix, not a docker daemon;
the smoke test needs docker. only amd64 is packaged.

```bash
nix build ./albedo#image
docker load < result
image=$(nix eval --raw ./albedo#image.imageName):$(nix eval --raw ./albedo#image.imageTag)
bash albedo/smoke.sh "$image"
```

the workflow builds and tests pull requests. merges to main publish the tested
archive to ghcr as an oci image using skopeo. make the package public after its
first publication if consumers pull without credentials. images contain no
provider credentials or deployment-specific personality.

## runtime contract

- run as uid/gid 1000 with a writable persistent mount at `/home/albedo` and a
  writable `/tmp`; the remaining root filesystem can be read-only.
- `/home/albedo` is also the workspace. mount instructions at
  `/home/albedo/AGENTS.md` if needed. retain the whole home, including `.albedo`,
  rather than only its sqlite database.
- the web listener is loopback-only on 4317; the authenticated daemon is on 4318.
  use kubectl port-forward for the web client in kubernetes. no network listener
  is published by default. `/bin/albedo-healthcheck` checks both services.
- `albedo web --local --no-open` retrieves the private browser sign-in link.
  the container uses upstream's internal `--serve` mode to stay in the foreground
  without writing that link to logs. verify this contract when updating upstream.
- provider login, recurring work, and optional discord integration are configured
  through albedo after deployment. keep credentials out of image builds.

the upstream client launches its daemon; a failed daemon makes the health check
fail so the orchestrator can restart the container. kubernetes permissions are
enforced by the deployment's service account, not by this image's tools.
startup removes only `daemon.json` and `web.json`, whose process identities are
invalid after container replacement. it preserves storage, locks, and browser
sign-in keys. never share one home between running containers.

## updates

change the upstream revision in `flake.nix`, refresh `albedo/flake.lock` with
`nix flake lock ./albedo`, and increment the image tag. also increment the tag for
packaging-only changes; do not reuse a published tag for different contents.
run the smoke test before updating consumers. the lockfile is independent of
deployment repositories, and albedo is pre-alpha: back up homes before upgrades.
