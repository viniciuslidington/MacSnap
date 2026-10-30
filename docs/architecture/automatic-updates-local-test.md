# Test an update before merging

The updater reads an appcast and downloads its signed archive. It does not require the source branch to be merged into `main`, a public release, or a production-feed deployment. This local rehearsal uses the full MacSnap source from the working branch.

## Prepared session

The disposable session is `.build/update-staging.5qeee33n/`. Build A is 1.0.8/build 8; build B is 1.0.9/build 9. These are test identities, not public releases. The production `Resources/Info.plist` stays at candidate 1.0.8/build 8.

Both apps use the separate bundle identifier `com.viniciuslidington.MacSnap.UpdateTest` and the display name **MacSnap Update Test**. Their executables were compiled independently, with distinct A/B diagnostic markers. The session includes the expected binary digests and ZIP SHA-256 in `verification.json`.

## Completed result — 2026-10-29

The maintainer reported: “funcionou tudo certinho”. A subsequent read-only inspection confirmed that the installed bundle is 1.0.9/build 9, its executable is byte-for-byte the independently compiled B candidate, and its recursive code signature verifies. The local receipt now records `update_executed: true` and the successful installed-binary/signature checks.

- B archive SHA-256: `5cec1a47cc83158433a3b0b7656f1b1e5cf2ce50f5ef87873490ef7dd7226467`.
- Installed B executable SHA-256: `e347dfd85f1d68aab7754eb7800f6dddadbc70e6cfaf858a10da5c70f3733797`.

This records a successful native full-app update rehearsal, with the maintainer's functional confirmation. It does not infer unreported Accessibility prompts, launch-at-login behavior or clean-profile migration from a general success report. The scope limits below continue to apply.

Test-only source copies register a loopback feed in the process's defaults registration domain on each launch. The app's production updater implementation remains unchanged, and no production preference is written. Only the disposable test bundle permits local networking. Sparkle's archive-signature verification stays enabled. The archive was signed with a disposable test key, verified, and its private seed was deleted. Production keys and the Keychain were not read.

## Run the rehearsal

1. Quit the currently running MacSnap from its menu so two window managers do not handle the same gestures. The installed `/Applications/MacSnap.app` is not replaced by this rehearsal.
2. In Terminal, start the local server and keep the Terminal session open:

   ```bash
   cd /Users/viniciuslidington/Projects/MacSnap
   python3 -m http.server 53722 --bind 127.0.0.1 \
     --directory .build/update-staging.5qeee33n/downloads
   ```

   Only the `downloads` folder is served; the source copies and verification records are outside the served directory.
3. In another Terminal tab, open build A:

   ```bash
   open /Users/viniciuslidington/Projects/MacSnap/.build/update-staging.5qeee33n/installed/MacSnap.app
   ```

4. In the status menu, confirm **MacSnap v1.0.8**. If testing actual window operations, authorize **MacSnap Update Test** through the normal Accessibility settings flow. This is a distinct app grant; record any prompt instead of assuming authorization.
5. Change a harmless preference, such as the top layout bar toggle, and note its state. Leave launch-at-login disabled for the disposable test app.
6. Choose **Check for Updates…**. The offer should identify 1.0.9 and state that it is a local rehearsal. Install it through Sparkle and allow the app to restart.
7. Confirm **MacSnap v1.0.9**, the saved preference and functional snapping/paired resizing. Record the Accessibility state before/after; restore it only through the normal settings flow if required. After updating, another manual check should report no newer version.
8. Quit **MacSnap Update Test**, stop the local server with Control-C, then reopen the normal installed MacSnap.

Keep the session's `verification.json` and record the observed result. A preparation receipt with `update_executed: false` is not evidence that the native update has completed. Compare the installed executable with the B candidate when collecting completion evidence.

## What this establishes

Successful execution exercises the full app-level updater/menu and real Sparkle download, EdDSA verification, replacement, relaunch and per-app preferences on the tested machine. It also lets the maintainer observe Accessibility changes across two ad-hoc test builds.

This does not verify the production signing pair, public HTTPS delivery, the manual 1.0.7 bootstrap, grant persistence for the production bundle identifier, Intel/macOS 13 execution or a clean-profile installation. The distinct identity is intentional so the production app and its preferences are preserved. Use the trusted candidate workflow and the documented release acceptance process for those remaining checks.

Primary references: [Sparkle update publishing](https://sparkle-project.org/documentation/publishing/) and [configuration options](https://sparkle-project.org/documentation/customization/).
