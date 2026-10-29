# Landing page asset provenance

Generated on 2026-10-29. The PNGs are native AppKit **source renders**, not a screen recording or a capture of a user's desktop.

| Asset | Dimensions | Source |
| --- | --- | --- |
| `icon.png` | 256 × 256 px | Existing `Resources/AppIcon.icns`, exported with `sips` |
| `icon-128.png` | 128 × 128 px | Same original icon |
| `menu-native.png` | 620 × 808 px | Production `MenuHeaderView`, `QuickSnapSectionView`, `ControllersSectionView`, and `MenuFooterSectionView` |
| `layouts-native.png` | 1360 × 188 px | Production `SnapLayoutBarView` in expanded landscape mode, with its first slot hovered programmatically |
| `social-preview.png` | 1200 × 630 px | English browser-rendered editorial composition using the original icon, the native menu render and the self-hosted fonts below |
| `social-preview-pt.png` | 1200 × 630 px | Original Portuguese version of the same editorial composition |

The native views were compiled from this checkout with Swift 6 into a temporary render harness outside the repository. The harness appended an entry point to a temporary copy of `MenuBarController.swift` to access its private section views, and otherwise compiled the unchanged production sources (excluding the app's normal `main.swift`). It created offscreen AppKit windows, used the Aqua appearance and `NSView.cacheDisplay` at 2× resolution, and wrote PNGs. No window was shown, no event monitor was started, no Accessibility prompt was requested, no user windows were moved, and no preferences were changed.

The menu image is a composition of the actual section views on a neutral background. It omits the system-drawn Horizontal Layouts and Vertical Layouts submenu rows and menu separators; it is not presented as a complete open menu screenshot. Enabled controls and granted permission are illustrative render states; Launch at Login is off. Actions are inert closures in the render harness. The layout bar image uses its actual hover drawing and an offscreen native material, so transparency can differ from the live app over a desktop. No interaction or installation behavior has been tested by these images.

Source SHA-256 at generation:

```text
b8de5f2c12c061059cd458e3816003ebc34b9798fad086103b34a6bcd6646284  Sources/MacSnap/Features/UI/MenuBarController.swift
785eeb3efecbf5db051346567d921ceb081c1f74e8e4c8feb76d7cf317e1a831  Sources/MacSnap/Features/UI/SnapLayoutBarWindow.swift
d7262af1b03ea374c4d732c78b1f587e10b931886afa91242c4a512885b241cd  Resources/AppIcon.icns
```

## Self-hosted fonts

The WOFF2 files came from the official [Google Fonts CSS API](https://developers.google.com/fonts/docs/css2) and `fonts.gstatic.com`. Their Latin subsets include Portuguese accented letters. CSS requests were for DM Sans normal variable 400–700 and Newsreader static normal/italic 400 at optical size 72. Newsreader was changed from variable to the official static files on 2026-10-29 to reduce transfer size; the two files total 44,688 bytes instead of 278,908 bytes. Use `font-display: swap`.

- [`fonts/dm-sans-latin.woff2`](https://fonts.gstatic.com/s/dmsans/v17/rP2Yp2ywxg089UriI5-g4vlH9VoD8Cmcqbu0-K6z9mXg.woff2): [DM Sans](https://fonts.google.com/specimen/DM+Sans), normal, variable weight; license in `fonts/DM-Sans-OFL.txt`.
- [`fonts/newsreader-latin.woff2`](https://fonts.gstatic.com/s/newsreader/v26/cY9qfjOCX1hbuyalUrK49dLac06G1ZGsZBt4ByzBDXXD9JVF438weI_wC-ZFHDWwgUii.woff2): [Newsreader](https://fonts.google.com/specimen/Newsreader), normal, static weight 400, optical size 72, 21,704 bytes; license in `fonts/Newsreader-OFL.txt`.
- [`fonts/newsreader-latin-italic.woff2`](https://fonts.gstatic.com/s/newsreader/v26/cY9kfjOCX1hbuyalUrK439vogqC9yFZCYg7oRYaIP4obnf7fTXglsMwoT9ZHFjSShVCjzSY.woff2): Newsreader, italic, static weight 400, optical size 72, 22,984 bytes; same license.

The original SIL Open Font License texts are retained unchanged from the official [DM Sans](https://github.com/google/fonts/tree/main/ofl/dmsans) and [Newsreader](https://github.com/google/fonts/tree/main/ofl/newsreader) font directories. These are the only third-party visual assets used here. The MacSnap icon is the repository's original branding.
