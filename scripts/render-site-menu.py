#!/usr/bin/env python3
"""Render current native menu sections offscreen, without starting or installing MacSnap."""
import argparse
from pathlib import Path
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent

RENDERER = r'''
import QuartzCore
@MainActor
func renderWebsiteMenu(to path: String, version: String) throws {
    _ = NSApplication.shared
    let appearance = NSAppearance(named: .aqua)!
    let width: CGFloat = 310
    NSApplication.shared.appearance = appearance
    var sections: [NSView] = []
    appearance.performAsCurrentDrawingAppearance {
      sections = [
        MenuHeaderView(width: width, isMasterEnabled: true, isAccessibilityGranted: true,
                       onMasterToggle: { _ in }, onOpenAccessibility: {}),
        QuickSnapSectionView(width: width, onSelectZone: { _ in }),
        ControllersSectionView(width: width, isTopBarEnabled: true, isEdgeSnapEnabled: true,
                               isDividerEnabled: true, isOptionSnapEnabled: false,
                               onToggleTopBar: { _ in }, onToggleEdgeSnap: { _ in },
                               onToggleDivider: { _ in }, onToggleOption: { _ in },
                               onReconnectPair: {}, onClearPair: {}),
        MenuFooterSectionView(width: width, isLaunchAtLogin: false, versionText: version,
                              onToggleLaunchAtLogin: { _ in }, onQuit: {})
      ]
    }
    let gap: CGFloat = 8
    let height = sections.reduce(0) { $0 + $1.frame.height } + gap * CGFloat(sections.count + 1)
    let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    container.appearance = appearance
    container.wantsLayer = true
    container.layer?.cornerRadius = 14
    container.layer?.masksToBounds = true
    container.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor
    var y = height - gap
    for section in sections {
        y -= section.frame.height
        section.setFrameOrigin(NSPoint(x: 0, y: y))
        container.addSubview(section)
        y -= gap
    }
    let window = NSWindow(contentRect: container.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = appearance
    window.contentView = container
    container.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    CATransaction.flush()
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = container.bounds.size
    appearance.performAsCurrentDrawingAppearance {
        container.cacheDisplay(in: container.bounds, to: bitmap)
    }
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("Rendered native menu sections at \(bitmap.pixelsWide) × \(bitmap.pixelsHigh)")
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'site/assets/menu-native.png')
    args = parser.parse_args()
    subprocess.run(['swift', 'build'], cwd=ROOT, check=True)
    binary_dir = Path(subprocess.check_output(['swift', 'build', '--show-bin-path'], cwd=ROOT, text=True).strip())
    info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='macsnap-menu-render-') as directory:
        stage = Path(directory)
        source = ROOT / 'Sources/MacSnap/Features/UI/MenuBarController.swift'
        menu = stage / 'MenuBarController.swift'
        menu.write_text(source.read_text() + '\n' + RENDERER)
        entry = stage / 'main.swift'
        entry.write_text('import AppKit\ntry renderWebsiteMenu(to: CommandLine.arguments[1], version: CommandLine.arguments[2])\n')
        sources = sorted(path for path in (ROOT / 'Sources/MacSnap').rglob('*.swift')
                         if path != source and path.name != 'main.swift')
        executable = stage / 'render-menu'
        subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-module-name', 'MacSnap',
                        '-I', str(binary_dir), '-F', str(binary_dir), '-framework', 'Sparkle',
                        '-Xlinker', '-rpath', '-Xlinker', str(binary_dir),
                        *map(str, sources), str(menu), str(entry),
                        str(binary_dir / 'MacSnapUninstallation.o'), '-o', str(executable)], cwd=ROOT, check=True)
        subprocess.run([str(executable), str(output), 'MacSnap v' + info['CFBundleShortVersionString']], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
