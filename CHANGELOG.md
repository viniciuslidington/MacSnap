# Changelog

## [1.0.8] - Unreleased

### Added

- A branded, bilingual drag-to-Applications DMG installer, verified against the signed ZIP payload before publication; website downloads switch only after the DMG is approved and publicly verified.
- Clean uninstallation from the status menu or Terminal, with confirmation, a read-only preview and cleanup of settings, caches, startup entries and app-specific permissions.
- Sparkle updates from the status menu, with pending-version reminders, scheduled-check preferences and a separate automatic-download/install preference.
- EdDSA-authenticated universal update archives, draft release preparation and explicit approval before feed publication.
- Feed preservation across website deployments, stale-publication rejection and permanent withdrawal of affected builds.

### Changed

- Application shutdown waits for an active window drag or paired resize to finish.
- Bundle assembly includes Sparkle and its license; the public installer preserves the shipped signature without removing quarantine or re-signing the app.

### Release notes

- Version 1.0.7 users need one manual installation of the first updater-enabled release. Version 1.0.8 has not been published yet.
- Intel/macOS 13 execution testing is deferred to future user testing by the maintainer's decision. Universal slices and the declared macOS 13 minimum are verified; runtime compatibility remains unverified.
- A local full-MacSnap A → B rehearsal passed under a separate test identity. Production-identity Accessibility, clean-profile migration and login behavior still require acceptance checks. Fully unattended updates are not claimed.

## [1.0.7] - 2026-10-28

### Changed

- Menu icons, badges, and action buttons use neutral tones in light and dark mode; toggles retain the native accent color.

### Fixed

- Quick Snap and pairing action buttons no longer keep their hover highlight after a click or after closing and reopening the menu.

### Added

- Labeled Quick Snap and pairing action buttons support press actions from assistive technologies.
