# MacSnap update distribution

This implementation uses Sparkle 2.10.1 with EdDSA-authenticated archives and the existing GitHub distribution. There is no annual Apple subscription requirement. It does not establish Developer ID identity or Apple notarization.

## Current readiness

The updater integration and release tooling are implemented locally. The maintainer generated the production key and configured the GitHub Actions variable `MACSNAP_UPDATE_PUBLIC_KEY` and secret `MACSNAP_UPDATE_PRIVATE_KEY`. Their presence and the public value were checked; the private secret is not readable through GitHub and its signing pair still needs verification by the trusted candidate workflow. No updater-enabled release has been approved, and the checked-in feed intentionally contains no updates. Builds without a configured public key keep updating unavailable and do not start Sparkle.

The fullscreen fix candidate is **1.0.9, build 9**, following the first updater candidate 1.0.8. This prepares version metadata for review; it does not create a tag or publish a release.

The local 1.0.8 candidate was assembled with the configured production public key, archived, extracted and recursively code-signature verified. Both architecture slices are present. Its archive has not been signed with the production private key; that verification remains part of trusted release preparation. The local SHA-256 and verification receipt are kept in ignored build output, not offered to clients.

VerificationResultSwift/AppKit integration tests86 tests passed, including menu actions and safe terminationDistribution policies and signatures20 tests passed, including withdrawal, stale promotion and real CryptoKit verificationExisting website checksBoth languages and all 12 preview lifecycle tests passedUniversal applicationIntel and Apple silicon slices built; both report macOS 13.0 minimumIsolated Sparkle A → B installationPassed on Apple silicon/macOS 26.6.2, using two separately compiled Cocoa test apps and an ephemeral EdDSA keyFull MacSnap local A → B rehearsalMaintainer reported success on 2026-10-29; installed 1.0.9/build 9 executable matches the independently compiled B candidate and its recursive code signature verifiesHelper runtime/signaturesVendor helper signatures/runtime flags retained; no library-validation bypass addedNative deferred terminationActual production updater/scheduler waited for a simulated interaction and exited after 1.550 seconds in AppKit's native termination loopFull MacSnap candidate packagingExtractable app, embedded framework, valid nested code signatures and valid EdDSA archive signatureAccessibility under the production bundle identityNot yet validated; the completed rehearsal uses a separate test identityIntel/macOS 13 runtimeDeferred to future user testing by maintainer decision; not validatedClean-profile migrationNot yet validatedProduction feed/releaseNot published

The isolated pilot used a loopback-only staging server. This demonstrates Sparkle replacement/relaunch, not public HTTPS delivery, a clean first installation, or MacSnap's Accessibility behavior. Temporary pilot artifacts are under ignored build output; its disposable private key was removed after validation and must never be used as a production credential.

The later full-app rehearsal used the MacSnap source, a separate test identity and a disposable signed feed. The maintainer reported that everything worked, and filesystem/code-signature verification independently confirmed replacement with the expected B executable. Detailed permission prompts, login behavior and production-identity Accessibility were not independently measured by that report. See the [local rehearsal record](architecture/automatic-updates-local-test.md).

## Application behavior

The app-level updater owns Sparkle. The status menu exposes Check for Updates…, a pending version, scheduled-check preferences and a separate automatic-download/install preference. Sparkle handles its consent flow, normal daily scheduling, download verification and installation UI. Existing users' choices are not rewritten at launch. Scheduled offers remain discoverable in the menu without stealing focus; explicit checks use Sparkle's standard UI.

Application termination waits while a window drag, a paired resize/settlement or a held mouse button is active. Once idle, normal application shutdown stops monitoring and clears transient pairing. Updating remains available when snapping is paused. Preferences and login identity are retained; their behavior after replacement still needs the acceptance checks below.

## Owner-only production setup

The maintainer completed key creation and GitHub configuration on 2026-10-29. The implementation agent checked only public configuration and secret metadata. Keep the procedure below for recovery or a new setup; do not generate a replacement key for an established channel without a deliberate migration plan.

