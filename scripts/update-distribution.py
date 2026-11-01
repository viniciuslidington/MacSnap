#!/usr/bin/env python3
"""Assemble apps, prepare signed candidates and preserve the approved update feed."""
import argparse
import base64
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parent.parent
REPO = "viniciuslidington/MacSnap"
SITE = f"https://viniciuslidington.github.io/MacSnap/"
FEED = SITE + "updates/appcast.xml"
NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", NS)
SPARKLE = ROOT / ".build/artifacts/sparkle/Sparkle"
APP_ID = "com.viniciuslidington.MacSnap"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def decoded(value, length, name):
    try:
        data = base64.b64decode(value, validate=True)
    except (ValueError, TypeError):
        raise ValueError(f"Invalid {name}") from None
    require(len(data) == length, f"Invalid {name} length")
    return data


def read_xml(data):
    require(len(data) <= 2_000_000 and b"<!DOCTYPE" not in data.upper()
            and b"<!ENTITY" not in data.upper(), "Unsupported update feed")
    root = ET.fromstring(data)
    require(root.tag == "rss" and root.find("channel") is not None, "Invalid appcast")
    return root


def system_version(value):
    require(isinstance(value, str) and re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", value),
            "Invalid minimum macOS version")
    return tuple(int(part) for part in (value.split(".") + ["0"])[:3])


def entries(data):
    root = read_xml(data)
    result = {}
    for item in root.findall("channel/item"):
        build = item.findtext(f"{{{NS}}}version", "")
        version = item.findtext(f"{{{NS}}}shortVersionString", "")
        require(build.isdecimal() and int(build) > 0, "Invalid update build")
        require(re.fullmatch(r"\d+\.\d+\.\d+", version), "Invalid display version")
        enclosure = item.find("enclosure")
        require(enclosure is not None, "Missing update archive")
        expected = f"https://github.com/{REPO}/releases/download/v{version}/MacSnap.app.zip"
        require(enclosure.get("url") == expected, "Update archive must use its immutable release URL")
        length = enclosure.get("length", "")
        require(length.isdecimal() and int(length) > 0, "Invalid archive length")
        decoded(enclosure.get(f"{{{NS}}}edSignature"), 64, "archive signature")
        system_version(item.findtext(f"{{{NS}}}minimumSystemVersion"))
        require(int(build) not in result, "Duplicate update build")
        result[int(build)] = (item, enclosure)
    return result


def merge_feed(candidate, previous):
    current, old = entries(candidate), entries(previous)
    require(current, "Candidate feed contains no update")
    require(not old or max(current) >= max(old), "Refusing to regress the production feed")
    for build in current.keys() & old.keys():
        require(current[build][1].attrib == old[build][1].attrib,
                "Refusing to replace an already offered archive")
    root = read_xml(candidate)
    channel = root.find("channel")
    for item in list(channel.findall("item")):
        channel.remove(item)
    combined = {**old, **current}
    for build in sorted(combined, reverse=True):
        channel.append(copy.deepcopy(combined[build][0]))
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def fetch(url, *, allow_missing=False):
    request = urllib.request.Request(url, headers={"User-Agent": "MacSnap-release"})
    parsed = urllib.parse.urlsplit(url)
    token = os.environ.get("GH_TOKEN", "")
    if parsed.scheme == "https" and parsed.netloc == "api.github.com" and token:
        # Workflow runners share anonymous rate limits. Never forward this credential
        # to download/CDN hosts or to a redirect destination.
        request.add_unredirected_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            data = response.read(2_000_001)
            require(len(data) <= 2_000_000, "Release metadata exceeded size limit")
            return data
    except urllib.error.HTTPError as error:
        if allow_missing and error.code == 404:
            return None
        raise


def withdrawn_builds():
    builds = json.loads((ROOT / "site/updates/withdrawn-builds.json").read_text())
    require(isinstance(builds, list) and all(type(build) is int and build > 0 for build in builds),
            "Withdrawn builds must be a list of positive integers")
    return set(builds)


