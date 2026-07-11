import Cocoa

// Keep process I/O unbuffered for console logs.
setbuf(stdout, nil)

let app = NSApplication.shared
// Dock + Cmd-Tab visible so settings (server on/off, token) stay reachable.
app.setActivationPolicy(.regular)

AppController.shared.bootstrap()

// Run loop keeps process alive and provides WindowServer for ScreenCaptureKit.
app.run()