1. Resolve the pinned dependencies and use Sparkle's official `generate_keys --account MacSnap-production` tool to generate a dedicated production key in the maintainer's Keychain. Never reuse the temporary pilot key.
2. Keep a recoverable backup in an appropriate private location. The public key is safe to distribute; the private seed is not. Do not put either an exported private file or its contents in the repository, logs, issue, app bundle or release assets.
3. Configure repository variable `MACSNAP_UPDATE_PUBLIC_KEY` with the base64 public key. Configure repository secret `MACSNAP_UPDATE_PRIVATE_KEY` with the base64 32-byte private seed supported by Sparkle's current tools. Do not paste private material into chat or expose it to pull-request jobs.
4. Use display version 1.0.8 and internal build 8 for the first candidate, subject to review. Later candidates must increase the integer build, including beyond withdrawn builds.

The bundle assembler injects only the public key. Missing/malformed keys, key/archive disagreement and invalid signatures stop candidate preparation. Losing the private key may require a manual bootstrap again; this free channel must not rely on Developer ID key-rotation recovery.

## Candidate and publication lifecycle

1. A reviewed release tag or a manual **Prepare MacSnap Release** run builds/tests the universal app, embeds Sparkle and its license, signs the app ad-hoc and packages the same signed app into a ZIP and a drag-to-Applications DMG. The final ZIP is signed for Sparkle updates; the DMG is verified without changing the app's signature.
2. Candidate preparation generates the appcast through Sparkle's tool, preserves existing offers and verifies the final archive against the configured public key. The draft release contains `MacSnap.app.zip`, `MacSnap.dmg`, `appcast.xml` and `SHA256.txt` with both artifact digests. It remains unpublished. Existing releases/assets are never overwritten; an incomplete draft requires deliberate maintainer recovery before retrying its tag.
3. Test the exact candidate ZIP with a separate staging feed/profile and rehearse installation from the candidate DMG. Sparkle supports a maintainer-controlled alternative feed through its documented updater feed settings/delegate; do not replace public feed content to perform a test. A draft download URL requires GitHub authentication and is not a usable public Sparkle enclosure, so staging must serve the downloaded candidate bytes at a test location, with matching signature/length.
4. Record the full acceptance result, then explicitly run **Publish Approved MacSnap Release** with the candidate `tag`, the tested ZIP's `archive_sha256` and the tested DMG's `dmg_sha256`. Before promoting that existing draft, it verifies both digests, the ZIP's EdDSA signature, the extracted app's code signature, the DMG's exact app payload against the extracted ZIP, and the non-regressing feed. It does not rebuild the approved candidate. See [DMG build and verification details](dmg-installer.md).
5. After both public downloads match the approved ZIP and DMG bytes, publication uploads `update-approval.json` containing `archive_sha256`, `dmg_sha256` and `appcast_sha256`. Only releases with a matching receipt are eligible for site hydration. The existing Pages workflow assembles the website with the most recently published approved release's appcast; a valid DMG receipt also selects the immutable DMG download and installation guidance in both languages. This is the final feed-publication step. Website/deployment runs share serialized production concurrency, and feed assembly preserves older offers and refuses stale/regressed metadata. Subsequent marketing deployments repeat feed hydration instead of restoring the empty source baseline.

The production feed is `https://viniciuslidington.github.io/MacSnap/updates/appcast.xml`. Its archive URLs identify an exact release. The landing page retains its current ZIP fallback until an approved DMG is available, then uses that release's version-specific DMG URL. Failure to retrieve trusted release metadata fails the website deployment rather than erasing the channel. Public candidates without approval receipts are ignored, retaining the deployed feed. Hydration examines the most recent 100 releases; if no approved release is present in that window it retains the live feed. Before the first approved updater release, an empty feed is valid.

