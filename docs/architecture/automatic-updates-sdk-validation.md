# Sparkle SDK integration validation

Checked on 2026-10-29 against the local Sparkle checkout at tag `2.10.1`, commit `ab7d71291238df6e0492143b120c9b696a35f603`. This is a source-contract review of the current implementation, not another end-to-end installation test.

## Result

No concrete SDK incompatibility was found in the reviewed calls and delegate hooks. Native termination deferral under a real busy interaction remains a specific runtime validation item; source inspection alone does not establish delivery of the app's scheduled callback inside AppKit's termination run loop.

## Manual checking and pending offers

[`SparkleAppUpdater`](../../Sources/MacSnap/Services/Updating/SparkleAppUpdater.swift) owns a standard updater controller and observes `canCheckForUpdates`; the menu uses that availability and calls the controller's `checkForUpdates` action on the main actor.

The SDK explicitly makes `canCheckForUpdates` suitable for menu validation. It can be true while an update is already presented: it is not equivalent to an idle session. With the standard user driver, `checkForUpdates` brings that existing offer into focus. This matches the app's menu-only scheduled-offer approach; the guard does not inherently prevent opening a pending offer. [Pinned `SPUUpdater.h`](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Sparkle/SPUUpdater.h#L155-L171), [implementation](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Sparkle/SPUUpdater.m#L684-L720)

## Gentle reminders and session cleanup

Returning false from `standardUserDriverShouldHandleShowingScheduledUpdate` makes the app responsible for a reminder. The implementation supplies `standardUserDriverWillHandleShowingUpdate` and exposes the version through the menu. User-initiated checks still use Sparkle's standard UI. The SDK says the controller's manual-check action can bring the offer forward. [Pinned user-driver delegate contract](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Sparkle/SPUStandardUserDriverDelegate.h#L93-L157)

Clearing the custom indicator from `standardUserDriverWillFinishUpdateSession` is the documented session-level cleanup point. Clearing it on `updater(_:didAbortWithError:)` also handles failed cycles, including a no-update result. An attention callback is optional when the indicator is intentionally retained for the full session. [Session cleanup contract](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Sparkle/SPUStandardUserDriverDelegate.h#L159-L189), [abort callback](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Sparkle/SPUUpdaterDelegate.h)

## Termination and installation on quit

Sparkle's installation progress agent uses `NSRunningApplication.terminate`, with a source comment explaining that this sends a normal Apple quit event so the application can delay or cancel. It waits for the target to terminate before final replacement. This supports the app's `applicationShouldTerminate` seam rather than requiring a custom Sparkle termination API. [Pinned termination request](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Sparkle/InstallerProgress/InstallerProgressAppController.m#L374-L385), [installer termination observation](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Autoupdate/AppInstaller.m#L392-L420)

The automatic driver can prepare an update and leave the separate installer alive until the app quits. Implementing `willInstallUpdateOnQuit` is optional; the current adapter can use the default path. [Pinned automatic driver](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Sparkle/SPUAutomaticUpdateDriver.m#L108-L139), [updater delegate contract](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Sparkle/SPUUpdaterDelegate.h)

[`AppDelegate.applicationShouldTerminate`](../../Sources/MacSnap/App/AppDelegate.swift) returns `.terminateLater` only when the adapter defers, and its resume closure calls `reply(toApplicationShouldTerminate: true)`. Apple requires that later reply. Apple also documents that `.terminateLater` runs the loop in `NSModalPanelRunLoopMode`. The adapter polls through `MainActorScheduler`, whose delivery is outside the SDK contract being checked here. A real busy-to-idle quit test should establish that the reply arrives without waiting indefinitely; fake-scheduler tests alone do not establish this native behavior. This is a test requirement, not a demonstrated defect. [Apple termination reply](https://developer.apple.com/documentation/appkit/nsapplication/reply(toapplicationshouldterminate:)), [Apple deferred termination](https://developer.apple.com/documentation/appkit/nsapplication/terminatereply/terminatelater)

## Framework and helper signatures

[`scripts/update-distribution.py`](../../scripts/update-distribution.py) copies the framework with `ditto`, retains vendor helper signatures, signs the outer framework and host without `--deep`, then verifies recursively.

Sparkle documents that its distributed helpers/XPC services are ad-hoc signed with Hardened Runtime and support common development workflows. It separately documents re-signing nested components with the publisher's certificate for custom certificate-based distribution. Preserving the vendor helpers in the current ad-hoc pilot is therefore not a claim that a future Developer ID/notarized distribution can reuse the same signing steps. [Official signing guidance](https://sparkle-project.org/documentation/sandboxing/#code-signing)

The parent implementation session reported a successful isolated Cocoa A→B replacement/relaunch on arm64 macOS 26.6.2 with retained helper signatures, plus recursive code-sign and EdDSA verification of the assembled MacSnap package. Those are parent-session observations, not tests rerun by this review. They do not establish Intel behavior, minimum-OS behavior, fresh-profile Gatekeeper UX, Accessibility permission persistence or the active-interaction termination case.

Only this research note was added during the review. No app was run, signing identity changed, keychain accessed, source/workflow edited, commit pushed or PR created by this review.

### Implementation follow-up

After that source review, the parent ran a native Cocoa termination fixture using the actual production `SparkleAppUpdater` and `MainActorScheduler`. Its quit request returned `.terminateLater` while a 1.5-second simulated interaction was busy, then the actual scheduler delivered the reply inside AppKit's termination loop. The fixture exited after 1.550 seconds and recorded `waitedUntilIdle: true`. This closes the modal-run-loop delivery question for the tested arm64/macOS 26.6.2 environment; it does not establish the remaining cross-machine Accessibility or minimum-OS acceptance cases.
