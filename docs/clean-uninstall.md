# Clean uninstallation

The new clean-uninstall feature is available in source on `codex/clean-uninstall`. It has not been installed over the maintainer's working MacSnap, published, or merged. Older builds without the bundled helper do not display the new menu action.

## From the app

Choose **Uninstall MacSnap…** in the status menu. The confirmation defaults to **Cancel**. Choosing **Uninstall** closes MacSnap normally, moves that installed app to Trash and removes its preferences, caches, legacy startup entry and privacy permissions. A result dialog reports success or anything that still needs attention.

Finish or dismiss any update first. A ready-to-install background update also blocks uninstallation; complete that update and reopen the app before retrying. The uninstall handoff prevents new update checks while the app quits. The helper waits for normal shutdown and refuses to proceed while another MacSnap instance or a related update process is still active.

The app must be in `/Applications/MacSnap.app` or `~/Applications/MacSnap.app`. Source checkouts, development builds, signing keys, documents, unrelated apps and other users' settings are outside the removal plan. Other copies in developer folders are not searched or deleted.

## From Terminal

Quit MacSnap first. Preview the exact removal plan without changing anything:

```bash
./install.sh --uninstall --dry-run
```

Then run interactively and type **UNINSTALL** when asked:

```bash
./install.sh --uninstall
```

From a source checkout, `./scripts/uninstall.sh --dry-run` and `./scripts/uninstall.sh` use the same native helper. The source wrapper builds only the helper if it is not installed. A packaged app also exposes it directly:

```bash
/Applications/MacSnap.app/Contents/Helpers/MacSnapUninstaller --dry-run
```

`--app "$HOME/Applications/MacSnap.app"` selects a per-user installation. `--yes` is explicit noninteractive confirmation; never add it to a preview command to imply that removal has been tested. Preview always remains read-only.

If the app has already been deleted, the remote installer can download a signed helper from the latest release once a release includes this feature. The current public 1.0.7 archive does not contain it; a source checkout can provide the helper meanwhile. Older builds cannot unregister their modern login item through the new app command, so the helper reports that remaining check in System Settings instead of claiming complete removal.

## Safety and verification

`MacSnapUninstallation` owns the bounded removal plan and filesystem cleanup. The app provides native confirmation and normal shutdown; the separate `MacSnapUninstaller` executable finishes after the app exits. It uses macOS system tools without requiring Python, Xcode or administrator elevation in a packaged distribution.

The plan validates the bundle identifier and installation location before any removal and validates again after confirmation. Symbolic links cannot redirect cleanup into another directory. A legacy startup file must have MacSnap's label and executable path. A failed application-to-Trash operation leaves the settings files intact. OS cleanup failures are reported as incomplete rather than silently ignored.

Tests exercise real temporary app/settings fixtures with a controlled OS adapter: successful cleanup, preserved project/key/other-app files, cancellation, update contention, changed identity, symbolic links, a failed Trash operation, and residual settings after app deletion. Native menu actions are exercised through AppKit. The CLI preview and universal helper packaging are checked separately. Actual uninstallation of the maintainer's working app is deliberately not used as a development test.

After reinstalling, macOS may request Accessibility again because clean removal resets that application's permissions. Historical entries in macOS background-item databases are OS-managed; the uninstaller does not reset global registries or permissions for other applications.
