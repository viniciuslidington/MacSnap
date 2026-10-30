# MacSnap 🪟⚡

Update-channel implementation and release readiness are documented in [Automatic updates](docs/automatic-updates.md). The current public 1.0.7 download still needs one manual bootstrap into a future updater-enabled release; no automatic-update availability is claimed for that binary.

> Native macOS window manager built with **pure Swift**, bringing the convenience and power of **Windows 11 Snap Layouts** and **interactive paired split resizing** to the Mac ecosystem with a refined **Apple Glass UI** aesthetic.

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift&logoColor=white)](https://swift.org)
[![Architecture](https://img.shields.io/badge/Architecture-Universal%20(Apple%20Silicon%20%2B%20Intel)-purple)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

[Explore the MacSnap website](https://viniciuslidington.github.io/MacSnap/) for an overview, installation guidance and the latest download.

---

## ⚡ Quick Command-Line Installation

To install **MacSnap** on your Mac in seconds, open **Terminal** and run:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/viniciuslidington/MacSnap/main/install.sh)"
```

> **What this command does:**
> 1. Downloads the pre-compiled universal production package and installs to `/Applications/MacSnap.app`.
> 2. Configures silent Launch at Login in the background via LaunchAgent.
> 3. Launches MacSnap and opens the Accessibility settings pane in System Settings to grant permissions.

### Uninstallation

Packaged builds that include the clean uninstaller offer **Uninstall MacSnap…** in the status menu. The confirmation closes the app, moves it to Trash and removes its settings, caches, startup entry and privacy permissions. [Clean-uninstall behavior and limits](docs/clean-uninstall.md).

To preview the cleanup from Terminal before confirming it:

```bash
/Applications/MacSnap.app/Contents/Helpers/MacSnapUninstaller --dry-run
```

The public 1.0.7 build predates that helper. From this source checkout, use `./scripts/uninstall.sh --dry-run`, then `./scripts/uninstall.sh` and type `UNINSTALL`. Quit MacSnap first. Once a release includes the helper, the remote installer can use the same removal flow:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/viniciuslidington/MacSnap/main/install.sh)" -- --uninstall
```

---

## 🎯 Key Features

### 1. 🪟 Top Snap Bar (Windows 11 Style)
- **Collapsible Apple Glass Pill**: Dragging a window tab summons a subtle translucent glass pill at the top of the active display featuring a vector screen-split glyph.
- **Dynamic Multi-Monitor Tracking**: Follows cursor location dynamically across displays, seamlessly adapting between horizontal (16:9 / Ultrawide) and vertical (Portrait) screens.
- **On-Demand Hover Expansion**: Approaching the pill smoothly expands it into clean geometric layout templates without text clutter. Moving the cursor away collapses it back into the pill.
- **Landscape Templates (16:9 / Ultrawide):**
  - **2 Columns (50/50):** Left Half and Right Half.
  - **3 Columns (1/3 each):** Left, Center, and Right.
  - **Asymmetric (2/3 + 1/3):** Left 2/3 and Right 1/3.
  - **Inverted Asymmetric (1/3 + 2/3):** Left 1/3 and Right 2/3.
  - **4 Quarters (2x2):** Four screen quadrants.
  - **Maximize:** Full fill of visible screen frame.
- **Portrait Templates (Vertical Monitors):**
  - **Vertical Halves:** Top (1/2) and Bottom (1/2).
  - **Vertical Thirds:** Top (1/3), Center (1/3), and Bottom (1/3).
  - **Two Thirds:** Top (2/3) and Bottom (1/3).
  - **Inverted Two Thirds:** Top (1/3) and Bottom (2/3).
  - **Vertical Maximize:** Full vertical fill.

### 2. ⚡ Aero Snap / Edge Snapping
- **Left / Right Screen Edges:** Snaps window to half the screen (50/50).
- **Top Screen Edge:** Maximizes window, respecting the Menu Bar and Dock.
- **Four Screen Corners:** Divides screen into 25% quadrants.
- **Side Edges on Portrait Displays:** Snaps into thirds (1/3) based on cursor height along the edge.

### 3. 🎨 Apple Glass UI & Translucent Preview
- Translucent *frosted glass* effect (`NSVisualEffectView` with vibrant popover material), subtle specular highlights, and luminous bevel borders.
- Calibrated transparency ensuring underlying text and windows remain readable.
- Optimal layer ordering: the layout menu always stays in front of the preview overlay, providing continuous visual orientation.

### 4. 🔗 Paired Windows & Interactive Multi-Monitor Split (Snap Assist)
- **Real-Time Dual-Window Frosted Blur**: While dragging the central resize divider, both windows are wrapped in an elegant *Apple Glass* frosted blur overlay that resizes smoothly at 120Hz, masking any third-party app repaint stutter. Upon release, the blur fades out cleanly.
- **Auto-Detection of Existing Windows**: Automatically identifies open windows placed side-by-side or stacked on the same display, attaching an interactive resize divider at their junction.
- **On-Demand Hover-Only Visibility**: The divider handle remains 100% invisible during normal work, fading in smoothly (*Apple Glass*) only when the cursor hovers near the split seam.
- **Persistent Multi-Monitor Support**: Each connected screen maintains its paired window state independently. Adjusting a split on a landscape monitor does not disturb pairing on a vertical monitor.
- **Subtle Magnetic Snapping:** Dragging the divider near 50/50, 33/67, or 67/33 smoothly locks into the exact ratio.

### 5. 🍏 macOS Menu Bar Utility (`NSStatusItem`)
- Retina vector icon in paired split window style.
- Context menu with 1-click snap shortcuts, Accessibility permission status indicator, and Launch at Login toggle.
- Neutral menu icons, badges, and action buttons in light and dark mode; toggles retain the native accent color.
- Lightweight background utility (`LSUIElement` / `.accessory`), consuming minimal RAM and zero background battery impact.

---

## 🏛 Project Architecture

Built following **Swift 6 Concurrency**, **Clean Architecture**, and **SOLID** principles:

```text
Sources/MacSnap/
├── App/
│   ├── main.swift                       # Entry point (sets accessory application mode)
│   └── AppDelegate.swift                # App lifecycle and service orchestration
│
├── Core/
│   ├── Models/
│   │   ├── SnapZone.swift               # Enums and geometric math for snap zones
│   │   ├── ScreenGeometry.swift         # Cocoa <-> Accessibility API coordinate conversion
│   │   ├── WindowElement.swift          # Window identity and frame access wrapper
│   │   ├── PairedSplit.swift            # Paired window geometry, ratios, and ordered frame application
│   │   └── PairGeometry.swift           # Shared pair adjacency and alignment checks
│   └── Protocols/
│       ├── Protocols.swift              # Service contracts for dependency injection
│       └── ActionScheduling.swift       # Cancelable delayed work on the main actor
│
├── Services/
│   ├── Accessibility/
│   │   ├── AccessibilityService.swift   # Accessibility API bridge and focused-window fallback
│   │   ├── WindowDiscovery.swift        # Visible observations and AX identity reconciliation
│   │   └── WindowFrameAccess.swift      # Validated native frame reads and writes
│   ├── Screen/
│   │   └── ScreenService.swift          # Screen discovery, orientation, and visible frames
│   ├── EventMonitoring/
│   │   ├── GlobalEventMonitor.swift     # CGEventTap lifecycle and snap presentation
│   │   └── DragRecognition.swift        # Drag admission, movement threshold, and rejection state
│   └── Updating/
│       ├── AppUpdating.swift            # App/menu update interface and unavailable-build adapter
│       └── SparkleAppUpdater.swift      # Sparkle ownership, pending offers and safe termination
│
└── Features/
    ├── Snapping/
    │   ├── SnapEngine.swift             # Snap placement and pending-operation ownership
    │   └── SnapTargetResolver.swift     # Shared exact-slot and adaptive snap intent
    ├── Pairing/
    │   ├── PairedResizeManager.swift    # Per-display pairs, discovery, and divider presentation
    │   └── PairedResizeSession.swift    # Resize gesture, ordered writes, and observed settlement
    └── UI/
        ├── SnapLayoutBarWindow.swift        # Apple Glass floating layout bar (Pill and Expanded)
        ├── PreviewOverlayWindow.swift       # Translucent snap preview overlay window
        ├── PairedResizeOverlayWindow.swift  # Dual-window frosted blur overlay during paired resize
        ├── DividerHandleWindow.swift        # Interactive split divider bar
        └── MenuBarController.swift          # Menu bar status item and context menu controller
```

---

## 🧪 Unit Tests

The project includes an automated test suite written with the Swift Testing framework (`import Testing`):

```bash
swift test
```

Coverage includes:
- Geometric calculations for all `SnapZone` targets across landscape, portrait, and ultrawide displays.
- Bidirectional coordinate conversion between **Cocoa** (origin bottom-left) and **Accessibility API** (origin top-left).
- State transitions between pill mode, hover expansion, and collapse in the layout bar.
- Independent visual slot highlighting across cards with identical target zones.
- Automatic window adjacency detection and multi-monitor persistence.
- Menu hover reset after clicking, closing, and reopening; accessibility press actions and disabled-action rejection while paused.
- Update menu availability, pending versions, separate preferences and safe termination during window interactions.

Run `python3 scripts/test-update-distribution.py` for archive metadata, real EdDSA verification, feed preservation, stale-publication rejection and withdrawal policies. Production release acceptance is tracked separately in [Automatic updates](docs/automatic-updates.md).

---

## 🛠 Building from Source Code

To clone and build locally:

### Requirements:
- macOS 13.0 (Ventura) or later
- Xcode 16+ or Command Line Tools with Swift 6 support

```bash
# 1. Clone repository
git clone https://github.com/viniciuslidington/MacSnap.git
cd MacSnap

# 2. Build and install locally
./scripts/install.sh
```

---

## 🔒 Accessibility Permissions

macOS requires **Accessibility** permission so that MacSnap can query dimensions and position windows of other applications:

1. When opening MacSnap for the first time, a system dialog will prompt for permission.
2. You can also grant permission anytime in:
   **System Settings > Privacy & Security > Accessibility**
3. Enable the toggle next to **MacSnap**.

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for details.


## Architecture study and local validation

The native window refactoring is documented in [the architecture study](docs/architecture/native-window-study.md), including alternatives, trade-offs, isolation, native adapters, and test limits. The [domain glossary](CONTEXT.md) defines windows, snap intent, pairs, gestures, and observations.

Run `swift test` for geometry, drag recognition/event integration, snap intent and cancellation, window discovery/identity, paired resize settlement, and menu interactions. Tests use scripted frame/observation adapters and controlled time; they do not demonstrate every third-party application's native response.

Build the separate local test app with `./scripts/build-development-app.sh` and follow [the manual test checklist](docs/architecture/manual-test.md) to validate native interactions. This does not replace the installed app, change the bundle version, or publish a release.
