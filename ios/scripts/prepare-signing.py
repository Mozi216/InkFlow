"""Validate supplied ad-hoc profiles without logging credentials or device IDs."""
import datetime
import pathlib
import plistlib
import re
import shlex
import sys

root = pathlib.Path(sys.argv[1])
profiles = [plistlib.loads((root / f"{name}.plist").read_bytes()) for name in ("app", "widget", "broadcast")]
team = profiles[0]["TeamIdentifier"][0]
ids = []
for profile in profiles:
    if profile["TeamIdentifier"][0] != team:
        raise SystemExit("All three profiles must use the same team")
    if profile["ExpirationDate"] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
        raise SystemExit("Provisioning profile expired")
    if not profile.get("ProvisionedDevices") or profile["Entitlements"].get("get-task-allow"):
        raise SystemExit("Use ad-hoc distribution profiles containing the test iPhone, for all targets")
    identifier = profile["Entitlements"]["application-identifier"]
    prefix = profile["ApplicationIdentifierPrefix"][0] + "."
    if not identifier.startswith(prefix):
        raise SystemExit("Unexpected application identifier prefix")
    bundle = identifier[len(prefix):]
    if not re.fullmatch(r"[A-Za-z0-9.-]+", bundle) or "*" in bundle:
        raise SystemExit("Use explicit app identifiers")
    ids.append(bundle)
if ids[1] != ids[0] + ".lyrics":
    raise SystemExit("Widget identifier must equal the app identifier followed by .lyrics")
if ids[2] != ids[0] + ".broadcast":
    raise SystemExit("Broadcast identifier must equal the app identifier followed by .broadcast")
if not set.intersection(*(set(profile["ProvisionedDevices"]) for profile in profiles)):
    raise SystemExit("All profiles must contain the same test iPhone")
group = "group." + ids[0]
for index in (0, 2):
    if group not in profiles[index]["Entitlements"].get("com.apple.security.application-groups", []):
        raise SystemExit("App and broadcast profiles must share the group.<app bundle ID> App Group")
if profiles[0]["Entitlements"].get("aps-environment") != "production":
    raise SystemExit("The distribution app profile must include production Push Notifications")

values = {"DEVELOPMENT_TEAM": team, "INKFLOW_BUNDLE_ID": ids[0],
          "APP_PROFILE_UUID": profiles[0]["UUID"], "WIDGET_PROFILE_UUID": profiles[1]["UUID"],
          "BROADCAST_PROFILE_UUID": profiles[2]["UUID"]}
values["INKFLOW_RELAY_GROUP"] = group
(root / "build.env").write_text("\n".join(f"{k}={shlex.quote(v)}" for k, v in values.items()) + "\n")
export = {"method": "release-testing", "teamID": team, "signingStyle": "manual",
          "signingCertificate": "Apple Distribution", "stripSwiftSymbols": True,
          "provisioningProfiles": dict(zip(ids, [p["UUID"] for p in profiles]))}
(root / "ExportOptions.plist").write_bytes(plistlib.dumps(export))
print("All three distribution profiles passed validation")