def apply_withdrawals(data):
    withdrawn = withdrawn_builds()
    if not withdrawn.intersection(entries(data)):
        return data
    root = read_xml(data)
    channel = root.find("channel")
    for item in channel.findall("item"):
        if int(item.findtext(f"{{{NS}}}version")) in withdrawn:
            channel.remove(item)
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def archive_info(archive):
    with zipfile.ZipFile(archive) as zipped:
        # Read a fixed member without extracting any archive-controlled paths.
        member = zipped.getinfo("MacSnap.app/Contents/Info.plist")
        require(member.file_size <= 131_072, "Oversized application metadata")
        info = plistlib.loads(zipped.read(member))
    require(info.get("CFBundleIdentifier") == APP_ID, "Unexpected application identity")
    build = str(info.get("CFBundleVersion", ""))
    require(build.isdecimal() and int(build) > 0, "Invalid application build")
    require(re.fullmatch(r"\d+\.\d+\.\d+", info.get("CFBundleShortVersionString", "")),
            "Invalid application display version")
    return info


def assemble(args):
    info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
    if args.version:
        require(re.fullmatch(r"\d+\.\d+\.\d+", args.version), "Invalid display version")
        info["CFBundleShortVersionString"] = args.version
    if args.build:
        require(args.build.isdecimal() and int(args.build) > 0, "Invalid build number")
        info["CFBundleVersion"] = args.build
    public = os.environ.get("MACSNAP_UPDATE_PUBLIC_KEY", "").strip()
    if public:
        decoded(public, 32, "public key")
        info["SUPublicEDKey"] = public
    else:
        require(args.allow_unconfigured, "MACSNAP_UPDATE_PUBLIC_KEY is required for a release")
    app = args.output.resolve()
    require(app.name == "MacSnap.app", "Output must be named MacSnap.app")
    require(not app.exists(), "Output already exists; choose a fresh candidate directory")
    (app / "Contents/MacOS").mkdir(parents=True)
    (app / "Contents/Resources").mkdir()
    shutil.copy2(args.binary, app / "Contents/MacOS/MacSnap")
    helper = args.binary.parent / "MacSnapUninstaller"
    require(helper.is_file(), "Build MacSnapUninstaller before assembling the app")
    app_archs = set(subprocess.check_output(["lipo", "-archs", str(args.binary)], text=True).split())
    helper_archs = set(subprocess.check_output(["lipo", "-archs", str(helper)], text=True).split())
    require(app_archs.issubset(helper_archs), "Uninstaller does not support all app architectures")
    (app / "Contents/Helpers").mkdir()
    shutil.copy2(helper, app / "Contents/Helpers/MacSnapUninstaller")
    shutil.copy2(ROOT / "Resources/AppIcon.icns", app / "Contents/Resources/AppIcon.icns")
    framework = SPARKLE / "Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
    subprocess.run(["ditto", str(framework), str(app / "Contents/Frameworks/Sparkle.framework")], check=True)
    (app / "Contents/Resources/Sparkle-LICENSE.txt").write_bytes((SPARKLE / "LICENSE").read_bytes())
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    # Vendor helpers retain their original signatures and runtime flags. Sign outer layers last.
    for path in [app / "Contents/Helpers/MacSnapUninstaller", app / "Contents/Frameworks/Sparkle.framework", app]:
        subprocess.run(["codesign", "--force", "--sign", args.identity, str(path)], check=True)
    subprocess.run(["codesign", "--verify", "--strict", "--deep", str(app)], check=True)
    linked = subprocess.check_output(["otool", "-l", str(app / "Contents/MacOS/MacSnap")], text=True)
    require("@executable_path/../Frameworks" in linked, "Missing self-contained framework runpath")
    print(f"Assembled and verified {app}")


def verify(archive, feed, public, tag):
    decoded(public, 32, "public key")
    info = archive_info(archive)
    require(tag == "v" + info["CFBundleShortVersionString"], "Tag/application version disagreement")
    offered = entries(feed)
    build = int(info["CFBundleVersion"])
    require(build in offered, "Archive build is absent from feed")
    require(build == max(offered), "Candidate archive must be the newest feed build")
    item, enclosure = offered[build]
    require(item.findtext(f"{{{NS}}}shortVersionString") == info["CFBundleShortVersionString"],
            "Feed/application versions disagree")
    require(info.get("SUPublicEDKey") == public, "Application/public release keys disagree")
    require(system_version(item.findtext(f"{{{NS}}}minimumSystemVersion")) ==
            system_version(info.get("LSMinimumSystemVersion")), "Feed/application macOS requirements disagree")
    require(info.get("SUFeedURL") == FEED and info.get("SUVerifyUpdateBeforeExtraction") is True,
            "Application update verification is not configured")
    require(archive.stat().st_size == int(enclosure.get("length")), "Archive length disagrees with feed")
    subprocess.run(["swift", str(ROOT / "scripts/verify-update.swift"), str(archive), public,
                    enclosure.get(f"{{{NS}}}edSignature")], check=True)


