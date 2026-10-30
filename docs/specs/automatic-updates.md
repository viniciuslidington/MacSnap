Automatic in-app updates for MacSnap

## Problem Statement

People who download MacSnap currently have to discover each new release, download a ZIP, quit the running app and replace it manually. This becomes an ongoing burden after the website and LinkedIn introduction bring in users who do not follow the repository.

The current 1.0.7 release has no updater. Publishing a new website or update feed cannot give that installed binary the ability to update itself. MacSnap is also a dockless app that may run continuously, so an update prompt hidden behind other windows is not a sufficient discovery mechanism.

The maintainer wants a sustainable update channel without an annual Apple Developer Program subscription. The existing ad-hoc distribution does not establish an Apple Developer ID identity or notarization status, and continued Accessibility authorization across updates has not been demonstrated.

## Solution

Integrate Sparkle 2 into the native app and use the existing GitHub distribution: version-specific archives on GitHub Releases and a stable HTTPS update feed hosted with GitHub Pages. Users can check manually from the menu, consent to scheduled checks and opt into automatic downloading and installation. Installation and relaunch happen through the updater instead of requiring a browser download and manual replacement.

Use EdDSA signatures to authenticate update archives, with the public key embedded in MacSnap and the private key retained by the publisher. Keep the first implementation free of an annual subscription. This update signature does not remove first-install Gatekeeper warnings or establish Apple notarization.

First prove the proposed ad-hoc packaging and update path with two real application bundles. Only advertise automatic updates after the release acceptance tests pass. Existing 1.0.7 users need one manual installation of the first updater-enabled release; new users should receive that release directly when the feature is announced.

## User Stories

1. As a MacSnap user, I want to receive new versions inside the app, so that I do not have to visit GitHub for every release.
2. As a new user, I want the downloaded app to include the updater, so that subsequent releases do not require manual replacement.
3. As an existing 1.0.7 user, I want clear instructions for the one manual upgrade, so that I understand when in-app updates become available.
4. As a user, I want a discoverable Check for Updates… menu action, so that I can look for a fix whenever I need one.
5. As a user, I want automatic update checks to be a clear preference, so that I control scheduled network access.
6. As a user, I want automatic downloading and installation to be a separate choice, so that checking for updates does not silently change my installation preferences.
7. As a user, I want my update preferences remembered, so that I do not have to choose them on every launch.
8. As a user, I want confirmation that my app is current after a manual check, so that I know the action completed.
9. As a user, I want to see the available version and release notes, so that I understand what is changing.
10. As a user, I want to postpone an update, so that I can continue my current work.
11. As a user who enabled automatic updates, I want eligible releases downloaded and installed through the updater, so that I can avoid repetitive installation steps.
12. As a user, I want a clear install-and-relaunch action when needed, so that I can complete an update at a convenient time.
13. As a user of a dockless app, I want pending updates visible in the status menu, so that I can find them without a Dock icon.
14. As a user, I want background update reminders to avoid stealing focus, so that window management remains unobtrusive.
15. As a user performing a Drag Gesture or Resize Operation, I want installation to wait for a safe point, so that an update does not interrupt an active interaction.
16. As a user, I want the updated app to relaunch correctly, so that window management is available again after installation.
17. As a user, I want my preferences and launch-at-login behavior preserved, so that updating does not change my configuration.
18. As a user, I want honest guidance if Accessibility authorization needs attention after an update, so that I can restore window management without guessing.
19. As a user, I want the current app to keep working when I am offline, so that an update check does not block snapping or resizing.
20. As a user, I want a useful result when a manual check or download fails, so that I can retry without reinstalling the app.
21. As a user, I want a damaged or incorrectly signed update rejected, so that untrusted code does not replace my installed app.
22. As a user, I want updates incompatible with my macOS version excluded, so that a working installation is not replaced with an unusable one.
23. As an Intel Mac user, I want the update channel to deliver a compatible app, so that I receive the same maintenance as Apple silicon users.
24. As an Apple silicon user, I want the update channel to preserve native compatibility, so that updates do not require switching architecture.
25. As a user with limited installation permissions, I want any required authorization explained, so that I understand why installation cannot be completely silent.
26. As a user running MacSnap from an unsuitable location, I want actionable installation guidance, so that I can move it to a supported location and update normally.
27. As a user, I want a rejected or interrupted update to leave a usable installed app, so that a failed update does not disable MacSnap.
28. As a user, I want the app to retain its recognizable identity across releases, so that updates replace the intended application.
29. As a maintainer, I want the update channel to use existing GitHub hosting without an annual Apple subscription, so that the distribution matches the project's current budget.
30. As a maintainer, I want the release artifact and feed generated from the same final bytes, so that clients verify exactly the package I tested.
31. As a maintainer, I want private signing material excluded from the public repository and PR jobs, so that contributors can work without gaining release-signing access.
32. As a maintainer, I want a recoverable backup of the update-signing key, so that losing one machine does not unnecessarily break the installed update channel.
33. As a maintainer, I want the release process to reject inconsistent versions or non-increasing builds, so that clients reliably detect newer releases.
34. As a maintainer, I want a failed build, upload or feed deployment to leave the last working feed intact, so that existing installations remain supported.
35. As a maintainer, I want release publication serialized, so that an older run cannot overwrite a newer update announcement.
36. As a maintainer, I want marketing-site deployments to preserve the update feed, so that routine website changes do not disable updates.
37. As a maintainer, I want a staging feed and real A → B update evidence, so that I can verify a release before offering it to the public.
38. As a maintainer, I want to withdraw a faulty offer and publish a higher-build fix, so that I can respond to a bad release without pretending already installed updates were undone.
39. As a maintainer, I want a single app-level updater boundary, so that update behavior can be tested without coupling Sparkle to Snap Zones, Snap Intent or Pair geometry.
40. As a prospective user reading the English or Portuguese website, I want accurate update instructions, so that the advertised behavior matches the downloadable app.

