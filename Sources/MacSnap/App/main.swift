import Cocoa

// Called only by the clean-uninstall helper, before creating an app or updater session.
if Array(CommandLine.arguments.dropFirst()) == ["--unregister-login-item"] {
    do { try AppUninstaller.unregisterLoginItem(); exit(0) }
    catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Accessory mode: Do not show in Dock; runs as a menu bar background utility
app.setActivationPolicy(.accessory)

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
