# MacSnap 🪟⚡

> Native macOS window manager built with **pure Swift**, bringing the convenience and power of **Windows 11 Snap Layouts** and **interactive paired split resizing** to the Mac ecosystem with a refined **Apple Glass UI** aesthetic.

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift&logoColor=white)](https://swift.org)
[![Architecture](https://img.shields.io/badge/Architecture-Universal%20(Apple%20Silicon%20%2B%20Intel)-purple)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

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

To completely uninstall MacSnap and remove Launch at Login at any time:

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
│   │   ├── WindowElement.swift          # Type-safe wrapper over AXUIElement with anti-clamp sizing
│   │   └── PairedSplit.swift            # Mathematical model for paired window splits and ratios
│   └── Protocols/
│       └── Protocols.swift              # Protocol contracts and abstractions for dependency injection
│
├── Services/
│   ├── Accessibility/
│   │   └── AccessibilityService.swift   # Accessibility API bridge (HIServices) with 5-level fallback
│   ├── Screen/
│   │   └── ScreenService.swift          # Screen discovery, orientation, and visible frames
│   └── EventMonitoring/
│       └── GlobalEventMonitor.swift     # Global mouse event tracking via CGEventTap
│
└── Features/
    ├── Snapping/
    │   └── SnapEngine.swift             # Core snapping engine and window repositioning
    ├── Pairing/
    │   └── PairedResizeManager.swift    # Multi-monitor paired window and divider manager
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

---

## 🛠 Building from Source Code

To clone and build locally:

### Requirements:
- macOS 13.0 (Ventura) or later
- Xcode 15+ or Command Line Tools with Swift 6 support

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
