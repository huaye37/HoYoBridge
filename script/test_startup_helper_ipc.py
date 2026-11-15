"""Exercise the exact helper protocol in a disposable per-user launchd service.

This does not install the privileged system service or modify /etc/hosts.
"""
import json
import os
from pathlib import Path
import plistlib
import shutil
import socket
import subprocess
import tempfile
import time

root = Path(tempfile.mkdtemp(prefix="hoyobridge-helper-", dir="/tmp"))
label = "cn.yeutech.HoYoBridge.HelperTest." + root.name
uid = os.getuid()
target = f"gui/{uid}/{label}"
loaded = False
hosts = root / "hosts"
hosts.write_text("127.0.0.1 localhost\n# keep\n")
original = hosts.read_bytes()
endpoint = str(root / "helper.sock")
try:
    subprocess.run([
        "xcrun", "clang", "-Wall", "-Wextra", "-Werror",
        f'-DMGB_HOSTS_PATH="{hosts}"', f'-DMGB_HOSTS_TEMP="{root}/.hosts-XXXXXX"',
        "-DMGB_HOSTS_OWNER=getuid()", "-DMGB_HELPER_EXPECTED_EUID=getuid()",
        "-DMGB_HELPER_TEST_NO_FLUSH", "script/native-window/startup-helper.c", "-o", str(root / "helper")
    ], check=True)
    config = {
        "Label": label, "ProgramArguments": [str(root / "helper"), str(uid)],
        "RunAtLoad": True, "KeepAlive": {"SuccessfulExit": False}, "ThrottleInterval": 1,
        "Sockets": {"Requests": {"SockPathName": endpoint, "SockPathMode": 0o666, "SockType": "stream"}},
    }
    job = root / "job.plist"
    job.write_bytes(plistlib.dumps(config))
    subprocess.run(["/bin/launchctl", "bootstrap", f"gui/{uid}", str(job)], check=True)
    loaded = True
    for _ in range(40):
        if Path(endpoint).exists():
            break
        time.sleep(0.1)

    def request(payload=b"START\n"):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(8)
            client.connect(endpoint)
            client.sendall(payload)
            return client.recv(6)

    assert request() == b"READY\n"
    assert b"# hoyobridge-startup-v1" in hosts.read_bytes()
    subprocess.run(["/bin/launchctl", "kill", "SIGTERM", target], check=True)
    for _ in range(40):
        if hosts.read_bytes() == original:
            break
        time.sleep(0.1)
    assert hosts.read_bytes() == original
    time.sleep(1.2)
    assert request() == b"READY\n"
    time.sleep(16)
    assert hosts.read_bytes() == original
    assert request(b"NOOP!\n") == b""
    assert hosts.read_bytes() == original
    print("PASS: launchd activation, reuse without reinstall, TERM/15-second restoration, invalid request rejection")
    Path("/tmp/hoyobridge-helper-ipc-result.json").write_text(json.dumps({
        "socketActivation": True, "repeatInvocation": True, "signalRestoration": True,
        "timedRestoration": True, "invalidRequestRejected": True, "systemHostsModified": False,
    }))
finally:
    if loaded:
        subprocess.run(["/bin/launchctl", "bootout", target], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    shutil.rmtree(root)