def prepare(args):
    info = archive_info(args.archive)
    tag = "v" + info["CFBundleShortVersionString"]
    require(args.tag == tag, "Tag and application version disagree")
    public = os.environ.get("MACSNAP_UPDATE_PUBLIC_KEY", "").strip()
    secret = os.environ.get("MACSNAP_UPDATE_PRIVATE_KEY", "").strip()
    decoded(public, 32, "public key")
    decoded(secret, 32, "private signing seed")
    require(int(info["CFBundleVersion"]) > max(withdrawn_builds(), default=0),
            "Build number must exceed withdrawn builds")
    previous = fetch(FEED, allow_missing=True)
    if previous:
        old = entries(previous)
        require(not old or int(info["CFBundleVersion"]) > max(old), "Build number must increase")
    with tempfile.TemporaryDirectory(prefix="macsnap-candidate-") as folder:
        staging = Path(folder)
        shutil.copy2(args.archive, staging / "MacSnap.app.zip")
        # Plain release text becomes escaped embedded notes; no remote notes script is needed.
        import html
        (staging / "MacSnap.app.html").write_text("<p>" + html.escape(args.notes.read_text())
                                                .replace("\n", "<br>") + "</p>")
        command = [str(SPARKLE / "bin/generate_appcast"), "--ed-key-file", "-", "--maximum-deltas", "0",
                   "--download-url-prefix", f"https://github.com/{REPO}/releases/download/{tag}/",
                   "--link", SITE, "--embed-release-notes", str(staging)]
        environment = {k: v for k, v in os.environ.items() if k != "MACSNAP_UPDATE_PRIVATE_KEY"}
        result = subprocess.run(command, input=secret + "\n", text=True, capture_output=True, env=environment)
        # SDK diagnostics may contain malformed key input. Never relay captured signing output.
        require(result.returncode == 0, "Sparkle appcast generation failed; signing output withheld")
        candidate = (staging / "appcast.xml").read_bytes()
        if previous:
            candidate = merge_feed(candidate, previous)
        verify(args.archive, candidate, public, args.tag)
        args.output.write_bytes(candidate)
    print("Prepared signed candidate feed. No release or feed was published.")


def hydrate_downloads(site, release, receipt):
    """Promote the installer only after its public bytes have a publication receipt."""
    if "dmg_sha256" not in receipt or not (site / "index.html").is_file():
        return
    require(re.fullmatch(r"[a-f0-9]{64}", receipt["dmg_sha256"]), "Invalid DMG approval digest")
    tag = release["tag_name"]
    expected = f"https://github.com/{REPO}/releases/download/{tag}/MacSnap.dmg"
    asset = next((a for a in release.get("assets", []) if a["name"] == "MacSnap.dmg"), None)
    require(asset is not None and asset["browser_download_url"] == expected,
            "Approved installer is missing from the release")
    # Render both languages from their sources; no client-side API or JavaScript is needed.
    spec = importlib.util.spec_from_file_location("site_locales", ROOT / "scripts/build-site-locales.py")
    renderer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(renderer)
    for path, content in renderer.render_all(release_tag=tag).items():
        destination = site / path.relative_to(renderer.SITE)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(content, encoding="utf-8")
    print("Promoted approved DMG download and installation guidance in both languages.")