If either public artifact verification fails after a draft was promoted, the release is public but no approval receipt exists, so neither the automatic trigger nor a later marketing deployment can publish its feed or select its DMG download. Investigate and explicitly rerun publication with the same approved digests to complete verification. A repeated approval receipt is accepted only if its contents are identical.

## Acceptance checklist

### Maintainer decision: deferred hardware testing

The maintainer has no Intel/macOS 13 test environment and explicitly chose to defer that runtime testing to future users. This does not block preparation or review of the feature. Keep the combination labeled unverified in release notes; do not turn the successful universal build into a claim of tested runtime support. Track incoming reports with the Mac model, macOS version, build, installation/update path and observed behavior, without asking users to share signing keys or personal system identifiers.

This decision applies to the unavailable hardware/OS combination. The full MacSnap A → B local rehearsal subsequently passed under its separate test identity. Clean-profile migration, login behavior and production-identity Accessibility remain separate checks; the deferred-hardware decision does not mark them as passed. Publication continues to require an explicit maintainer decision about the documented results and remaining limitations.

### Remaining acceptance checks

- Rehearse the exact production-signed candidate through staging before publication. The full MacSnap local A → B check has passed with a disposable key and separate identity; it does not establish the production signing pair.
- Track the deferred Intel/macOS 13 user-testing results when hardware becomes available; record unsupported/unavailable test machines explicitly. Continue available Apple silicon/current-OS checks.
- Use a disposable profile to test first launch without clearing quarantine, the manual migration from 1.0.7 and then an in-app update. Record actual Gatekeeper and Accessibility prompts. Do not enable unattended installation claims until unexpected grant loss is resolved or its limitation is accepted.
- Verify preferences, launch at login, manual checking while snapping is paused, long-running background reminders, defer/skip, separate preferences, offline recovery and authorization requirements.
- Verify wrong signatures, equal/older builds, incompatible OS requirements, interrupted downloads and installation from unsuitable/read-only locations do not replace a working app with an unusable or unauthenticated one.
- Verify installation waits for window dragging and paired resize settlement. Check that termination/relaunch cleanup leaves no orphan overlays or competing instances.
- Preserve the candidate SHA-256 and the staging receipt. Only then approve public distribution and update the English/Portuguese website to describe the released updater.

## Local commands

To rehearse a full MacSnap A → B update from this branch before merging, follow [the isolated local update guide](architecture/automatic-updates-local-test.md). Its separate app identity/feed/key keep the production installation independent; completing that rehearsal does not imply all production acceptance checks passed.

Run `swift test` and `python3 scripts/test-update-distribution.py`. Website changes additionally use `python3 scripts/check-site.py` and `node --test scripts/test-site-motion.cjs`.

`scripts/build-development-app.sh` builds an isolated, uninstalled app with the framework embedded. With no public key, update actions are disabled. It does not replace `/Applications/MacSnap.app`. The local installer uses the same assembler; the public installer verifies the downloaded bundle, preserves its signature and does not strip quarantine or re-sign it.

Use `python3 scripts/update-distribution.py --help` for candidate assembly/verification and feed hydration. Signing accepts its private seed only through the trusted process environment/stdin; diagnostics from the signing tool are deliberately not echoed. Production promotion uses public-key verification and never needs the private seed.

## Incident recovery

Do not replace bytes behind a version already offered to clients. To withdraw a faulty offer, add its integer build to `site/updates/withdrawn-builds.json` through a reviewed change and deploy Pages. Keep that build in the list permanently: hydration removes listed offers even when a release asset or cached feed still includes them. If every offer is withdrawn, a valid empty feed is deployed. A failed deployment leaves the existing feed in place, so verify the deployed feed before declaring the withdrawal complete.

Publish a corrected version with a build higher than every withdrawn build. Preparation and promotion enforce this floor, preventing reuse of an affected build. Removing an offer prevents future offers; it does not undo installed updates or guarantee cancellation of an update already downloaded by a client. Editing only the checked-in empty appcast baseline is ineffective because hydration restores approved offers.
