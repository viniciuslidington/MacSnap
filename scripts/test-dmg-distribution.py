"""Installer rollout policies; run on any OS without disk-image dependencies."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


updates = load("updates", "update-distribution.py")
locales = load("locales", "build-site-locales.py")


class InstallerRolloutTests(unittest.TestCase):
    def release(self, url=None):
        return {"tag_name": "v1.0.8", "assets": [{
            "name": "MacSnap.dmg", "browser_download_url": url or
            f"https://github.com/{updates.REPO}/releases/download/v1.0.8/MacSnap.dmg"}]}

    def test_unreleased_installer_keeps_working_zip_links_and_guidance(self):
        for path, text in locales.render_all().items():
            if path.suffix == ".html":
                self.assertEqual(text.count('href="https://github.com/' + updates.REPO +
                                            '/releases/latest/download/MacSnap.app.zip"'), 4)
                self.assertNotIn("MacSnap.dmg", text)

    def test_only_verified_dmg_receipt_promotes_both_languages(self):
        with tempfile.TemporaryDirectory() as folder:
            site = Path(folder)
            (site / "index.html").write_text("previous-deployment")
            updates.hydrate_downloads(site, self.release(), {"dmg_sha256": "a" * 64})
            for route in ["index.html", "pt/index.html"]:
                text = (site / route).read_text()
                self.assertEqual(text.count('href="' + self.release()["assets"][0]["browser_download_url"] + '"'), 4)
                self.assertNotIn("/download/MacSnap.app.zip", text)
            self.assertIn("double-click", (site / "index.html").read_text())
            self.assertIn("atalho de Aplicativos", (site / "pt/index.html").read_text())

    def test_legacy_receipt_never_advertises_a_missing_dmg(self):
        with tempfile.TemporaryDirectory() as folder:
            site = Path(folder)
            target = site / "index.html"
            target.write_text("previous-deployment")
            updates.hydrate_downloads(site, self.release(), {"archive_sha256": "a" * 64})
            self.assertEqual(target.read_text(), "previous-deployment")

    def test_missing_moved_or_unapproved_installer_cannot_change_the_site(self):
        invalid = [
            ({"tag_name": "v1.0.8", "assets": []}, {"dmg_sha256": "a" * 64}),
            (self.release("https://example.com/replaced.dmg"), {"dmg_sha256": "a" * 64}),
            (self.release(), {"dmg_sha256": "not-a-digest"}),
        ]
        for release, receipt in invalid:
            with self.subTest(release=release, receipt=receipt), tempfile.TemporaryDirectory() as folder:
                site = Path(folder)
                target = site / "index.html"
                target.write_text("previous-deployment")
                with self.assertRaises(ValueError):
                    updates.hydrate_downloads(site, release, receipt)
                self.assertEqual(target.read_text(), "previous-deployment")


if __name__ == "__main__":
    unittest.main()
