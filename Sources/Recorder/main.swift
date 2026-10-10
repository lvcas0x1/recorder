import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Menu-bar app: no Dock icon and no app-switcher entry (spec: Menu-bar app without Dock icon).
    app.setActivationPolicy(.accessory)
    app.run()
}
