#!/usr/bin/env python3
"""Build and verify a drag-to-Applications disk image of an already signed app."""
import argparse
from contextlib import contextmanager
import hashlib
import os
from pathlib import Path
import plistlib
import stat
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
APP_NAME = "MacSnap.app"
LOCATIONS = {APP_NAME: (184, 252), "Applications": (536, 252),
             # Developer Macs may show hidden files. Keep these away from the instructions.
             ".background.png": (184, 900), ".VolumeIcon.icns": (536, 900)}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(*command):
    return subprocess.run(command, check=True, stdout=subprocess.PIPE).stdout


def validate_app(app):
    require(app.name == APP_NAME and not app.is_symlink(), "Expected a real MacSnap.app bundle")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    require(info.get("CFBundleIdentifier") == "com.viniciuslidington.MacSnap", "Unexpected app identity")
    run("/usr/bin/codesign", "--verify", "--strict", "--deep", str(app))


def manifest(app):
    """Compare every payload byte, executable bit and framework symlink, without following links."""
    result = {}
    for path in sorted(app.rglob("*")):
        mode = path.lstat().st_mode
        name = path.relative_to(app).as_posix()
        if stat.S_ISLNK(mode):
            result[name] = ("link", os.readlink(path))
        elif stat.S_ISREG(mode):
            result[name] = ("file", stat.S_IMODE(mode), hashlib.sha256(path.read_bytes()).hexdigest())
        else:
            require(stat.S_ISDIR(mode), f"Unsupported app entry: {name}")
            result[name] = ("directory", stat.S_IMODE(mode))
    return result


@contextmanager
def mounted(image):
    with tempfile.TemporaryDirectory(prefix="macsnap-dmg-check-") as folder:
        mount = Path(folder) / "volume"
        mount.mkdir()
        run("/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(image))
        try:
            yield mount
        finally:
            run("/usr/bin/hdiutil", "detach", str(mount))


def verify(image, app):
    from ds_store import DSStore
    validate_app(app)
    details = plistlib.loads(run("/usr/bin/hdiutil", "imageinfo", "-plist", str(image)))
    require(details.get("Format") == "ULFO", "Expected a read-only LZFSE-compressed disk image")
    run("/usr/bin/hdiutil", "verify", str(image))
    with mounted(image) as volume:
        visible = {p.name for p in volume.iterdir() if not p.name.startswith(".")}
        require(visible == {APP_NAME, "Applications"}, "Unexpected visible installer contents")
        link = volume / "Applications"
        require(link.is_symlink() and os.readlink(link) == "/Applications", "Missing Applications shortcut")
        installed = volume / APP_NAME
        validate_app(installed)
        require(manifest(app) == manifest(installed), "DMG app differs from the approved ZIP payload")
        require((volume / ".background.png").read_bytes() ==
                (ROOT / "Resources/Installer/background.png").read_bytes(), "Installer artwork differs")
        with DSStore.open(str(volume / ".DS_Store"), "r") as store:
            for name, location in LOCATIONS.items():
                require(tuple(store[name]["Iloc"]) == location, f"Incorrect Finder placement: {name}")
            require(store["."]["icvp"]["backgroundType"] == 2, "Missing Finder background")
            require(store["."]["icvp"]["iconSize"] == 112, "Incorrect Finder icon size")
            require(store["."]["bwsp"]["ShowToolbar"] is False, "Unexpected Finder toolbar")
    print("PASS: read-only DMG, Finder layout, Applications shortcut and exact signed app payload.")


def build(image, app):
    import dmgbuild
    validate_app(app)
    require(not image.exists(), "Output already exists; choose a new path")
    require(image.suffix == ".dmg", "Output must end in .dmg")
    require(not image.is_relative_to(app), "Output must be outside the app bundle")
    image.parent.mkdir(parents=True, exist_ok=True)
    # Build to a temporary name, exposing only a successfully verified image.
    with tempfile.TemporaryDirectory(prefix="macsnap-installer-", dir=image.parent) as folder:
        candidate = Path(folder) / "MacSnap.dmg"
        dmgbuild.build_dmg(str(candidate), "MacSnap", settings={
            "files": [str(app)],
            "symlinks": {"Applications": "/Applications"},
            "format": "ULFO", "filesystem": "APFS",
            "background": str(ROOT / "Resources/Installer/background.png"),
            "icon": str(app / "Contents/Resources/AppIcon.icns"),
            "icon_locations": LOCATIONS, "icon_size": 112, "text_size": 14,
            "window_rect": ((180, 140), (720, 560)),
            "default_view": "icon-view", "arrange_by": None,
            "show_toolbar": False, "show_sidebar": False,
            "show_status_bar": False, "show_pathbar": False,
            "show_tab_view": False, "show_icon_preview": False,
        })
        verify(candidate, app)
        candidate.rename(image)
    print(f"Created {image}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["build", "verify"])
    parser.add_argument("--app", type=Path, required=True, help="The exact signed app also archived in the ZIP")
    parser.add_argument("--image", type=Path, required=True)
    args = parser.parse_args()
    app = args.app.absolute()
    image = args.image.resolve()
    if args.command == "build":
        build(image, app)
    else:
        verify(image, app)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
