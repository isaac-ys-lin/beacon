#!/usr/bin/env python3
"""Fail-closed checks for the existing Beacon DMG workflow; never installs/runs the app."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import subprocess
import sys
import tempfile
import uuid


class VerificationError(RuntimeError):
    pass


def preflight(env: dict[str, str]) -> None:
    mode = env.get("NOTARIZE", "0")
    if mode not in {"0", "1"}:
        raise VerificationError("NOTARIZE must be 0 or 1")
    if mode == "0":
        return  # Existing local ad-hoc builds do not require distribution credentials.
    if env.get("CONFIGURATION", "Release") != "Release":
        raise VerificationError("Notarization requires a Release build")
    identity = env.get("DEVELOPER_ID_IDENTITY", "").strip()
    if not identity or identity == "-":
        raise VerificationError("NOTARIZE=1 requires a Developer ID Application signing identity")
    team = env.get("EXPECTED_TEAM_ID", env.get("TEAM_ID", ""))
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise VerificationError("Set EXPECTED_TEAM_ID (or TEAM_ID) to the expected 10-character signing team")
    if not env.get("NOTARY_PROFILE") and not all(env.get(k) for k in ("APPLE_ID", "APPLE_APP_PASSWORD", "TEAM_ID")):
        raise VerificationError("Set NOTARY_PROFILE or all three Apple notarization credential variables")


def notary_result(path: Path) -> dict:
    try:
        result = json.loads(path.read_text())
        if not isinstance(result, dict):
            raise ValueError("not an object")
        result["id"] = str(uuid.UUID(result["id"]))
        return result
    except (ValueError, KeyError, TypeError, AttributeError) as exc:
        raise VerificationError("Missing or malformed Apple notarization result") from exc


def accepted_notary_result(path: Path) -> str:
    result = notary_result(path)
    if result.get("status") != "Accepted":
        raise VerificationError("Apple did not report notarization Accepted; inspect the retained result/log")
    return result["id"]


def signing_layout(app: Path) -> None:
    """Fail closed if Beacon grows nested code needing its own signing/entitlements."""
    contents = app / "Contents"
    if not contents.is_dir():
        raise VerificationError("App bundle is missing")
    nested_suffixes = {".app", ".framework", ".xpc", ".appex", ".bundle", ".dylib"}
    for entry in contents.rglob("*"):
        if entry.suffix.lower() in nested_suffixes or entry.name in {"Helpers", "LoginItems", "PlugIns"}:
            raise VerificationError("Nested code requires an explicit inside-out signing policy before distribution")
        if entry.is_symlink() and not entry.resolve().is_relative_to(app.resolve()):
            raise VerificationError("App contains an external symlink")
    executables = list((contents / "MacOS").iterdir()) if (contents / "MacOS").is_dir() else []
    if len(executables) != 1 or not executables[0].is_file():
        raise VerificationError("Unexpected executable layout requires explicit signing review")


def run(command: list[str]) -> subprocess.CompletedProcess[bytes]:
    try:
        result = subprocess.run(command, capture_output=True, timeout=120, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise VerificationError(f"Could not complete {Path(command[0]).name}") from exc
    if result.returncode:
        detail = (result.stdout + result.stderr).decode("utf-8", "replace")
        raise VerificationError(f"{Path(command[0]).name} exited {result.returncode}: {detail}")
    return result


def signature_details(text: str, team: str, *, app: bool) -> None:
    authorities = re.findall(r"^Authority=(.+)$", text, re.M)
    if not authorities or not authorities[0].startswith("Developer ID Application:"):
        raise VerificationError("Signature is not Developer ID Application (ad-hoc/development is insufficient)")
    if re.search(r"^TeamIdentifier=(.+)$", text, re.M) is None or f"TeamIdentifier={team}\n" not in text + "\n":
        raise VerificationError("Signature team does not match the explicitly expected team")
    if not re.search(r"^Timestamp=(?!none\s*$).+", text, re.M | re.I):
        raise VerificationError("Secure signing timestamp is missing")
    if app and not re.search(r"flags=0x[0-9a-f]+\([^\n)]*\bruntime\b", text, re.I):
        raise VerificationError("Hardened runtime is missing")


def check_signature(path: Path, team: str, *, app: bool = True) -> dict:
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise VerificationError("Invalid expected signing team")
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(path)])
    result = run(["/usr/bin/codesign", "--display", "--verbose=4", str(path)])
    signature_details((result.stdout + result.stderr).decode("utf-8", "replace"), team, app=app)
    if not app:
        return {"team_id": team, "certificate_type": "Developer ID Application"}
    entitlement_data = run(["/usr/bin/codesign", "--display", "--entitlements", ":-", str(path)]).stdout
    try:
        entitlements = plistlib.loads(entitlement_data)
        if not isinstance(entitlements, dict) or entitlements.get("com.apple.security.get-task-allow", False):
            raise VerificationError("Release entitlements allow debugging or are invalid")
        if entitlements.get("com.apple.security.app-sandbox", False):
            raise VerificationError("App Sandbox blocks the required iPhone battery subprocess")
        info = plistlib.loads((path / "Contents/Info.plist").read_bytes())
        if not isinstance(info, dict):
            raise VerificationError("Release bundle metadata is not a dictionary")
        required = ["CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion", "CFBundleExecutable", "BeaconSourceCommit"]
        if not all(isinstance(info.get(k), str) and info[k].strip() for k in required):
            raise VerificationError("Release bundle metadata is incomplete")
        if info["CFBundleIdentifier"] != "com.isaacyslin.Beacon.mac":
            raise VerificationError("Unexpected bundle identifier")
        if not re.fullmatch(r"[0-9a-f]{40}", info["BeaconSourceCommit"]):
            raise VerificationError("Missing full source commit in signed bundle")
        executable = path / "Contents/MacOS" / info["CFBundleExecutable"]
        if not executable.is_file() or not executable.resolve().is_relative_to(path.resolve()):
            raise VerificationError("Bundle executable is missing or outside the app")
        return {"team_id": team, "bundle_id": info["CFBundleIdentifier"],
                "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
                "source_commit": info["BeaconSourceCommit"]}
    except (OSError, ValueError, plistlib.InvalidFileException, TypeError) as exc:
        raise VerificationError("Unable to verify signed bundle metadata/entitlements") from exc


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_artifact(dmg: Path, team: str, output: Path) -> dict:
    if platform.system() != "Darwin":
        raise VerificationError("Actual artifact verification requires macOS; fixture tests are not distribution evidence")
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise VerificationError("Invalid expected signing team")
    dmg = dmg.resolve(strict=True)
    if not dmg.is_file() or dmg.suffix.lower() != ".dmg":
        raise VerificationError("Provide the actual DMG file")
    if output.exists():
        raise VerificationError("Evidence output already exists; use a new file rather than reusing stale evidence")
    before = sha256(dmg)
    policy = run(["/usr/sbin/spctl", "--status"])
    if (policy.stdout + policy.stderr).decode().strip() != "assessments enabled":
        raise VerificationError("Gatekeeper assessments are not enabled")
    run(["/usr/bin/hdiutil", "verify", str(dmg)])
    check_signature(dmg, team, app=False)
    run(["/usr/bin/xcrun", "stapler", "validate", str(dmg)])
    run(["/usr/sbin/spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=2", str(dmg)])
    with tempfile.TemporaryDirectory(prefix="beacon-release-check-") as temporary:
        mount = Path(temporary) / "volume"
        mount.mkdir()
        run(["/usr/bin/hdiutil", "attach", str(dmg), "-readonly", "-nobrowse", "-mountpoint", str(mount)])
        try:
            app = mount / "BeaconMac.app"
            if not app.is_dir() or not app.resolve().is_relative_to(mount.resolve()):
                raise VerificationError("DMG does not contain the expected app inside its mounted volume")
            metadata = check_signature(app, team)
            assessment = run(["/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=2", str(app)])
            if "source=Notarized Developer ID" not in (assessment.stdout + assessment.stderr).decode("utf-8", "replace"):
                raise VerificationError("App assessment did not identify a notarized Developer ID source")
        finally:
            # Never force detach and never launch or install a downloaded executable.
            run(["/usr/bin/hdiutil", "detach", str(mount)])
    if sha256(dmg) != before:
        raise VerificationError("DMG changed during verification")
    report = {"schema_version": 1, "evidence_kind": "actual-distribution-security-checks",
              "checked_at": dt.datetime.now(dt.timezone.utc).isoformat(), "macos": platform.mac_ver()[0],
              "artifact": {"file": dmg.name, "sha256": before, "bytes": dmg.stat().st_size}, "app": metadata,
              "checks": {"developer_id": "passed", "hardened_runtime": "passed", "stapled_ticket": "passed",
                         "gatekeeper_dmg": "passed", "gatekeeper_app": "passed"},
              "runtime": "not_performed", "real_device": "not_performed", "clean_mac_install": "not_performed",
              "first_launch_permissions": "not_performed", "relogin_and_upgrade": "not_performed",
              "release_acceptance": "not_assessed"}
    with output.open("x") as handle:
        json.dump(report, handle, indent=2); handle.write("\n")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("preflight")
    for name in ("notary-result", "notary-id", "signing-layout"):
        command = sub.add_parser(name); command.add_argument("path", type=Path)
    signature = sub.add_parser("signature"); signature.add_argument("path", type=Path); signature.add_argument("--team", required=True)
    artifact = sub.add_parser("artifact"); artifact.add_argument("path", type=Path)
    artifact.add_argument("--team", required=True); artifact.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        if args.command == "preflight": preflight(dict(os.environ))
        elif args.command == "notary-id": print(notary_result(args.path)["id"])
        elif args.command == "signing-layout": signing_layout(args.path)
        elif args.command == "notary-result": print(accepted_notary_result(args.path))
        elif args.command == "signature": print(json.dumps(check_signature(args.path, args.team), indent=2))
        else: print(json.dumps(verify_artifact(args.path, args.team, args.output), indent=2))
    except (VerificationError, OSError, UnicodeError) as exc:
        print(f"Verification failed: {exc}", file=sys.stderr); return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