def hydrate(args):
    target = args.site / "updates/appcast.xml"
    baseline = target.read_bytes()
    live = fetch(FEED, allow_missing=True) or baseline
    entries(live)
    releases_data = fetch(f"https://api.github.com/repos/{REPO}/releases?per_page=100")
    releases = json.loads(releases_data)
    require(isinstance(releases, list), "Invalid release metadata")
    approved = [release for release in releases
                if not release.get("draft") and not release.get("prerelease")
                and {"appcast.xml", "update-approval.json"}.issubset(
                    {asset["name"] for asset in release.get("assets", [])})]
    approved.sort(key=lambda release: release.get("published_at", ""), reverse=True)
    latest = approved[0] if approved else {}
    asset = next((asset for asset in latest.get("assets", []) if asset["name"] == "appcast.xml"), None)
    if not asset:
        # A public candidate whose verification failed has no approval receipt.
        # Keep the last working channel instead of allowing an unrelated site deploy to promote it.
        target.write_bytes(apply_withdrawals(live))
        return
    tag = latest.get("tag_name", "")
    require(re.fullmatch(r"v\d+\.\d+\.\d+", tag), "Unsupported latest-release tag")
    expected = f"https://github.com/{REPO}/releases/download/{tag}/appcast.xml"
    require(asset["browser_download_url"] == expected, "Unexpected feed asset URL")
    candidate = fetch(expected)
    approval_url = f"https://github.com/{REPO}/releases/download/{tag}/update-approval.json"
    approval = next((a for a in latest.get("assets", []) if a["name"] == "update-approval.json"), None)
    require(approval is not None and approval["browser_download_url"] == approval_url,
            "Release has no verified publication receipt; refusing feed deployment")
    receipt = json.loads(fetch(approval_url))
    require(receipt.get("tag") == tag and
            receipt.get("appcast_sha256") == hashlib.sha256(candidate).hexdigest() and
            re.fullmatch(r"[a-f0-9]{64}", receipt.get("archive_sha256", "")),
            "Publication receipt does not match release feed")
    offered = entries(candidate)
    require(offered and offered[max(offered)][0].findtext(f"{{{NS}}}shortVersionString") == tag[1:],
            "Latest-release feed/version disagreement")
    merged = apply_withdrawals(merge_feed(candidate, live))
    if max(offered) not in withdrawn_builds():
        hydrate_downloads(args.site, latest, receipt)
    target.write_bytes(merged)
    print("Preserved approved feed in website deployment artifact.")


def promotion(args):
    candidate = args.feed.read_bytes()
    offered = entries(candidate)
    require(offered and max(offered) > max(withdrawn_builds(), default=0),
            "Cannot promote a withdrawn or older build")
    with tempfile.TemporaryDirectory(prefix="macsnap-promotion-") as folder:
        root = Path(folder)
        (root / "updates").mkdir()
        (root / "updates/appcast.xml").write_bytes(b"<rss><channel/></rss>")
        # Hydration validates both the deployed feed and the latest approved release,
        # including a release whose Pages deployment has not finished yet.
        hydrate(argparse.Namespace(site=root))
        merge_feed(candidate, (root / "updates/appcast.xml").read_bytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    app = commands.add_parser("assemble")
    app.add_argument("--binary", type=Path, required=True)
    app.add_argument("--output", type=Path, required=True)
    app.add_argument("--allow-unconfigured", action="store_true")
    app.add_argument("--identity", default="-")
    app.add_argument("--version")
    app.add_argument("--build")
    candidate = commands.add_parser("prepare")
    candidate.add_argument("--archive", type=Path, required=True)
    candidate.add_argument("--tag", required=True)
    candidate.add_argument("--notes", type=Path, required=True)
    candidate.add_argument("--output", type=Path, required=True)
    check = commands.add_parser("verify")
    check.add_argument("--archive", type=Path, required=True)
    check.add_argument("--feed", type=Path, required=True)
    check.add_argument("--tag", required=True)
    deploy = commands.add_parser("hydrate")
    deploy.add_argument("--site", type=Path, required=True)
    promote = commands.add_parser("check-promotion")
    promote.add_argument("--feed", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "assemble": assemble(args)
    elif args.command == "prepare": prepare(args)
    elif args.command == "hydrate": hydrate(args)
    elif args.command == "check-promotion": promotion(args)
    elif args.command == "verify": verify(args.archive, args.feed.read_bytes(), os.environ.get("MACSNAP_UPDATE_PUBLIC_KEY", ""), args.tag)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, ET.ParseError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        raise SystemExit(str(error))