## Implementation Decisions

1. **Distribution and budget.** Use Sparkle 2, EdDSA-signed archives and HTTPS with the existing GitHub Releases and Pages services. Do not require Apple Developer Program enrollment, a new paid updater service or a custom application server. Preserve Sparkle's license and required notices.
2. **Feasibility gate first.** Pin a reviewed Sparkle 2 release and prove that it can be linked, packaged, loaded and used to update two real ad-hoc-signed bundles with MacSnap's supported toolchain. Successful dependency resolution or a unit-test run alone does not satisfy this gate. Do not silently substitute a paid signing requirement or weaken platform protections if this route fails; document the failure and revisit the decision.
3. **One application boundary.** Introduce one app-level update service boundary, owned by app composition and implemented through Sparkle's retained standard updater controller. Expose manual checking, check availability, update preferences and the user-visible pending-update state. Keep Sparkle types and callbacks inside this integration rather than spreading them through window-management modules.
4. **Menu integration.** Reuse the menu controller's dependency-injection pattern. Add Check for Updates… and a discoverable pending-update indication. Disable duplicate or unavailable check actions based on the update service's state. Do not disable updating merely because the user paused snapping.
5. **Consent and preferences.** Use Sparkle's supported consent flow for scheduled checks and expose automatic download/install as a separate opt-in. Avoid stacking a new update-consent dialog onto the first-launch Accessibility request. Preserve the user's choices; use supported configuration for defaults rather than rewriting preferences on each launch.
6. **Scheduling and UI.** Delegate update scheduling, version comparison, download, verification, installation and relaunch to Sparkle. Begin with its normal daily scheduled-check policy. Use its gentle-reminder hooks for the dockless app and keep the standard update UI available. A system notification must not be the sole way to discover a pending update.
7. **Safe installation point.** Background download must not force application termination during an active Drag Gesture or Resize Operation. Connect installation readiness to the existing app/gesture lifecycle, defer relaunch while an interaction is active, and use the normal application shutdown cleanup. Do not redesign Snap Intent, Pair formation or Split Ratio calculations for this feature.
8. **Packaging.** Extend application-bundle assembly to embed Sparkle's framework and required helpers, with self-contained runtime paths, preserved symlinks and executable permissions. Validate the final extracted app, not just the build directory. Review nested-component signing explicitly instead of assuming a blanket deep-signing command packages the framework correctly.
9. **Application identity.** Keep the existing application name and bundle identifier. Use monotonically increasing internal build numbers independently from the user-facing version. Validate tag, displayed version and internal build consistency before publishing. Do not change preferences or launch-at-login identity as a side effect of adding updates.
10. **Archive authentication.** Embed only the public EdDSA key in the app. Sign the exact final update archive and reject unauthenticated archives before they can replace the installed app. Preserve normal verification and transport protections; do not introduce an insecure fallback when validation fails.
11. **Key custody.** Keep private signing material and a recoverable backup outside the repository, application and downloadable artifacts. Any CI signing access belongs only in a trusted, explicitly controlled release job, never ordinary pull-request builds. Plan key custody before bootstrapping the public channel; the free route must not assume that a lost key can be recovered through Developer ID-based rotation.
12. **Public installer behavior.** The production installer must preserve the published bundle instead of re-signing it after download. Remove routine quarantine removal from that distribution path and retain truthful first-install guidance. Keep development builds and local development installation separate from the production update trust model.
13. **Feed contract.** Configure a stable production HTTPS appcast and a separate staging feed. Entries must describe the internal build, displayed version, release-specific download URL, archive length, EdDSA signature, release notes and applicable minimum macOS version. Never put a moving latest-release download URL into a signed update entry.
14. **Artifact policy.** Start with complete universal archives for Intel and Apple silicon. Preserve the already offered bytes at each release-specific URL. A correction requires a new build and release rather than replacing an archive that clients may already have downloaded or verified.
15. **Publication order.** Build and test, assemble and validate the app, create the final archive, generate update metadata/signatures, upload the archive, verify the final download, then publish the feed. Fail closed on missing keys, invalid signatures, inconsistent versions or unavailable artifacts. Build/upload failure must not advance the public feed.
16. **Pages ownership.** Include the production appcast and any referenced release notes in the coordinated Pages deployment artifact. A normal landing-page deployment must retain them. Serialize release/feed promotion and guard against stale runs replacing a newer feed, including races between website and release workflows.
17. **Promotion and incidents.** Exercise the exact candidate archive against staging before announcing it in production. Preserve the last working feed during unsuccessful promotion. Withdrawing an offer prevents future offers but does not roll back installations already completed; publish fixes with a higher build number. Keep explicit human release approval and the existing policy against automatically opening PRs without authorization.
18. **Migration.** Document the one manual bootstrap from 1.0.7 to the first updater-enabled release. Do not assign a release version in this spec or claim that a feed/site change upgrades older binaries. Update English and Portuguese website instructions only when the advertised updater-enabled artifact is actually available.
19. **Accessibility acceptance.** Preserve application identity and preferences, but do not assert that Sparkle's archive signature preserves macOS Accessibility grants. Measure the result for both the manual bootstrap and a subsequent in-app update. The free-path pilot must record any reauthorization needed and provide recovery guidance. Unexpected loss of permission blocks claims of unattended updates until resolved or explicitly accepted with documented product limits.
20. **No guaranteed zero-click installation.** Respect macOS write authorization and Sparkle's supported install/relaunch flow. The first release must support updates without manual browser downloading; it must not promise that every installation is silent or needs no Accessibility confirmation.

