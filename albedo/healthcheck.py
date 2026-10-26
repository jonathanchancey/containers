import json
import os
import urllib.request
from pathlib import Path

# both listeners bind to loopback; kubelet http probes cannot reach them.
# never include the daemon record or its bearer token in probe output.
try:
    record = json.loads((Path(os.environ["ALBEDO_HOME"]) / "daemon.json").read_text())
    request = urllib.request.Request(
        f"http://127.0.0.1:{record['port']}/server",
        headers={"Authorization": f"Bearer {record['token']}"},
    )
    with urllib.request.urlopen(request, timeout=2) as response:
        if response.status != 200:
            raise RuntimeError("daemon unavailable")
    with urllib.request.urlopen("http://127.0.0.1:4317/", timeout=2) as response:
        if response.status != 200:
            raise RuntimeError("web unavailable")
except Exception:
    raise SystemExit("albedo is not ready") from None
