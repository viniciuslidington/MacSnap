import base64
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

module = importlib.util.spec_from_file_location("updates", Path(__file__).with_name("update-distribution.py"))
updates = importlib.util.module_from_spec(module)
module.loader.exec_module(updates)


def feed(build=8, version="1.0.8", *, signature=None):
    signature = signature or base64.b64encode(bytes(64)).decode()
    return f'''<rss xmlns:sparkle="{updates.NS}"><channel><title>MacSnap</title><item>
    <sparkle:version>{build}</sparkle:version><sparkle:shortVersionString>{version}</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>13.0.0</sparkle:minimumSystemVersion>
    <enclosure url="https://github.com/{updates.REPO}/releases/download/v{version}/MacSnap.app.zip"
    length="1234" sparkle:edSignature="{signature}"/></item></channel></rss>'''.encode()


class UpdatePublicationTests(unittest.TestCase):
    def test_github_api_uses_workflow_token_without_forwarding_it_to_other_hosts(self):
        for url, authenticated in [
            ("https://api.github.com/repos/example/app/releases", True),
            ("http://api.github.com/repos/example/app/releases", False),
            ("https://api.github.com.example.invalid/releases", False),
            ("https://github.com/example/app/releases/download/v1/appcast.xml", False),
        ]:
            with self.subTest(url=url), patch.dict(updates.os.environ, {"GH_TOKEN": "test-token"}, clear=True), \
                    patch.object(updates.urllib.request, "urlopen") as opened:
                opened.return_value.__enter__.return_value.read.return_value = b"[]"
                self.assertEqual(updates.fetch(url), b"[]")
                request = opened.call_args.args[0]
                self.assertEqual(request.get_header("Authorization"), "Bearer test-token" if authenticated else None)
                redirected = updates.urllib.request.HTTPRedirectHandler().redirect_request(
                    request, None, 302, "Found", {}, "https://cdn.example.invalid/feed.xml")
                self.assertIsNone(redirected.get_header("Authorization"))

    def test_public_api_reads_still_work_without_a_workflow_token(self):
        with patch.dict(updates.os.environ, {}, clear=True), \
                patch.object(updates.urllib.request, "urlopen") as opened:
            opened.return_value.__enter__.return_value.read.return_value = b"[]"
            updates.fetch("https://api.github.com/repos/example/app/releases")
            self.assertIsNone(opened.call_args.args[0].get_header("Authorization"))

    def test_new_release_preserves_the_previous_offers(self):
        merged = updates.merge_feed(feed(9, "1.0.9"), feed())
        self.assertEqual(list(updates.entries(merged)), [9, 8])

    def test_stale_run_cannot_regress_feed(self):
        with self.assertRaisesRegex(ValueError, "regress"):
            updates.merge_feed(feed(), feed(9, "1.0.9"))

    def test_same_build_cannot_change_an_offered_archive(self):
        changed = feed(signature=base64.b64encode(bytes([1]) * 64).decode())
        with self.assertRaisesRegex(ValueError, "already offered"):
            updates.merge_feed(changed, feed())

    def test_republishing_identical_feed_is_safe(self):
        self.assertEqual(len(updates.entries(updates.merge_feed(feed(), feed()))), 1)

    def test_moving_download_url_is_rejected(self):
        moving = feed().replace(b"releases/download/v1.0.8", b"releases/latest/download")
        with self.assertRaisesRegex(ValueError, "immutable"):
            updates.entries(moving)

    def test_missing_or_malformed_archive_signature_is_rejected(self):
        for signature in ["invalid", base64.b64encode(bytes(32)).decode()]:
            with self.assertRaises(ValueError):
                updates.entries(feed(signature=signature))

    def test_duplicate_build_and_xml_entities_are_rejected(self):
        root = updates.read_xml(feed())
        root.find("channel").append(copy.deepcopy(root.find("channel/item")))
        duplicate = updates.ET.tostring(root)
        with self.assertRaises(ValueError):
            updates.entries(duplicate)
        with self.assertRaisesRegex(ValueError, "Unsupported"):
            updates.entries(b'<!DOCTYPE rss [<!ENTITY x "bad">]>' + feed())

    def test_empty_baseline_is_valid_but_cannot_replace_an_offer(self):
        baseline = b"<rss><channel/></rss>"
        self.assertEqual(updates.entries(baseline), {})
        with self.assertRaisesRegex(ValueError, "no update"):
            updates.merge_feed(baseline, feed())

    def test_invalid_key_error_does_not_echo_input(self):
        secret = "private-input-that-must-not-appear"
        with self.assertRaises(ValueError) as failure:
            updates.decoded(secret, 32, "private signing seed")
        self.assertNotIn(secret, str(failure.exception))

    def test_incompatible_metadata_is_not_treated_as_a_valid_offer(self):
        with self.assertRaisesRegex(ValueError, "macOS"):
            updates.entries(feed().replace(b"13.0.0", b"unknown"))
        self.assertEqual(updates.system_version("13.0"), updates.system_version("13.0.0"))

    def test_invalid_publication_receipt_does_not_change_site_artifact(self):
        with tempfile.TemporaryDirectory() as folder:
            site = Path(folder)
            (site / "updates").mkdir()
            target = site / "updates/appcast.xml"
            target.write_bytes(feed())
            url = f"https://github.com/{updates.REPO}/releases/download/v1.0.9/"
            latest = json.dumps([{"tag_name": "v1.0.9", "assets": [
                {"name": name, "browser_download_url": url + name}
                for name in ["appcast.xml", "update-approval.json"]]}]).encode()
            bad_receipt = json.dumps({"tag": "v1.0.9", "appcast_sha256": "0" * 64,
                                      "archive_sha256": "a" * 64}).encode()
            with patch.object(updates, "fetch", side_effect=[feed(), latest, feed(9, "1.0.9"), bad_receipt]):
                with self.assertRaisesRegex(ValueError, "receipt"):
                    updates.hydrate(type("Args", (), {"site": site}))
            self.assertEqual(target.read_bytes(), feed())

    def test_marketing_deployment_restores_feed_from_latest_approved_release(self):
        with tempfile.TemporaryDirectory() as folder:
            site = Path(folder)
            (site / "updates").mkdir()
            target = site / "updates/appcast.xml"
            target.write_bytes(b"<rss><channel/></rss>")
            url = f"https://github.com/{updates.REPO}/releases/download/v1.0.9/appcast.xml"
            latest = json.dumps([{"tag_name": "v1.0.9", "assets": [
                {"name": "appcast.xml", "browser_download_url": url},
                {"name": "update-approval.json", "browser_download_url": url.replace("appcast.xml", "update-approval.json")}]}]).encode()
            receipt = json.dumps({"tag": "v1.0.9", "archive_sha256": "a" * 64,
                                  "appcast_sha256": hashlib.sha256(feed(9, "1.0.9")).hexdigest()}).encode()
            with patch.object(updates, "fetch", side_effect=[feed(), latest, feed(9, "1.0.9"), receipt]):
                updates.hydrate(type("Args", (), {"site": site}))
            self.assertEqual(list(updates.entries(target.read_bytes())), [9, 8])

    def test_missing_feed_asset_does_not_erase_a_deployed_channel(self):
        with tempfile.TemporaryDirectory() as folder:
            site = Path(folder)
            (site / "updates").mkdir()
            target = site / "updates/appcast.xml"
            baseline = b"<rss><channel/></rss>"
            target.write_bytes(baseline)
            with patch.object(updates, "fetch", side_effect=[feed(), b'[{"assets":[]}]']):
                updates.hydrate(type("Args", (), {"site": site}))
            self.assertEqual(target.read_bytes(), feed())

    def test_public_release_without_successful_verification_cannot_publish_feed(self):
        with tempfile.TemporaryDirectory() as folder:
            site = Path(folder)
            (site / "updates").mkdir()
            target = site / "updates/appcast.xml"
            target.write_bytes(feed())
            latest = json.dumps([{"tag_name": "v1.0.9", "assets": [{"name": "appcast.xml",
                "browser_download_url": f"https://github.com/{updates.REPO}/releases/download/v1.0.9/appcast.xml"}]}]).encode()
            with patch.object(updates, "fetch", side_effect=[feed(), latest]):
                updates.hydrate(type("Args", (), {"site": site}))
            self.assertEqual(target.read_bytes(), feed())

    def test_promotion_cannot_regress_an_approved_release_awaiting_pages(self):
        with tempfile.TemporaryDirectory() as folder:
            candidate = Path(folder) / "appcast.xml"
            candidate.write_bytes(feed())
            newer = feed(9, "1.0.9")
            url = f"https://github.com/{updates.REPO}/releases/download/v1.0.9/"
            releases = json.dumps([{"tag_name": "v1.0.9", "assets": [
                {"name": name, "browser_download_url": url + name}
                for name in ["appcast.xml", "update-approval.json"]]}]).encode()
            receipt = json.dumps({"tag": "v1.0.9", "archive_sha256": "a" * 64,
                                  "appcast_sha256": hashlib.sha256(newer).hexdigest()}).encode()
            with patch.object(updates, "fetch", side_effect=[feed(), releases, newer, receipt]):
                with self.assertRaisesRegex(ValueError, "regress"):
                    updates.promotion(type("Args", (), {"feed": candidate}))

    def test_withdrawn_offer_cannot_return_during_marketing_deployment(self):
        with tempfile.TemporaryDirectory() as folder:
            site = Path(folder)
            (site / "updates").mkdir()
            target = site / "updates/appcast.xml"
            target.write_bytes(b"<rss><channel/></rss>")
            with patch.object(updates, "withdrawn_builds", return_value={8}), \
                    patch.object(updates, "fetch", side_effect=[feed(), b"[]"]):
                updates.hydrate(type("Args", (), {"site": site}))
                self.assertEqual(updates.entries(target.read_bytes()), {})
                # Repeated hydration keeps the withdrawal even if a cached live feed still offers it.
                with patch.object(updates, "fetch", side_effect=[feed(), b"[]"]):
                    updates.hydrate(type("Args", (), {"site": site}))
                self.assertEqual(updates.entries(target.read_bytes()), {})

    def test_withdrawing_latest_offer_retains_previous_offer_and_build_floor(self):
        combined = updates.merge_feed(feed(9, "1.0.9"), feed())
        with patch.object(updates, "withdrawn_builds", return_value={9}):
            self.assertEqual(list(updates.entries(updates.apply_withdrawals(combined))), [8])
            with tempfile.TemporaryDirectory() as folder:
                candidate = Path(folder) / "appcast.xml"
                candidate.write_bytes(feed())
                with self.assertRaisesRegex(ValueError, "withdrawn"):
                    updates.promotion(type("Args", (), {"feed": candidate}))

    def test_an_older_archive_cannot_promote_a_feed_for_another_release(self):
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / "MacSnap.app.zip"
            info = {"CFBundleIdentifier": updates.APP_ID, "CFBundleVersion": "8",
                    "CFBundleShortVersionString": "1.0.8"}
            with zipfile.ZipFile(archive, "w") as zipped:
                zipped.writestr("MacSnap.app/Contents/Info.plist", plistlib.dumps(info))
            combined = updates.merge_feed(feed(9, "1.0.9"), feed())
            with self.assertRaisesRegex(ValueError, "newest"):
                updates.verify(archive, combined, base64.b64encode(bytes(32)).decode(), "v1.0.8")

    def test_archive_metadata_disagreements_are_rejected_before_signature_verification(self):
        public = base64.b64encode(bytes(32)).decode()
        other_public = base64.b64encode(bytes([1]) * 32).decode()
        cases = [
            ({}, "v1.0.9", 0, "Tag/application"),
            ({"SUPublicEDKey": other_public}, "v1.0.8", 0, "keys disagree"),
            ({"LSMinimumSystemVersion": "14.0"}, "v1.0.8", 0, "macOS requirements"),
            ({"SUFeedURL": "https://example.invalid/appcast.xml"}, "v1.0.8", 0, "not configured"),
            ({"SUVerifyUpdateBeforeExtraction": False}, "v1.0.8", 0, "not configured"),
            ({}, "v1.0.8", 1, "length disagrees"),
        ]
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / "MacSnap.app.zip"
            for changed, tag, extra_length, message in cases:
                with self.subTest(changed=changed, tag=tag, extra_length=extra_length):
                    info = {"CFBundleIdentifier": updates.APP_ID, "CFBundleVersion": "8",
                            "CFBundleShortVersionString": "1.0.8", "SUPublicEDKey": public,
                            "LSMinimumSystemVersion": "13.0", "SUFeedURL": updates.FEED,
                            "SUVerifyUpdateBeforeExtraction": True, **changed}
                    with zipfile.ZipFile(archive, "w") as zipped:
                        zipped.writestr("MacSnap.app/Contents/Info.plist", plistlib.dumps(info))
                    root = updates.read_xml(feed())
                    root.find("channel/item/enclosure").set("length", str(archive.stat().st_size + extra_length))
                    with patch.object(updates.subprocess, "run", side_effect=AssertionError("Invalid metadata reached signature verifier")):
                        with self.assertRaisesRegex(ValueError, message):
                            updates.verify(archive, updates.ET.tostring(root), public, tag)

    @unittest.skipUnless(sys.platform == "darwin", "CryptoKit verification runs in macOS CI")
    def test_real_signature_accepts_original_and_rejects_tampered_archive(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            archive = root / "update.zip"
            archive.write_bytes(b"candidate archive bytes")
            generator = root / "sign.swift"
            generator.write_text('''import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let signature = try key.signature(for: bytes)
print(key.publicKey.rawRepresentation.base64EncodedString())
print(signature.base64EncodedString())
''')
            public, signature = subprocess.check_output(["swift", str(generator), str(archive)], text=True).splitlines()
            command = ["swift", str(updates.ROOT / "scripts/verify-update.swift"), str(archive), public, signature]
            subprocess.run(command, check=True, capture_output=True)
            archive.write_bytes(b"tampered archive bytes")
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)


if __name__ == "__main__":
    unittest.main()