## Testing Decisions

1. **Confirmed test boundary.** The user approved one new boundary between MacSnap and the updater, exercised through menu actions and externally visible update state, plus real A → B application-update acceptance tests. Prefer this application-level seam to separate mock interfaces for networking, file replacement, version parsing, signature checking or relaunch.
2. **Good automated tests.** Drive a user action or supported updater event and assert an observable outcome: available menu actions, pending-update presentation, persisted choices, whether a check was requested, and whether installation is deferred during a Drag Gesture or Resize Operation. Do not assert private flags, callback order, exact SDK call counts or Sparkle's internal algorithms.
3. **Application integration coverage.** Use a controlled updater implementation behind the single boundary to cover checking, no update, update available, failed check/download, installation eligibility, cancelled/deferred installation and recovery. Check duplicate actions, unavailable states and manual checking while snapping is paused. Use an isolated preferences store so tests do not change a developer's installed configuration.
4. **Existing test precedents.** Follow the existing Swift Testing/AppKit menu tests that inject native collaborators and drive real controls through mouse or accessibility actions. Reuse the existing gesture and paired-resize fixtures and controlled scheduling where needed to prove that installation does not interrupt window interactions. Do not introduce an additional scheduler abstraction just to duplicate Sparkle's scheduling.
5. **Distribution validation.** Check assembled/extracted framework and helper presence, executable permissions, symlink preservation, self-contained runtime dependencies, supported architectures, bundle identity and signatures. Validate generated appcast metadata against the final downloadable archive. Prove that a marketing-site deployment retains the feed and that stale or failed publication cannot advance/regress it. Use temporary artifacts or staging rather than publishing test updates to production.
6. **Real upgrade gate.** Install a genuine older updater-enabled app in a disposable test profile, grant Accessibility, create representative preferences and launch-at-login state, then install a genuinely newer build through Sparkle. Verify the installed version, relaunch, menu availability, actual snapping/resizing, preferences, login behavior and observed Accessibility state. Repeat the manual 1.0.7 bootstrap followed by an in-app update. Stubbed SDK events and edited version metadata alone are insufficient.
7. **Compatibility and failure cases.** Exercise Intel and Apple silicon, the supported macOS floor and a current supported release. Include scheduled/manual checks, opted-out checks, opted-in automatic installation, a long-running dockless app, offline recovery, interrupted downloads, wrong signatures, older/equal build offers, incompatible macOS requirements, limited write permissions and unsuitable launch locations. A rejected update must not replace the app with unverified bytes or leave it unusable.
8. **Evidence before promotion.** Record candidate build identity, architecture, macOS version, install location, update path and all observed authorization prompts. Mark untested combinations as untested. Public claims and automatic-install promotion are gated on the actual signed/ad-hoc artifact path being demonstrated, not only on automated tests passing.

