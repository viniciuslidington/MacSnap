# Automatic updates for MacSnap

Research date: 2026-10-29. This is a proposal, not an implemented updater or an approved release plan.

## Recommendation

The user chose to keep annual costs at zero for now. Investigate Sparkle 2 with EdDSA-signed updates over HTTPS, keeping downloads on GitHub Releases and the feed in the existing GitHub Pages deployment. Start with a constrained ad-hoc-signed pilot and test real upgrades before offering automatic installation publicly. Sparkle itself is available without a licensing fee; retain its license and bundled notices. [Sparkle license](https://github.com/sparkle-project/Sparkle/blob/2.10.1/LICENSE)

Developer ID signing and notarization remain a possible future improvement, not a prerequisite imposed on this first phase. The free update-signing route does not remove Gatekeeper's first-install identity warnings. This document does not recommend bypassing them.

The verified current stable release is Sparkle 2.10.1. Its package contains a binary target and declares macOS 12 as its minimum, below MacSnap's macOS 13 floor. This establishes a plausible compatibility baseline, not a successful build with this project's Xcode 16 release toolchain. Pin and test a specific release rather than assuming the package alone completes integration. [Release](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1), [tagged package manifest](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Package.swift)

## What exists today

These findings come from this checkout:

| Area                                                      | Current behavior                                                                                    | Implication                                                                                                              |
| --------------------------------------------------------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| [Package.swift](../../Package.swift)                       | A Swift executable and tests, no package dependencies                                               | No updater is currently linked                                                                                           |
| [Info.plist](../../Resources/Info.plist)                   | Version 1.0.7, build 7, bundle identifier `com.viniciuslidington.MacSnap`, `LSUIElement = true` | Preserve app identity; increment the build for updates                                                                   |
| [AppDelegate](../../Sources/MacSnap/App/AppDelegate.swift) | Creates the menu, requests Accessibility access and starts event monitoring                         | A retained updater controller can be owned at app composition time                                                       |
| [Release workflow](../../.github/workflows/release.yml)    | Builds Intel/Apple silicon, assembles the bundle, ad-hoc signs it, uploads a ZIP                    | Framework embedding, distribution signing and feed publication are missing                                               |
| [Public installer](../../install.sh)                       | Downloads the release, removes quarantine and re-signs the installed app ad-hoc                     | It would overwrite a future Developer ID signature; revise this path before signed distribution                          |
| [Local build installer](../../scripts/install.sh)          | Compiles locally and signs using a local development certificate when available                     | Keep development installation separate from the public artifact's trust model                                            |
| [Pages workflow](../../.github/workflows/pages.yml)        | Publishes only `site/`                                                                            | An appcast must be included in that deployed artifact, or be deployed through a separate coordinated update-feed process |

The installer finding is material: replacing a shipped signature on the recipient's Mac defeats the intended distribution identity. The production installer should copy and validate the released app without re-signing it or routinely removing quarantine. No installer changes were made during this research.

## How an update reaches the user

```text
Maintainer publishes a tested release
  → version-specific ZIP on GitHub Releases
  → update-feed entry with build number and archive signature
  → MacSnap checks the feed
  → Sparkle downloads and verifies the update
  → install/relaunch through Sparkle's update flow
```

Sparkle reads an appcast, an RSS-style update feed, through `SUFeedURL`. Its setup uses a public EdDSA key in `SUPublicEDKey`; private signing material stays with the publisher. HTTPS, archive signatures and Apple distribution signing serve complementary purposes. An EdDSA signature authenticates the update archive; it does not give the first download Apple's Developer ID identity or notarization status. [Sparkle setup and security guidance](https://sparkle-project.org/documentation/)

Keep a recoverable backup of the private EdDSA key outside the public repository; only the public key belongs in the app. If release signing moves to GitHub Actions, expose the private key only to a trusted release job, never pull-request builds or downloadable artifacts. Sparkle's documented key-rotation fallback relies on Developer ID signing, so the free track must not assume that losing its signing key is recoverable through an ordinary automatic update. [Key storage and rotation](https://sparkle-project.org/documentation/#eddsa-ed25519-signatures)

Proposed feed URL: `https://viniciuslidington.github.io/MacSnap/updates/appcast.xml`. This URL does not exist as part of the current implementation. GitHub Pages supplies static hosting; GitHub Releases hosts versioned downloadable binaries. This combination is an architectural proposal based on those capabilities, without a new application server. [GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages), [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)

Use a release-specific archive URL, such as `/releases/download/vX.Y.Z/MacSnap.app.zip`, in the feed. Keep `/releases/latest/download/...` for the website's initial-download button. This proposed policy keeps the feed's signature and size tied to fixed archive bytes. Never replace the bytes behind a version that clients have already been offered.

## “Automatic” has two separate settings

Sparkle distinguishes automatic checking from automatic downloading/installing. `SUEnableAutomaticChecks` enables checks; `SUAutomaticallyUpdate` changes the default for background download and installation. Checks default to a daily schedule. A silent installation is not guaranteed: authorization may be required, and an app that stays open for a long time can still need a prompt to complete installation. Defaults should be configured through the plist; runtime settings respond to the user's choices. [Sparkle customization](https://sparkle-project.org/documentation/customization/)

Recommended first experience for MacSnap:

1. Let the user enable automatic update checks and choose automatic download/install.
2. Always provide **Check for Updates…** in the status-bar menu.
3. Offer **Install and Relaunch** when appropriate, instead of requiring a browser download, unzip and manual app replacement.
4. Make a pending update discoverable without interrupting window management.

Because MacSnap is dockless and can stay running for days, this last step matters. Sparkle documents gentle reminder APIs for background apps; scheduled update alerts normally avoid stealing another app's focus after launch. Implement an unobtrusive status-menu indicator using those hooks, while keeping the standard update UI available. A Notification Center message alone is insufficient because delivery/visibility is not guaranteed. [Gentle update reminders](https://sparkle-project.org/documentation/gentle-reminders/)

## Integration work specific to this repository

This is a proposed implementation breakdown:

- Keep update coordination out of snap geometry, drag monitoring and paired-resize logic. A small app-level update service can own the retained `SPUStandardUpdaterController` and expose manual-check availability to the menu. Sparkle's programmatic Cocoa example supplies this controller and the menu target/action. [Programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/)
- Add the package dependency, then extend bundle assembly to include `Sparkle.framework` under `Contents/Frameworks`, preserve symlinks/executable permissions, and supply the framework runpath. Linking a SwiftPM executable alone should not be treated as proof that the manually assembled `.app` embeds everything. [Framework integration](https://sparkle-project.org/documentation/)
- Review the retained Sparkle helper apps, tools and XPC services, then framework and host, in the custom signing/packaging process. The ad-hoc pilot must validate framework loading and helper execution, including the prebuilt helpers' Hardened Runtime behavior. Do not assume the current blanket `--deep` command is sufficient, or weaken production library validation to make it work. Sparkle documents inside-out signing for custom distribution; signing only the framework does not re-sign all helpers. [Sparkle signing guidance](https://sparkle-project.org/documentation/sandboxing/#code-signing)
- Add the feed/public-key settings and retain the existing bundle identifier. Preserve preferences and launch-at-login behavior. Treat continued Accessibility authorization as a release acceptance test, not a promise: the ad-hoc-to-Developer-ID transition especially needs testing on an existing installation.

## Release pipeline proposal

1. Build/test the universal app and verify tag, display version and increasing internal build agree.
2. Embed and sign the framework and host consistently for the ad-hoc pilot. If Developer ID distribution is adopted later, notarize and staple before producing the final archive.
3. Package without breaking framework symlinks; Sparkle recommends `ditto` for ZIP archives.
4. Generate the signed appcast from the final artifact, with final release-specific download URLs. `generate_appcast` produces signatures; the feed carries build/display versions, length and enclosure information.
5. Upload the artifact, verify it is downloadable, then publish the feed last. Serialize release publication so concurrent releases cannot overwrite a newer feed with older data. A failed build/upload should leave the previous feed intact. Include the feed in the existing Pages artifact so a later marketing-site deployment cannot remove it.

Sparkle's publishing documentation covers archive construction, generated signatures and separate machine/display version values. Feed publication order and immutable artifact policy above are proposed operational safeguards. [Publishing updates](https://sparkle-project.org/documentation/publishing/)

For incidents, stop offering the affected build and publish a fixed build with a higher build number. Removing a feed item cannot undo an update already installed. Start with full archives; delta updates are unnecessary for the first working update channel.

## Signing, cost and migration

Sparkle's update signing does not itself require purchasing an Apple membership. Developer ID distribution and notarization are a separate future track; they are deferred under the user's zero-annual-cost decision. The Apple Developer Program currently costs US$99 per year, with regional pricing variation. Revisit the account and intended identity only if that decision changes. [Apple enrollment](https://developer.apple.com/help/account/membership/program-enrollment/)

The current **1.0.7 cannot acquire an updater merely because we publish a newer feed**: the installed binary contains no updater. Existing users must install the first updater-enabled release once through the normal download or installer. Subsequent releases can use Sparkle. This is an inference directly from the current package and app startup code, not a limitation a website change can solve.

Recommendation: prepare and test the updater-enabled release before directing a large LinkedIn audience to the download. If promotion happens earlier, explain that one later manual upgrade will be necessary.

## Alternatives

| Option                                 | Fit for MacSnap                                                                                                                                                                                                                                                                                                                                                                       |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sparkle + existing GitHub distribution | Recommended: the app manages its own update experience while retaining current hosting                                                                                                                                                                                                                                                                                                |
| Mac App Store                          | Outside the current cost decision. Store-distributed apps must be sandboxed and use the store for updates. MacSnap's cross-application Accessibility behavior would require a separate feasibility review; do not assume approval or assert impossibility from this research. [Apple guideline 2.4.5](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility) |
| Homebrew cask                          | Useful as an additional technical-user channel. `auto_updates true` describes an app that already updates itself; it does not add an updater to today's ZIP downloads. [Cask cookbook](https://docs.brew.sh/Cask-Cookbook#stanza-auto_updates)                                                                                                                                       |
| Custom updater                         | Possible engineering work, but would make this project responsible for download trust, replacement/relaunch, interruption recovery, permissions and update UI. That is a larger ownership commitment than using Sparkle; not recommended for this small app                                                                                                                           |

## Acceptance tests before announcing automatic updates

These are required proposed tests, not results already obtained:

- Install two real successive ad-hoc-signed release bundles, then update from the older one through the actual updater. Exercise both Intel and Apple silicon and the supported macOS floor/current OS. The free path is not validated until this succeeds, including framework loading and helper execution.
- Check manual and scheduled flows, opt-in/out, offline recovery, failed downloads, wrong signatures and incompatible OS versions.
- Verify the installed signature, restart behavior, preferences and launch at login survive the update. Inspect actual Gatekeeper behavior on a clean profile without removing quarantine. If the paid track is adopted later, test Developer ID and notarization assessment too.
- Test a long-running dockless app: pending update remains discoverable without stealing focus, and an active resize/drag is not interrupted by a forced restart.
- Test installation in `/Applications`, limited write permissions and launching from an extracted/downloaded location. Do not claim a completely silent flow where macOS authorization is required.
- Test an existing 1.0.7 installation moving manually to the first updater-enabled build, then updating through Sparkle. Re-check Accessibility access after both steps; ad-hoc signing can make this a material limitation, so do not promise permission persistence. If a new signing identity is introduced later, test that migration separately.
- Keep a staging feed separate from production; publish the production feed only after the exact signed archive passes end-to-end checks.

No dependencies were installed, keys generated, Apple account changed, app code modified, release uploaded or PR opened for this research.
