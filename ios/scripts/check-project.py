"""Offline syntax/configuration checks. This does not compile Swift or run XCTest."""
import json
import pathlib
import plistlib
import sys

root = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "tools" / "ios-validation"))
import yaml
import tree_sitter
import tree_sitter_swift

parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
errors = []
files = sorted((root / "ios").rglob("*.swift"))
for path in files:
    source = path.read_bytes()
    tree = parser.parse(source)
    stack = [tree.root_node]
    while stack:
        node = stack.pop()
        if node.type == "ERROR" or node.is_missing:
            row, col = node.start_point
            errors.append(f"{path.relative_to(root)}:{row + 1}:{col + 1}: {node.type}: {source[node.start_byte:node.end_byte][:100]!r}")
        stack.extend(reversed(node.children))

app = plistlib.loads((root / "ios/App/Info.plist").read_bytes())
widget = plistlib.loads((root / "ios/LiveActivity/Info.plist").read_bytes())
privacy = plistlib.loads((root / "ios/App/PrivacyInfo.xcprivacy").read_bytes())
spec = yaml.safe_load((root / "ios/project.yml").read_text())
workflow = yaml.safe_load((root / ".github/workflows/ios.yml").read_text())
assert app["UIBackgroundModes"] == ["screen-capture", "processing"]
assert app["BGTaskSchedulerPermittedIdentifiers"] == ["com.inkflow.mobile.*"]
assert app["NSSupportsLiveActivities"] is True
assert widget["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.widgetkit-extension"
assert privacy["NSPrivacyTracking"] is False
assert workflow["jobs"]["build"]["runs-on"] == "xcode-27"
for target in spec["targets"].values():
    for source in target["sources"]:
        assert (root / "ios" / source["path"]).exists(), source
    assert (root / "ios" / target["settings"]["base"]["INFOPLIST_FILE"]).exists()
scenes = json.loads((root / "ios/InkFlowCore/Tests/InkFlowCoreTests/Fixtures/motion.json").read_text(encoding="utf-8"))
assert len(scenes) == 72
assert {scene["plan"]["style"] for scene in scenes} == {"flow", "columns", "scatter", "collage", "cinema"}

report = {"check": "Swift grammar and project configuration only", "swiftFiles": len(files),
          "referenceScenes": len(scenes), "errors": errors, "xcodeBuild": "not-run", "swiftTests": "not-run",
          "deviceTests": "not-run"}
(root / "artifacts/ios-project-check.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps(report, indent=2))
sys.exit(1 if errors else 0)
