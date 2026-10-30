import json
import os
from pathlib import Path
import subprocess
import tempfile

source = Path(__file__).resolve().parent
revision = "a" * 40
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root / "bin").mkdir()
    (root / "albedo").mkdir()
    (root / ".github/workflows").mkdir(parents=True)
    (root / ".github/workflows/albedo.yaml").write_text("fixture")
    (root / "albedo/flake.lock").write_text(
        json.dumps(
            {
                "nodes": {
                    "root": {"inputs": {"albedo": "albedo"}},
                    "albedo": {"locked": {"rev": revision}},
                }
            }
        )
    )
    subprocess.run(["git", "init", "-q"], cwd=root, check=True)
    subprocess.run(["git", "add", "."], cwd=root, check=True)
    subprocess.run(
        [
            "git",
            "-c",
            "user.name=fixture",
            "-c",
            "user.email=fixture@example.invalid",
            "commit",
            "-qm",
            "fixture",
        ],
        cwd=root,
        check=True,
    )
    (root / "bin/gh").write_text("""#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
  'release list') [[ "${API_FAIL:-false}" != true ]]; printf '%s' "${PREVIOUS_TAG:-}" ;;
  'release download') cp "$PREVIOUS_JSON" "$RUNNER_TEMP/previous-release.json" ;;
  'release create') printf '%s\\n' "$@" > "$RUNNER_TEMP/created" ;;
  *) exit 90 ;;
esac
""")
    (root / "bin/nix").write_text("""#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == flake ]]; then exit 0; fi
if [[ "$*" == *login* ]]; then cat >/dev/null; touch "$RUNNER_TEMP/registry-auth.json"; exit 0; fi
[[ "${COPY_FAIL:-false}" != true ]]
printf 'sha256:fixture' > "$RUNNER_TEMP/image-digest"
""")
    for path in (root / "bin").iterdir():
        path.chmod(0o755)
    env = {
        **os.environ,
        "PATH": str(root / "bin") + ":" + os.environ["PATH"],
        "GITHUB_REPOSITORY": "fixture/containers",
        "GITHUB_SHA": "b" * 40,
        "GITHUB_RUN_NUMBER": "93",
        "GITHUB_RUN_ATTEMPT": "2",
        "UPSTREAM_REVISION": revision,
        "RUNNER_TEMP": str(root),
        "GITHUB_OUTPUT": str(root / "output"),
        "REGISTRY_USER": "fixture",
        "REGISTRY_PASSWORD": "fixture",
    }

    def prepare(**changes):
        (root / "output").unlink(missing_ok=True)
        return subprocess.run(
            ["bash", str(source / "prepare-release.sh")],
            cwd=root,
            env={**env, **changes},
            capture_output=True,
            text=True,
        )

    def check_publish(result, expected):
        assert result.returncode == 0, result.stderr
        assert (
            root / "output"
        ).read_text().strip() == f"publish={str(expected).lower()}"

    check_publish(prepare(), True)
    metadata = json.loads((root / "release.json").read_text())
    assert (
        metadata["tag"].endswith(".93.2") and metadata["upstream_revision"] == revision
    )
    (root / "baseline.json").write_text(json.dumps(metadata))
    previous = {
        "PREVIOUS_TAG": "albedo-20261029.92.1",
        "PREVIOUS_JSON": str(root / "baseline.json"),
    }
    check_publish(prepare(**previous), False)
    check_publish(prepare(**previous, FORCE_RELEASE="true"), True)
    for field in ("upstream_revision", "packaging_hash"):
        (root / "different.json").write_text(
            json.dumps({**metadata, field: "different"})
        )
        check_publish(
            prepare(**{**previous, "PREVIOUS_JSON": str(root / "different.json")}), True
        )
    assert prepare(UPSTREAM_REVISION="main; false").returncode != 0
    assert prepare(API_FAIL="true").returncode != 0
    result = subprocess.run(
        ["bash", str(source / "publish-release.sh")],
        cwd=root,
        env=env,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    published = json.loads((root / "release.json").read_text())
    assert published["digest"] == "sha256:fixture"
    args = (root / "created").read_text().splitlines()
    assert (
        "--prerelease" in args
        and "albedo/flake.lock" in args
        and str(root / "release.json") in args
    )
    assert args[args.index("--target") + 1] == "b" * 40
    assert not (root / "registry-auth.json").exists()
    (root / "created").unlink()
    result = subprocess.run(
        ["bash", str(source / "publish-release.sh")],
        cwd=root,
        env={**env, "COPY_FAIL": "true"},
        capture_output=True,
    )
    assert result.returncode != 0 and not (root / "created").exists()
    assert not (root / "registry-auth.json").exists()
print(
    "passed: new, unchanged, forced, upstream-only, packaging-only, invalid revision, api failure, release assets/digest, copy failure, credential cleanup"
)
