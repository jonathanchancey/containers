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

the workflow builds and tests pull requests using the committed lockfile.
release builds publish tested oci images to ghcr using skopeo. make the package
public after its first publication if consumers pull without credentials.
images contain no provider credentials or deployment-specific personality.

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

the [workflow](../.github/workflows/albedo.yaml) checks upstream `main` daily at
08:23 utc and after packaging merges. unchanged upstream and packaging inputs
skip publication. github may delay scheduled runs.

for an immediate release, open **actions → albedo → run workflow** on `main`.
leave `revision` empty for upstream `main`, or enter a full upstream commit sha.
enable `force` to rebuild unchanged inputs. only successful builds and smoke
tests publish images; a failed run leaves existing releases untouched.

images use `YYYYMMDD.run-number.run-attempt` tags. each github prerelease includes
`release.json` with the image digest and upstream/packaging commits, plus the
exact `flake.lock`. reruns get new tags, never replacing previous images.
if publication succeeds but release creation fails, rerun the workflow to
publish a new tag with its release assets.

to reproduce a release, check out its `packaging_revision` from `release.json`,
replace `albedo/flake.lock` with the release asset, and run the build commands
above. the release workflow overrides the upstream input without changing the
committed pin. to refresh the pr-build baseline, change the revision in
`flake.nix` and run `nix flake lock ./albedo`.

consumer repositories should track the date tags with digest pins and review
deployment updates separately. albedo is pre-alpha: back up persistent homes
before upgrades; reverting an image does not undo database migrations.
