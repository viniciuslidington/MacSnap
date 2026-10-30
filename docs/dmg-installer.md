# Drag-to-Applications installer

## What changes for someone downloading MacSnap

The initial download becomes `MacSnap.dmg`. Opening it presents the real MacSnap icon, an arrow and a shortcut to `/Applications`, on a neutral background that follows the website's design. Instructions appear in English and Portuguese.

The user drags MacSnap to Applications, opens the installed copy and ejects the disk image. Downloading alone does not install the app. Finder handles the copy and any replacement or authorization prompt. This avoids leaving the runnable app in Downloads or running it from a read-only mounted image, which is unsuitable for updates.

The DMG changes packaging, not Apple's trust decisions. The app remains ad-hoc signed and is not notarized. Gatekeeper and Accessibility prompts may still appear. No quarantine attributes are removed and no security settings are changed by these scripts.

## Two artifacts, one application

- **MacSnap.dmg** is the initial Finder download.
- **MacSnap.app.zip** remains the EdDSA-authenticated Sparkle update and Terminal-install archive.

Both are created from the same signed app, including Sparkle and the clean-uninstall helper. Building the DMG does not modify or re-sign that app. Verification mounts the image read-only, recursively verifies code signatures, and compares every app file's bytes, permissions and symlink destination with the ZIP's extracted payload. It also checks compression, Finder layout, background and the exact Applications shortcut.

The disk image uses APFS and read-only LZFSE compression, compatible with the project's declared macOS 13 minimum. Runtime acceptance on Intel/macOS 13 remains deferred; creating the image is not evidence of those runtime tests.

## Build locally

First assemble a signed app using `scripts/update-distribution.py assemble`, as described in the update-distribution documentation. Then run from the repository root:

```bash
python3 -m venv .build/dmg-tools
.build/dmg-tools/bin/python -m pip install -r scripts/requirements-dmg.txt
.build/dmg-tools/bin/python scripts/build-dmg.py build \
  --app /absolute/path/to/MacSnap.app \
  --image /absolute/path/to/MacSnap.dmg
```

The output must not already exist. The script exposes the final DMG only after verification succeeds, and detaches its temporary mount in a `finally` block. It does not install or launch the app or change `/Applications`.

To check an existing DMG against the signed app extracted from its release ZIP:

```bash
.build/dmg-tools/bin/python scripts/build-dmg.py verify \
  --app /absolute/path/to/extracted/MacSnap.app \
  --image /absolute/path/to/MacSnap.dmg
```

Artwork is checked in at `Resources/Installer/background.png`, so release builds do not depend on local fonts. Regenerate it on macOS with `.build/dmg-tools/bin/python scripts/render-installer-background.py`. Finder metadata sets a 720 × 560 window, 112-point icons and fixed placements. On developer machines that show hidden files, internal artwork/icon files are positioned below the instructions rather than over them. Finder may retain user-wide path/status bars.

## Release and website rollout

1. **Prepare MacSnap Release** builds a universal signed app, ZIP, DMG, signed appcast and a `SHA256.txt` containing both artifact digests. It uploads an unpublished draft.
2. Rehearse the ZIP update and inspect the DMG installation before approval. No new release is created by local packaging.
3. **Publish Approved MacSnap Release** requires `tag`, the tested ZIP's `archive_sha256` and the tested installer's `dmg_sha256`. It checks both hashes, authenticates the ZIP, and proves the DMG contains the identical app before publishing.
4. Both public downloads must match the approved bytes. Only then does the workflow upload `update-approval.json`, now including `dmg_sha256`, and allow Pages deployment.
5. Pages hydration reads that verified receipt and the immutable, version-specific DMG asset URL. It renders both language routes with the DMG download and corresponding installation steps. Older receipts keep the ZIP fallback; merging these sources before publishing the DMG cannot introduce a missing DMG link.

The checked-in HTML intentionally describes the currently available ZIP. `scripts/build-site-locales.py` generates that baseline; deployment hydration selects the approved DMG variant without client-side JavaScript or an API call from visitors' browsers.

## Validation

`python3 scripts/test-dmg-distribution.py` covers fallback and approval policies, both languages, and rejection of missing/moved/unapproved DMG assets. Existing update policies and website checks still apply. The macOS CI job builds a signed app, creates a DMG and verifies it against a fresh extraction of the ZIP; release preparation repeats this with the universal production candidate.

Local verification includes a mounted DMG, actual Finder appearance and signed payload equality. The working installed app is not replaced. A clean-profile, quarantined download remains a separate release acceptance check.

References: [dmgbuild settings](https://dmgbuild.readthedocs.io/en/latest/settings.html), [Sparkle distribution guidance](https://sparkle-project.org/documentation/), [Sparkle archive guidance](https://sparkle-project.org/documentation/publishing/).
