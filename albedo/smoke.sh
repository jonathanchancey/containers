#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: smoke.sh image}
name="albedo-smoke-$$"
volume="$name-home"
cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker volume rm "$volume" >/dev/null 2>&1 || true
}
trap cleanup EXIT
docker volume create "$volume" >/dev/null

start() {
  docker run -d --name "$name" --read-only --cap-drop ALL \
    --security-opt no-new-privileges --network none \
    --memory 2g --tmpfs /tmp:rw,nosuid,nodev,size=256m \
    --mount "type=volume,source=$volume,target=/home/albedo" \
    "$image" >/dev/null
  for _ in $(seq 1 60); do
    if docker exec "$name" /bin/albedo-healthcheck >/dev/null 2>&1; then
      return
    fi
    sleep 2
  done
  docker logs "$name"
  echo 'albedo failed to become ready' >&2
  exit 1
}

start
test "$(docker exec "$name" id -u)" = 1000
docker exec "$name" kubectl version --client >/dev/null
docker exec "$name" bash -c 'test -w "$HOME" && ! touch /readonly-probe 2>/dev/null'
docker exec -i "$name" python3 - <<'PY'
import json
import os
import secrets
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

home = Path(os.environ["ALBEDO_HOME"])
record = json.loads((home / "daemon.json").read_text())
base = f"http://127.0.0.1:{record['port']}"
for url in (base + "/server", "http://127.0.0.1:4317/api/server"):
    try:
        urllib.request.urlopen(url, timeout=5)
    except urllib.error.HTTPError as error:
        assert error.code == 401, error.code
    else:
        raise AssertionError("unauthenticated api access succeeded")
# configure an offline fixture through the public api; never call a real model.
headers = {"Authorization": "Bearer " + record["token"], "Content-Type": "application/json"}
settings = base + "/settings?group=providers"
with urllib.request.urlopen(urllib.request.Request(settings, headers=headers), timeout=5) as response:
    etag = response.headers["ETag"]
profile = {"extension": "openai", "endpoint": "http://127.0.0.1:9/v1", "model": "fixture-model", "protocol": "responses", "api_key": "fixture-key"}
request = urllib.request.Request(
    settings,
    method="PATCH",
    data=json.dumps({"default_profile": "fixture", "profiles": {"fixture": profile}}).encode(),
    headers={**headers, "If-Match": etag, "Content-Type": "application/merge-patch+json"},
)
with urllib.request.urlopen(request, timeout=5) as response:
    assert response.status == 200
bits = (int(time.time() * 1000) << 80) | (7 << 76) | secrets.randbits(76)
session = str(uuid.UUID(int=(bits & ~(3 << 62)) | (2 << 62)))
request = urllib.request.Request(
    base + "/sessions/" + session,
    method="PUT",
    data=json.dumps({"kind": "new", "workspace": "/home/albedo", "name": "image smoke"}).encode(),
    headers={"Authorization": "Bearer " + record["token"], "Content-Type": "application/json", "If-None-Match": "*"},
)
with urllib.request.urlopen(request, timeout=20) as response:
    assert json.load(response)["id"] == session
Path("/home/albedo/smoke-session").write_text(session)
PY

# a replacement container must recover the same session and writable home.
docker rm -f "$name" >/dev/null
start
docker exec -i "$name" python3 - <<'PY'
import json
import os
import urllib.request
from pathlib import Path

record = json.loads((Path(os.environ["ALBEDO_HOME"]) / "daemon.json").read_text())
session = Path("/home/albedo/smoke-session").read_text()
request = urllib.request.Request(
    f"http://127.0.0.1:{record['port']}/sessions/{session}",
    headers={"Authorization": "Bearer " + record["token"]},
)
with urllib.request.urlopen(request, timeout=20) as response:
    assert json.load(response)["id"] == session
PY
echo 'passed: non-root startup, read-only root, tools, api authentication, and session recovery'
