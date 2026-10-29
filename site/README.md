# MacSnap website

Buildless public landing page, in Brazilian Portuguese. Host only this directory with GitHub Pages, at `https://viniciuslidington.github.io/MacSnap/`.

## Validate and preview

Run `python3 scripts/check-site.py` from the repository root. Serve `site/` with a static HTTP server for visual checks. Also test it under the `/MacSnap/` path before publishing. No dependency installation or bundler is required.

`Website` validates pull requests and deploys only from main through its own workflow. The application release workflow and app version remain separate.

## Media and first-use limits

The interface images are rendered from the actual native AppKit views, with illustrative enabled/selection states. The surrounding windows and monitor diagrams on the page are illustrations. See [asset provenance](assets/README.md). This version contains no screen recording; no recording or clean-profile installation test is claimed.

The user approved publishing this version with these limitations disclosed. Before replacing installation guidance or adding a recording, download the public release ZIP through a browser into a fresh test profile and record the macOS version, architecture and observed prompts. Current distribution is ad-hoc signed, without Apple notarization.

## Sharing

The social image is `assets/social-preview.png` (1200 × 630). The title, description and Open Graph metadata are in `index.html`. After publishing, check the URL with LinkedIn's Post Inspector to refresh its cached preview.

Fonts are self-hosted with their OFL notices. No analytics, forms or runtime API requests are included. Download links use the latest GitHub Release; avoid hard-coding a version number into the landing page.
