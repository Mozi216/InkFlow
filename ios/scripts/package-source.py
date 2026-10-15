"""Prepare only source and build inputs; exclude binaries, account files and local logs."""
import hashlib
import pathlib
import zipfile

root = pathlib.Path(__file__).resolve().parents[2]
output = root / "release" / "InkFlow-iOS-source.zip"
output.parent.mkdir(parents=True, exist_ok=True)
extensions = {".swift", ".plist", ".entitlements", ".xcprivacy", ".json", ".svg", ".png", ".py", ".sh", ".ps1", ".mjs", ".md", ".yml"}
excluded = {"build", ".build", "InkFlow.xcodeproj", "__pycache__"}
paths = [p for p in (root / "ios").rglob("*") if p.is_file()
         and (p.suffix in extensions or p.name == ".gitignore")
         and not excluded.intersection(p.relative_to(root / "ios").parts)]
paths.append(root / ".github/workflows/ios.yml")
for name in ("animation.ts", "ambient-motion.ts", "layout.ts", "graphemes.ts", "timing.ts"):
    paths.append(root / "frontend/src/features/lyrics" / name)
with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(paths): archive.write(path, path.relative_to(root).as_posix())
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
    assert ".github/workflows/ios.yml" in archive.namelist()
digest = hashlib.sha256(output.read_bytes()).hexdigest()
print(f"{output}\n{len(paths)} source files, {output.stat().st_size} bytes\nSHA256 {digest}")
