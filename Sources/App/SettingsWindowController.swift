import AppKit

/// Configuration UI — stays open; save applies without closing; server on/off live.
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private var config: AppConfig
    private let onApply: (AppConfig) -> Void

    /// macOS switch (not checkbox) — default off; when left on, auto-starts next launch.
    private let serverSwitch = NSSwitch()
    private let serverSwitchLabel = NSTextField(labelWithString: "서버")
    private let lanToggle = NSButton(checkboxWithTitle: "외부 접근 허용 (LAN)", target: nil, action: nil)
    private let ipListToggle = NSButton(checkboxWithTitle: "IP 허용 목록 사용", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    private let portField = NSTextField(string: "8080")
    private let domainField = NSTextField(string: "")
    private let ipField = NSTextField(string: "")
    private let tokenField = NSTextField(string: "")
    private let urlsLabel = NSTextView()

    private let domainTable = NSTableView()
    private let ipTable = NSTableView()

    private var domains: [String] = []
    private var ips: [String] = []
    /// Live filter from the add/search field (auto-filters tables as you type).
    private var domainFilter = ""
    private var ipFilter = ""

    private var filteredDomains: [String] {
        filterList(domains, query: domainFilter)
    }

    private var filteredIPs: [String] {
        filterList(ips, query: ipFilter)
    }

    init(config: AppConfig, onApply: @escaping (AppConfig) -> Void) {
        self.config = config
        self.onApply = onApply
        self.domains = config.allowedDomains
        self.ips = config.allowedIPs

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WebDock 설정"
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: window)
        buildUI()
        loadFromConfig()
        refreshURLs()
        updateStatusLabel(running: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setServerRunning(_ running: Bool) {
        updateStatusLabel(running: running)
    }

    func syncServerToggle(enabled: Bool) {
        serverSwitch.state = enabled ? .on : .off
        updateStatusLabel(running: nil)
    }

    /// Reload form from disk/config without recreating the window.
    func reload(from newConfig: AppConfig) {
        config = newConfig
        domains = newConfig.allowedDomains
        ips = newConfig.allowedIPs
        domainFilter = ""
        ipFilter = ""
        domainField.stringValue = ""
        ipField.stringValue = ""
        loadFromConfig()
        refreshURLs()
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        root.addArrangedSubview(sectionLabel("서버"))
        let serverRow = NSStackView()
        serverRow.orientation = .horizontal
        serverRow.alignment = .centerY
        serverRow.spacing = 10
        serverSwitchLabel.font = NSFont.systemFont(ofSize: 13)
        serverSwitch.target = self
        serverSwitch.action = #selector(serverToggleChanged)
        // Leading label + trailing switch (common macOS settings layout)
        serverRow.addArrangedSubview(serverSwitchLabel)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        serverRow.addArrangedSubview(spacer)
        serverRow.addArrangedSubview(serverSwitch)
        serverRow.translatesAutoresizingMaskIntoConstraints = false
        serverRow.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -8).isActive = true
        root.addArrangedSubview(serverRow)

        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(statusLabel)

        let portRow = NSStackView()
        portRow.orientation = .horizontal
        portRow.spacing = 8
        portField.translatesAutoresizingMaskIntoConstraints = false
        portField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        portField.delegate = self
        portRow.addArrangedSubview(NSTextField(labelWithString: "포트"))
        portRow.addArrangedSubview(portField)
        root.addArrangedSubview(portRow)

        lanToggle.target = self
        lanToggle.action = #selector(togglesChanged)
        root.addArrangedSubview(lanToggle)

        // Domains — field is both add input and live filter
        root.addArrangedSubview(sectionLabel("도메인 접근 목록 (입력 시 목록 자동 필터)"))
        let domainScroll = makeTableScroll(domainTable, identifier: "domain")
        domainScroll.translatesAutoresizingMaskIntoConstraints = false
        domainScroll.heightAnchor.constraint(equalToConstant: 100).isActive = true
        root.addArrangedSubview(domainScroll)
        root.addArrangedSubview(listEditRow(
            field: domainField,
            placeholder: "검색 / 추가할 도메인",
            addAction: #selector(addDomain),
            removeAction: #selector(removeDomain)
        ))
        domainField.delegate = self

        // IPs
        root.addArrangedSubview(sectionLabel("IP 허용 목록 (입력 시 목록 자동 필터)"))
        ipListToggle.target = self
        ipListToggle.action = #selector(togglesChanged)
        root.addArrangedSubview(ipListToggle)
        let ipScroll = makeTableScroll(ipTable, identifier: "ip")
        ipScroll.translatesAutoresizingMaskIntoConstraints = false
        ipScroll.heightAnchor.constraint(equalToConstant: 100).isActive = true
        root.addArrangedSubview(ipScroll)
        root.addArrangedSubview(listEditRow(
            field: ipField,
            placeholder: "검색 / 추가할 IP",
            addAction: #selector(addIP),
            removeAction: #selector(removeIP)
        ))
        ipField.delegate = self

        // Token
        root.addArrangedSubview(sectionLabel("접속 토큰"))
        tokenField.isEditable = false
        tokenField.isBezeled = true
        tokenField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tokenField.translatesAutoresizingMaskIntoConstraints = false
        tokenField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        root.addArrangedSubview(tokenField)

        let regen = NSButton(title: "토큰 재생성", target: self, action: #selector(regenerateToken))
        regen.bezelStyle = .rounded
        root.addArrangedSubview(regen)

        // URLs
        root.addArrangedSubview(sectionLabel("접속 주소"))
        urlsLabel.isEditable = false
        urlsLabel.isSelectable = true
        urlsLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        urlsLabel.backgroundColor = NSColor.textBackgroundColor
        urlsLabel.drawsBackground = true
        urlsLabel.textContainerInset = NSSize(width: 6, height: 6)
        let urlScroll = NSScrollView()
        urlScroll.documentView = urlsLabel
        urlScroll.hasVerticalScroller = true
        urlScroll.borderType = .bezelBorder
        urlScroll.translatesAutoresizingMaskIntoConstraints = false
        urlScroll.heightAnchor.constraint(equalToConstant: 90).isActive = true
        urlScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 460).isActive = true
        root.addArrangedSubview(urlScroll)

        let hint = NSTextField(wrappingLabelWithString: "서버 토글은 바로 적용됩니다. 켜 두면 다음에 앱을 실행해도 자동으로 서버가 시작됩니다. 토큰·도메인·IP는 「저장 및 적용」 후 반영됩니다.")
        hint.textColor = .secondaryLabelColor
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.preferredMaxLayoutWidth = 470
        root.addArrangedSubview(hint)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let applyBtn = NSButton(title: "저장 및 적용", target: self, action: #selector(saveAndApply))
        applyBtn.bezelStyle = .rounded
        applyBtn.keyEquivalent = "\r"
        let openIni = NSButton(title: "ini 폴더 열기", target: self, action: #selector(openIniFolder))
        openIni.bezelStyle = .rounded
        buttons.addArrangedSubview(applyBtn)
        buttons.addArrangedSubview(openIni)
        root.addArrangedSubview(buttons)
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.boldSystemFont(ofSize: 12)
        return l
    }

    private func makeTableScroll(_ table: NSTableView, identifier: String) -> NSScrollView {
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        col.title = identifier == "domain" ? "도메인" : "IP"
        col.width = 420
        table.addTableColumn(col)
        table.headerView = nil
        table.delegate = self
        table.dataSource = self
        table.allowsEmptySelection = false
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 22
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        return scroll
    }

    private func listEditRow(
        field: NSTextField,
        placeholder: String,
        addAction: Selector,
        removeAction: Selector
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        field.placeholderString = placeholder
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        let add = NSButton(title: "+", target: self, action: addAction)
        add.bezelStyle = .rounded
        let remove = NSButton(title: "−", target: self, action: removeAction)
        remove.bezelStyle = .rounded
        row.addArrangedSubview(field)
        row.addArrangedSubview(add)
        row.addArrangedSubview(remove)
        return row
    }

    private func loadFromConfig() {
        serverSwitch.state = config.serverEnabled ? .on : .off
        lanToggle.state = config.allowLAN ? .on : .off
        ipListToggle.state = config.ipAllowlistEnabled ? .on : .off
        portField.stringValue = String(config.port)
        if config.token.isEmpty {
            config.token = AppConfig.generateToken()
        }
        tokenField.stringValue = config.token
        domainTable.reloadData()
        ipTable.reloadData()
    }

    private func updateStatusLabel(running: Bool?) {
        let enabled = serverSwitch.state == .on
        if let running {
            if running {
                statusLabel.stringValue = "상태: 켜짐 (실행 중) — 끄면 서버 중지 · 다음 실행에도 유지"
                statusLabel.textColor = .systemGreen
            } else if enabled {
                statusLabel.stringValue = "상태: 켜짐 (시작 중…)"
                statusLabel.textColor = .systemOrange
            } else {
                statusLabel.stringValue = "상태: 꺼짐 — 켜 두면 다음 실행 때 자동 시작"
                statusLabel.textColor = .secondaryLabelColor
            }
        } else {
            statusLabel.stringValue = enabled
                ? "상태: 켜짐 — 저장되면 자동 시작"
                : "상태: 꺼짐 (기본)"
            statusLabel.textColor = .secondaryLabelColor
        }
    }

    // MARK: - Filter

    private func filterList(_ items: [String], query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return items }
        return items.filter { $0.lowercased().contains(q) }
    }

    // MARK: - Actions

    @objc private func serverToggleChanged() {
        // Immediate apply for on/off so user can toggle without closing.
        saveAndApply()
    }

    @objc private func togglesChanged() {
        refreshURLs()
    }

    @objc private func addDomain() {
        let v = domainField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !v.isEmpty else { return }
        guard !domains.contains(where: { $0.caseInsensitiveCompare(v) == .orderedSame }) else {
            domainField.stringValue = ""
            domainFilter = ""
            domainTable.reloadData()
            return
        }
        domains.append(v)
        domainField.stringValue = ""
        domainFilter = ""
        domainTable.reloadData()
        refreshURLs()
    }

    @objc private func removeDomain() {
        let row = domainTable.selectedRow
        let visible = filteredDomains
        guard row >= 0, row < visible.count else { return }
        let target = visible[row]
        domains.removeAll { $0.caseInsensitiveCompare(target) == .orderedSame }
        domainTable.reloadData()
        refreshURLs()
    }

    @objc private func addIP() {
        let v = ipField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        guard !ips.contains(v) else {
            ipField.stringValue = ""
            ipFilter = ""
            ipTable.reloadData()
            return
        }
        ips.append(v)
        ipField.stringValue = ""
        ipFilter = ""
        ipTable.reloadData()
    }

    @objc private func removeIP() {
        let row = ipTable.selectedRow
        let visible = filteredIPs
        guard row >= 0, row < visible.count else { return }
        let target = visible[row]
        ips.removeAll { $0 == target }
        ipTable.reloadData()
    }

    @objc private func regenerateToken() {
        config.token = AppConfig.generateToken()
        tokenField.stringValue = config.token
        refreshURLs()
    }

    @objc private func openIniFolder() {
        try? FileManager.default.createDirectory(at: AppConfig.supportDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(AppConfig.supportDirectory)
    }

    /// Save ini + apply to running server. Window stays open.
    @objc private func saveAndApply() {
        applyFormToConfig()
        do {
            try config.save()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
            return
        }
        onApply(config)
        // Do not close window — keep UI for further toggles / token changes.
        refreshURLs()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    private func applyFormToConfig() {
        config.serverEnabled = serverSwitch.state == .on
        config.allowLAN = lanToggle.state == .on
        config.ipAllowlistEnabled = ipListToggle.state == .on
        if let p = UInt16(portField.stringValue.trimmingCharacters(in: .whitespaces)), p > 0 {
            config.port = p
        }
        config.token = tokenField.stringValue.trimmingCharacters(in: .whitespaces)
        config.allowedDomains = domains
        config.allowedIPs = ips
    }

    private func refreshURLs() {
        applyFormToConfig()
        let lan = NetworkInfo.lanIPv4Addresses()
        var lines: [String] = []
        lines.append("로컬:  http://127.0.0.1:\(config.port)")
        if config.allowLAN {
            if lan.isEmpty {
                lines.append("LAN:   (감지된 IP 없음)")
            } else {
                for ip in lan {
                    lines.append("LAN:   http://\(ip):\(config.port)")
                }
            }
        } else {
            lines.append("LAN:   꺼짐 (이 Mac에서만 접속)")
        }
        lines.append("")
        lines.append("WS:    \(config.websocketHint(for: "127.0.0.1"))")
        if config.allowLAN, let first = lan.first {
            lines.append("WS:    \(config.websocketHint(for: first))")
        }
        if config.hasToken {
            lines.append("")
            lines.append("토큰 사용 중 — WS URL에 token 쿼리 포함")
        }
        if config.ipAllowlistEnabled {
            lines.append("IP 허용 목록: 켜짐 (\(ips.count)개)")
        }
        if !domains.isEmpty {
            lines.append("도메인 허용: \(domains.count)개")
        }
        urlsLabel.string = lines.joined(separator: "\n")
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === domainTable ? filteredDomains.count : filteredIPs.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField) ?? NSTextField(labelWithString: "")
        cell.identifier = id
        cell.isEditable = false
        cell.drawsBackground = false
        cell.isBordered = false
        if tableView === domainTable {
            cell.stringValue = filteredDomains[row]
        } else {
            cell.stringValue = filteredIPs[row]
        }
        return cell
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === portField {
            refreshURLs()
        } else if field === domainField {
            domainFilter = field.stringValue
            domainTable.reloadData()
        } else if field === ipField {
            ipFilter = field.stringValue
            ipTable.reloadData()
        }
    }
}
