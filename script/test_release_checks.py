"""Fixture tests only. No credentials, Apple network calls, installation or real signing."""
from pathlib import Path
import json
import os
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import release_checks as checks

TEAM = "ABCDEFGHIJ"
IDENTIFIER = "8bc36b9a-08c8-4d24-8f15-3e9e95c8e880"
SIGNATURE = """Authority=Developer ID Application: Fixture (ABCDEFGHIJ)
Authority=Developer ID Certification Authority
TeamIdentifier=ABCDEFGHIJ
Timestamp=Sep 13, 2026 at 1:00:00 PM
CodeDirectory v=20500 size=123 flags=0x10000(runtime) hashes=2+7 location=embedded
"""


class ReleaseChecksTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="beacon-release-fixture-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.dmg = self.root / "Fixture.dmg"
        self.dmg.write_bytes(b"not a real disk image: injected boundary test")
        self.output = self.root / "evidence.json"
        self.calls = []
        self.fail = None
        self.entitlements = {"com.apple.security.device.bluetooth": True}
        self.signature = SIGNATURE
        self.policy = "assessments enabled"
        self.assessment = "accepted\nsource=Notarized Developer ID\n"
        self.mutate_image = False
        self.no_app = False

    def make_app(self, path):
        (path / "Contents/MacOS").mkdir(parents=True)
        (path / "Contents/MacOS/BeaconMac").write_bytes(b"fixture, never executed")
        (path / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.isaacyslin.Beacon.mac", "CFBundleVersion": "123",
            "CFBundleShortVersionString": "1.0", "CFBundleExecutable": "BeaconMac",
            "BeaconSourceCommit": "a" * 40}))
        return path

    def fake_run(self, command):
        self.calls.append(command)
        if self.fail and self.fail(command):
            raise checks.VerificationError("Injected Apple command failure")
        data = b""
        if command[:2] == ["/usr/sbin/spctl", "--status"]:
            data = self.policy.encode()
        elif "--entitlements" in command:
            data = plistlib.dumps(self.entitlements)
        elif "--display" in command:
            data = self.signature.encode()
        elif "attach" in command and not self.no_app:
            self.make_app(Path(command[-1]) / "BeaconMac.app")
        elif "--type" in command and "execute" in command:
            data = self.assessment.encode()
        elif "detach" in command and self.mutate_image:
            self.dmg.write_bytes(b"changed fixture")
        return subprocess.CompletedProcess(command, 0, stdout=data, stderr=b"")

    def verify(self):
        with patch.object(checks.platform, "system", return_value="Darwin"), \
             patch.object(checks.platform, "mac_ver", return_value=("fixture-macOS", "", "")), \
             patch.object(checks, "run", side_effect=self.fake_run):
            return checks.verify_artifact(self.dmg, TEAM, self.output)

    def testLocalAdHocDoesNotRequireDistributionCredentials(self):
        checks.preflight({})
        checks.preflight({"NOTARIZE": "0", "CONFIGURATION": "Debug"})

    def testFormalPreflightRejectsIncompleteCredentialsWithoutPrintingSecrets(self):
        good = {"NOTARIZE": "1", "CONFIGURATION": "Release", "DEVELOPER_ID_IDENTITY": "Fixture identity",
                "EXPECTED_TEAM_ID": TEAM, "NOTARY_PROFILE": "fixture-profile"}
        checks.preflight(good)
        for field in ("DEVELOPER_ID_IDENTITY", "EXPECTED_TEAM_ID", "NOTARY_PROFILE"):
            bad = dict(good); del bad[field]
            with self.subTest(field=field), self.assertRaises(checks.VerificationError):
                checks.preflight(bad)
        for change in ({"NOTARIZE": "yes"}, {"CONFIGURATION": "Debug"}, {"EXPECTED_TEAM_ID": "wrong"},
                       {"DEVELOPER_ID_IDENTITY": "-"}):
            with self.subTest(change=change), self.assertRaises(checks.VerificationError):
                checks.preflight(good | change)
        fallback = dict(good); del fallback["NOTARY_PROFILE"]
        fallback.update(APPLE_ID="fixture@example.invalid", APPLE_APP_PASSWORD="SENSITIVE_FIXTURE", TEAM_ID=TEAM)
        checks.preflight(fallback)
        del fallback["APPLE_ID"]
        try:
            checks.preflight(fallback)
            self.fail("Incomplete credentials accepted")
        except checks.VerificationError as error:
            self.assertNotIn("SENSITIVE_FIXTURE", str(error))

    def testAppleAcceptedResultRequiresValidSubmissionAndExactStatus(self):
        result = self.root / "notary.json"
        for value in ({"id": IDENTIFIER, "status": "Invalid"}, {"id": IDENTIFIER, "status": "In Progress"},
                      {"id": IDENTIFIER}, {"status": "Accepted"}, {"id": "invented", "status": "Accepted"}, [], None):
            result.write_text(json.dumps(value))
            with self.subTest(value=value), self.assertRaises(checks.VerificationError):
                checks.accepted_notary_result(result)
        result.write_text(json.dumps({"id": IDENTIFIER, "status": "Accepted"}))
        self.assertEqual(checks.accepted_notary_result(result), IDENTIFIER)
        result.write_text(json.dumps({"id": IDENTIFIER, "status": "Invalid"}))
        self.assertEqual(checks.notary_result(result)["id"], IDENTIFIER)  # Retain log even on rejection.

    def testCertificateTeamTimestampAndHardenedRuntimeAreIndependentRequirements(self):
        checks.signature_details(SIGNATURE, TEAM, app=True)
        for bad in (SIGNATURE.replace("Developer ID Application:", "Apple Development:"),
                    SIGNATURE.replace(TEAM, "KLMNOPQRST"), SIGNATURE.replace("Timestamp=", "Signed Time="),
                    SIGNATURE.replace("Timestamp=Sep 13, 2026 at 1:00:00 PM", "Timestamp=none"),
                    SIGNATURE.replace("(runtime)", "(adhoc)")):
            with self.subTest(bad=bad), self.assertRaises(checks.VerificationError):
                checks.signature_details(bad, TEAM, app=True)

    def testDebugEntitlementsAndUntraceableMetadataAreRejected(self):
        app = self.make_app(self.root / "BeaconMac.app")
        with patch.object(checks, "run", side_effect=self.fake_run):
            self.entitlements["com.apple.security.get-task-allow"] = True
            with self.assertRaises(checks.VerificationError): checks.check_signature(app, TEAM)
            self.entitlements = {"com.apple.security.app-sandbox": True}
            with self.assertRaises(checks.VerificationError): checks.check_signature(app, TEAM)
            self.entitlements = {}
            info_path = app / "Contents/Info.plist"
            info = plistlib.loads(info_path.read_bytes()); del info["BeaconSourceCommit"]
            info_path.write_bytes(plistlib.dumps(info))
            with self.assertRaises(checks.VerificationError): checks.check_signature(app, TEAM)
            info_path.write_bytes(plistlib.dumps([]))
            with self.assertRaises(checks.VerificationError): checks.check_signature(app, TEAM)

    def testChangedNestedCodeLayoutRequiresSigningReviewNotDeepAppEntitlements(self):
        app = self.make_app(self.root / "BeaconMac.app")
        checks.signing_layout(app)
        framework = app / "Contents/Frameworks/Unreviewed.framework"
        framework.mkdir(parents=True)
        with self.assertRaises(checks.VerificationError): checks.signing_layout(app)

    def testProductionVerifierRefusesNonMacHostAndExistingEvidence(self):
        with patch.object(checks.platform, "system", return_value="Linux"), patch.object(checks, "run") as run:
            with self.assertRaises(checks.VerificationError): checks.verify_artifact(self.dmg, TEAM, self.output)
            run.assert_not_called()
        self.output.write_text("old evidence must remain unchanged")
        with self.assertRaises(checks.VerificationError): self.verify()
        self.assertEqual(self.output.read_text(), "old evidence must remain unchanged")
        self.assertEqual(self.calls, [])

    def testGatekeeperMustBeEnabled(self):
        self.policy = "assessments disabled"
        with self.assertRaises(checks.VerificationError): self.verify()
        self.assertFalse(self.output.exists())
        self.assertFalse(any("attach" in call for call in self.calls))

    def testStaplerAndDmgGatekeeperFailuresNeverEmitPassingEvidence(self):
        for gate in (lambda c: "stapler" in c, lambda c: "context:primary-signature" in c):
            self.calls = []; self.fail = gate
            with self.assertRaises(checks.VerificationError): self.verify()
            self.assertFalse(self.output.exists())
            self.assertFalse(any("attach" in call for call in self.calls))

    def testAppGatekeeperFailureStillDetachesAndNeverEmitsEvidence(self):
        self.assessment = "accepted\nsource=Developer ID\n"  # Not notarized.
        with self.assertRaises(checks.VerificationError): self.verify()
        self.assertTrue(any("detach" in call for call in self.calls))
        self.assertFalse(self.output.exists())

    def testMissingAppAndDetachFailureDoNotLeaveSuccessReport(self):
        self.no_app = True
        with self.assertRaises(checks.VerificationError): self.verify()
        self.assertTrue(any("detach" in call for call in self.calls))
        self.no_app = False; self.fail = lambda c: "detach" in c
        with self.assertRaises(checks.VerificationError): self.verify()
        self.assertFalse(self.output.exists())

    def testChangedArtifactCannotReuseSuccessfulSecurityChecks(self):
        self.mutate_image = True
        with self.assertRaises(checks.VerificationError): self.verify()
        self.assertFalse(self.output.exists())

    def testInjectedSecuritySuccessDoesNotClaimInstallationOrRuntimeAcceptance(self):
        report = self.verify()
        self.assertEqual(report["artifact"]["sha256"], checks.sha256(self.dmg))
        self.assertEqual(report["app"]["source_commit"], "a" * 40)
        self.assertEqual(report["release_acceptance"], "not_assessed")
        for key in ("runtime", "real_device", "clean_mac_install", "first_launch_permissions", "relogin_and_upgrade"):
            self.assertEqual(report[key], "not_performed")
        self.assertEqual(json.loads(self.output.read_text()), report)
        attach = next(c for c in self.calls if "attach" in c)
        self.assertIn("-readonly", attach); self.assertIn("-nobrowse", attach)
        self.assertFalse(any(Path(c[0]).name in ("open", "installer", "xattr") for c in self.calls))
        self.assertFalse(any("--master-disable" in c for c in self.calls))

    def testPackagingFailsBeforeBuildWhenNotarizationInputsAreMissing(self):
        env = {k: v for k, v in os.environ.items() if k not in (
            "DEVELOPER_ID_IDENTITY", "EXPECTED_TEAM_ID", "TEAM_ID", "NOTARY_PROFILE",
            "APPLE_ID", "APPLE_APP_PASSWORD")}
        env["NOTARIZE"] = "1"
        result = subprocess.run(["bash", str(Path(__file__).with_name("package_dmg.sh"))],
                                env=env, capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires a Developer ID", result.stderr)
        self.assertNotIn("Building", result.stdout)


if __name__ == "__main__":
    unittest.main()
