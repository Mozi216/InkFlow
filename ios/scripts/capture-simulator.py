"""Capture the real SwiftUI app in the iOS simulator. Not a Dynamic Island test."""
import json
import pathlib
import subprocess
import sys
import time

root = pathlib.Path(__file__).resolve().parents[1]
output = root / "build" / "app-preview"
output.mkdir(parents=True, exist_ok=True)

def run(*arguments, **kwargs):
    print("simctl " + " ".join(arguments), flush=True)
    return subprocess.run(["xcrun", "simctl", *arguments], check=True, text=True,
                          timeout=kwargs.pop("timeout", 300), **kwargs)

inventory = json.loads(run("list", "devices", "available", "--json", capture_output=True).stdout)
devices = [d for runtime, entries in inventory["devices"].items() if "iOS-27" in runtime
           for d in entries if "iPhone" in d["name"] and d.get("isAvailable")]
if not devices:
    raise SystemExit("No iOS 27 iPhone simulator is available; visual verification was NOT run")
devices.sort(key=lambda d: ("Pro" not in d["name"], "18" not in d["name"]))
device = devices[0]
if device["state"] != "Booted": run("boot", device["udid"])
if "--boot-only" in sys.argv:
    print("Started simulator boot; compilation can proceed while it finishes.", flush=True)
    raise SystemExit(0)
run("bootstatus", device["udid"], "-b", timeout=480)
run("install", device["udid"], str(root / "build/DerivedData/Build/Products/Debug-iphonesimulator/InkFlow.app"))
for style in ("flow", "columns", "scatter", "collage", "cinema", "mv"):
    run("launch", "--terminate-running-process", device["udid"], "com.inkflow.mobile", "--preview-style", style,
        "--preview-time", "1.65", "--preview-paused")
    time.sleep(2)
    run("io", device["udid"], "screenshot", str(output / f"app-{style}.png"))
    run("launch", "--terminate-running-process", device["udid"], "com.inkflow.mobile", "--scene-check", "--preview-style", style)
    time.sleep(2)
    run("io", device["udid"], "screenshot", str(output / f"shared-scene-{style}.png"))
run("launch", "--terminate-running-process", device["udid"], "com.inkflow.mobile", "--layout-check")
time.sleep(2)
run("io", device["udid"], "screenshot", str(output / "compact-and-connection.png"))
(output / "scope.json").write_text(json.dumps({"surface": "SwiftUI app preview",
    "device": device["name"], "sharedIslandViews": True,
    "dynamicIslandTested": False, "audioSyncTested": False}, indent=2))