## Out of Scope

- Buying or configuring an Apple Developer Program membership, Developer ID certificates or notarization for this first phase.
- Mac App Store distribution, Homebrew cask distribution or a custom updater engine.
- A custom backend, user accounts, billing, analytics or system profiling.
- Delta updates, multiple public release channels, beta enrollment or a staged percentage rollout.
- Automatic downgrades, guaranteed recovery after losing the signing key, or retroactively installing an updater into 1.0.7.
- Guaranteed silent installation or guaranteed preservation of Accessibility authorization across ad-hoc builds.
- Bypassing Gatekeeper, disabling platform security protections, or changing the architecture of snapping, window discovery and paired resizing.
- Implementing the feature, generating keys, changing account/security settings, publishing a release, posting on LinkedIn or merging a PR merely by publishing this spec.

## Further Notes

- Implementation follow-up: the maintainer explicitly deferred Intel/macOS 13 runtime validation to future user testing because no test machine is available. This combination remains unverified; the decision permits feature preparation/review without representing the test as passed. See [current readiness](../automatic-updates.md).
- This spec synthesizes the research and the user's decision to keep annual costs at zero. The proposed testing boundary was explicitly confirmed by the user. Implementation progress and observed acceptance results are tracked in [Automatic updates](../automatic-updates.md); remaining runtime checks are not implied by this spec's approval.
- Recommended delivery order: prove packaging and a real staging upgrade; integrate the app/menu/consent experience; automate artifact/feed publication; complete the compatibility and migration evidence; then announce the updater-enabled release. Prepare that release before the LinkedIn promotion when practical.
- If end-to-end testing shows that Accessibility must be reauthorized after each ad-hoc update, report that product limitation explicitly rather than describing the feature as fully unattended. A paid signing track remains a separate future decision.
- The implementation agent should produce reviewable changes and verification evidence. Production release approval remains with the maintainer; publishing this issue does not authorize generating credentials, changing secrets, deploying releases or merging code.
- Primary references: [Sparkle setup and security](https://sparkle-project.org/documentation/), [programmatic integration](https://sparkle-project.org/documentation/programmatic-setup/), [update preferences](https://sparkle-project.org/documentation/customization/), [dockless-app reminders](https://sparkle-project.org/documentation/gentle-reminders/), [release publishing](https://sparkle-project.org/documentation/publishing/), [Apple Developer ID](https://developer.apple.com/developer-id/).
