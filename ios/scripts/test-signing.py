import datetime
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import unittest

prepare = pathlib.Path(__file__).with_name("prepare-signing.py")

class SigningTests(unittest.TestCase):
    def run_profiles(self, mutation=None):
        with tempfile.TemporaryDirectory(prefix="inkflow-signing-test-") as directory:
            root = pathlib.Path(directory)
            for name, suffix in (("app", ""), ("widget", ".lyrics")):
                profile = {"TeamIdentifier": ["TEAMTEST01"], "ApplicationIdentifierPrefix": ["PREFIXTEST"],
                    "UUID": f"{name}-test-uuid", "ProvisionedDevices": ["test-device"],
                    "ExpirationDate": datetime.datetime.now() + datetime.timedelta(days=1),
                    "Entitlements": {"application-identifier": "PREFIXTEST.com.example.inkflow" + suffix,
                                     "get-task-allow": False}}
                if mutation: mutation(name, profile)
                (root / f"{name}.plist").write_bytes(plistlib.dumps(profile))
            result = subprocess.run([sys.executable, str(prepare), str(root)], capture_output=True, text=True)
            options = plistlib.loads((root / "ExportOptions.plist").read_bytes()) if result.returncode == 0 else None
            return result, options

    def test_valid_profiles(self):
        result, options = self.run_profiles()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(options["method"], "release-testing")
        self.assertEqual(len(options["provisioningProfiles"]), 2)

    def test_mismatched_team_rejected(self):
        result, _ = self.run_profiles(lambda name, p: p.update(TeamIdentifier=["OTHERTEAM"]) if name == "widget" else None)
        self.assertNotEqual(result.returncode, 0)

    def test_unregistered_phone_rejected(self):
        result, _ = self.run_profiles(lambda name, p: p.update(ProvisionedDevices=["another-device"]) if name == "widget" else None)
        self.assertNotEqual(result.returncode, 0)

    def test_expired_profile_rejected(self):
        result, _ = self.run_profiles(lambda name, p: p.update(ExpirationDate=datetime.datetime(2020, 1, 1)))
        self.assertNotEqual(result.returncode, 0)

if __name__ == "__main__": unittest.main()
