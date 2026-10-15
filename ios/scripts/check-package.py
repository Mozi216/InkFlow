"""Check the shipped extension declarations, not just their source plists."""
import json
import pathlib
import plistlib
import sys
import zipfile


def check(ipa):
    with zipfile.ZipFile(ipa) as archive:
        paths = [name for name in archive.namelist()
                 if name.endswith("/Info.plist") and name.count("/") in (2, 4)]
        bundles = {name: plistlib.loads(archive.read(name)) for name in paths}
        names = set(archive.namelist())
    apps = [(name, info) for name, info in bundles.items() if name.count("/") == 2]
    assert len(apps) == 1, "Expected one containing application"
    app_path, app = apps[0]
    parent = app_path.removesuffix("Info.plist")
    app_id = app["CFBundleIdentifier"]
    version = app["CFBundleVersion"]
    if int(version) >= 10:
        for folder in (parent, parent + "PlugIns/InkFlowBroadcast.appex/"):
            assert folder + "fingerprint-runtime.js" in names, "Missing fingerprint runtime"
    assert app.get("NSSupportsLiveActivities") is True
    expected = {
        "InkFlowLiveActivity": ("lyrics", "com.apple.widgetkit-extension"),
        "InkFlowBroadcast": ("broadcast", "com.apple.broadcast-services-upload"),
    }
    for name, (suffix, point) in expected.items():
        path = parent + "PlugIns/" + name + ".appex/Info.plist"
        assert path in bundles, f"Missing extension: {name}"
        info = bundles[path]
        assert info["CFBundleIdentifier"] == app_id + "." + suffix
        assert info["CFBundleVersion"] == version, f"Version mismatch: {name}"
        extension = info["NSExtension"]
        assert extension["NSExtensionPointIdentifier"] == point
        if suffix == "broadcast":
            assert extension.get("RPBroadcastProcessMode") == "RPBroadcastProcessModeSampleBuffer", \
                "RPBroadcastProcessMode must be a direct child of NSExtension"
            principal = extension.get("NSExtensionPrincipalClass", "")
            assert principal.endswith(".SampleHandler") and "$(" not in principal
    return {"build": version, "extensions": list(expected), "broadcastMode": "sample buffers", "result": "passed"}


if __name__ == "__main__":
    print(json.dumps(check(pathlib.Path(sys.argv[1])), indent=2))
