import AppKit
import Foundation

/// Owns config, settings UI, status-item, and the HTTP server lifecycle.
/// Settings stay accessible from Dock + menu bar (never buried as pure agent).
final class AppController: NSObject, NSApplicationDelegate {
    static let shared = AppController()

    private var config: AppConfig = .loadOrDefault()
    private var server: Server?
    private var settingsWC: SettingsWindowController?
    private var statusItem: NSStatusItem?

    private override init() {
        super.init()
    }

    func bootstrap() {
        NSApp.delegate = self
        // Always regular: Dock icon + Cmd-Tab so the settings window is reachable.
        NSApp.setActivationPolicy(.regular)

        Permissions.requestAll()
        setupStatusItem()

        config = AppConfig.loadOrDefault()
        applyEnvOverrides()
        // Auto-start only if user previously left the server toggle ON (default is off).
        startServerIfEnabled()
        updateStatusItem()
        openSettings(isFirstRun: !AppConfig.exists)
    }

    // MARK: - NSApplicationDelegate

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings(isFirstRun: false)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running as menu-bar + dock app even if settings is closed.
        false
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "WebDock"
            button.toolTip = "WebDock 설정 열기"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "설정 열기…", action: #selector(openSettingsMenu), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        let startItem = NSMenuItem(title: "서버 시작", action: #selector(startServerMenu), keyEquivalent: "")
        startItem.tag = 100
        let stopItem = NSMenuItem(title: "서버 중지", action: #selector(stopServerMenu), keyEquivalent: "")
        stopItem.tag = 101
        menu.addItem(startItem)
        menu.addItem(stopItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "종료", action: #selector(quitApp), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
        updateStatusItem()
    }

    /// Menu bar title + enable start/stop according to whether the server is running.
    private func updateStatusItem() {
        let running = server != nil
        if let button = statusItem?.button {
            button.title = running ? "WebDock ●" : "WebDock ○"
            button.toolTip = running
                ? "WebDock — 서버 실행 중 (클릭: 설정)"
                : "WebDock — 서버 꺼짐 (클릭: 설정에서 시작)"
        }
        if let menu = statusItem?.menu {
            menu.item(withTag: 100)?.isEnabled = !running // 시작
            menu.item(withTag: 101)?.isEnabled = running  // 중지
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        // Left click opens settings; menu still available via click-hold / right menu.
        guard let event = NSApp.currentEvent else {
            openSettings(isFirstRun: false)
            return
        }
        if event.type == .rightMouseUp {
            // Let the menu show (default).
            statusItem?.button?.performClick(nil)
            return
        }
        openSettings(isFirstRun: false)
    }

    @objc private func openSettingsMenu() {
        openSettings(isFirstRun: false)
    }

    @objc private func startServerMenu() {
        config.serverEnabled = true
        _ = try? config.save()
        startServerIfEnabled()
        settingsWC?.setServerRunning(server != nil)
        settingsWC?.syncServerToggle(enabled: true)
        updateStatusItem()
        bringSettingsToFront()
    }

    @objc private func stopServerMenu() {
        stopServer()
        config.serverEnabled = false
        _ = try? config.save()
        print("WebDock server stopped")
        settingsWC?.setServerRunning(false)
        settingsWC?.syncServerToggle(enabled: false)
        updateStatusItem()
        bringSettingsToFront()
    }

    @objc private func quitApp() {
        stopServer()
        NSApp.terminate(nil)
    }

    // MARK: - Settings

    func openSettings(isFirstRun: Bool) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        var base = AppConfig.loadOrDefault()
        if base.token.isEmpty { base.token = AppConfig.generateToken() }

        if settingsWC == nil {
            settingsWC = SettingsWindowController(config: base) { [weak self] saved in
                self?.applyConfig(saved)
            }
            settingsWC?.window?.delegate = self
        } else {
            settingsWC?.reload(from: base)
        }

        bringSettingsToFront()
        settingsWC?.setServerRunning(server != nil)
        updateStatusItem()
    }

    private func bringSettingsToFront() {
        guard let wc = settingsWC, let window = wc.window else { return }
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // Normal window level — stays in Dock/Cmd-Tab app, not agent-only.
        window.level = .normal
        wc.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Called from settings without closing the window.
    private func applyConfig(_ saved: AppConfig) {
        config = saved
        applyEnvOverrides()
        stopServer()
        if config.serverEnabled {
            startServerIfEnabled()
        } else {
            print("WebDock: server off (user disabled)")
        }
        settingsWC?.setServerRunning(server != nil)
        updateStatusItem()
        // Keep window on top after apply (restart can steal focus).
        DispatchQueue.main.async { [weak self] in
            self?.bringSettingsToFront()
        }
        printConfigSummary()
    }

    // MARK: - Server lifecycle

    private func applyEnvOverrides() {
        if let p = ProcessInfo.processInfo.environment["PORT"], let v = UInt16(p) {
            config.port = v
        }
        if ProcessInfo.processInfo.environment["ALLOW_LAN"] == "1" {
            config.allowLAN = true
        }
        if let t = ProcessInfo.processInfo.environment["WEBDOCK_TOKEN"], !t.isEmpty {
            config.token = t
        }
    }

    private func startServerIfEnabled() {
        guard config.serverEnabled else {
            print("WebDock: server disabled in config")
            updateStatusItem()
            return
        }
        stopServer()
        do {
            let s = try Server(config: config)
            s.start()
            server = s
            updateStatusItem()
            printConfigSummary()
        } catch {
            FileHandle.standardError.write(Data("server error: \(error)\n".utf8))
            server = nil
            updateStatusItem()
            let alert = NSAlert(error: error)
            alert.messageText = "서버 시작 실패"
            alert.runModal()
            bringSettingsToFront()
        }
    }

    private func stopServer() {
        server?.stop()
        server = nil
        updateStatusItem()
    }

    private func printConfigSummary() {
        setbuf(stdout, nil)
        print("WebDock config: \(AppConfig.iniURL.path)")
        if config.serverEnabled, server != nil {
            print("  local : http://127.0.0.1:\(config.port)")
            if config.allowLAN {
                for ip in NetworkInfo.lanIPv4Addresses() {
                    print("  LAN   : http://\(ip):\(config.port)")
                }
            } else {
                print("  LAN   : off (loopback only)")
            }
            if config.hasToken {
                print("  token : set (ws://…/ws?token=…)")
            } else {
                print("  token : off")
            }
        } else {
            print("  server: stopped / disabled")
        }
        print(Permissions.summaryLine())
    }
}

// Re-open settings when user closes the window then clicks Dock.
extension AppController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Keep controller; just hide. User can reopen from Dock / menu bar.
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide instead of destroy so state (token field etc.) is preserved.
        sender.orderOut(nil)
        return false
    }
}
