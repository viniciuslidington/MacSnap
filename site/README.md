# MacSnap website

Buildless public landing page, in Brazilian Portuguese. Host only this directory with GitHub Pages, at `https://viniciuslidington.github.io/MacSnap/`.

## Validate and preview

Run `python3 scripts/check-site.py` from the repository root. Serve `site/` with a static HTTP server for visual checks. Also test it under the `/MacSnap/` path before publishing. No dependency installation or bundler is required.

`Website` validates pull requests and deploys only from main through its own workflow. The application release workflow and app version remain separate.

Changes stay local for user review. Open a pull request only after explicit user approval; do not automatically open, merge or publish one.

## Media and first-use limits

The menu image is rendered from actual native AppKit views, with illustrative enabled/selection states. The interactive layout board, surrounding windows and monitor diagrams are illustrations. The original layout capture is retained as a reference asset. See [asset provenance](assets/README.md). This version contains no screen recording; no recording or clean-profile installation test is claimed.

Clean-profile installation validation remains pending. Before claiming it has been tested or adding a recording, download the public release ZIP through a browser into a fresh test profile and record the macOS version, architecture and observed prompts. The website retains the current ad-hoc signing and lack of Apple notarization notice.

## Sharing

The social image is `assets/social-preview.png` (1200 × 630). The title, description and Open Graph metadata are in `index.html`. After publishing, check the URL with LinkedIn's Post Inspector to refresh its cached preview.

Fonts are self-hosted with their OFL notices. No analytics, forms or runtime API requests are included. Download links use the latest GitHub Release; avoid hard-coding a version number into the landing page.

## Interactive illustrations

Mouse movement adds a small depth effect to the hero layers. This effect runs only with a fine pointer and no reduced-motion preference; leaving the artwork, switching tabs or changing that preference cancels pending frames and resets the artwork. There is no continuous animation loop or global pointer tracking. Individual HTML layout slots highlight on hover and keyboard focus; clicking selects a slot and updates its illustrative caption.

On first view, the layout pill opens for a short preview, highlights a few slots and closes. Actual mouse movement, keyboard focus or a tap permanently cancels that automatic sequence for this page load. Thereafter the panel opens on hover, closes on mouse leave, retains keyboard focus access, and supports a disclosure button for touch/keyboard and Escape to close. The closed panel is inert and hidden from assistive technology. Its illustration reserves its full area to avoid shifting the page during expansion; without JavaScript the layout board stays visible.

The visible pill follows the native `showPill` proportions (220 × 24 pt): a low glass capsule with two centered panes and a small chevron. Its web button keeps a 44 px hit area around that 24 px visible shape for touch and keyboard focus.

The split illustration previews a small ratio change once on entering the viewport, and the monitor illustration plays one short window-arranging animation. Focusing or using the divider cancels its preview immediately. All three automatic previews stop offscreen, on tab hiding/blur, or when reduced motion is enabled, and disconnect their visibility listeners when finished. They never loop. Browsers without IntersectionObserver use a scroll-frame visibility fallback.

The paired-window illustration is adjusted by dragging the central divider itself with pointer capture. That handle exposes slider semantics: arrows change the split by 1%, Page Up/Down by 10%, and Home/End select the 40%/70% limits. It changes only the illustration, labels the current percentages for assistive technology, and remains usable with reduced motion. Pointer cancellation, lost capture, blur, resize and tab hiding end the drag. Without JavaScript, the illustration stays static and the inactive control stays hidden.

## Native tiling comparison

Checked Apple's [window tiling guide](https://support.apple.com/pt-br/guide/mac-help/mchlef287e5d/mac) and [icons and shortcuts reference](https://support.apple.com/pt-br/guide/mac-help/mchl9674d0b0/mac) on 2026-10-29. Apple documents native tiling, including a three-window arrangement with one half and two quarters. Do not claim that macOS cannot organize windows on portrait displays or cannot arrange three windows.

The page instead highlights MacSnap's explicit top/middle/bottom third positions for portrait displays, verified in `buildVerticalSlots` in `Sources/MacSnap/Features/UI/SnapLayoutBarWindow.swift` and the geometry in `Sources/MacSnap/Core/Models/SnapZone.swift`. This is a comparison of documented presets, not an exhaustive runtime test of macOS or a claim that manual resizing is impossible. The app positions each selected window; it does not automatically populate all three slots.
