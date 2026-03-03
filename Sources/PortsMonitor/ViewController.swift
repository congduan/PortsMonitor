import AppKit
import Foundation
import Darwin
import Darwin.C


class ViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource, NSSearchFieldDelegate, NSWindowDelegate {
    
    struct PortInfo: Hashable {
        let port: Int
        let processName: String
        let processID: Int
        let protocolType: String
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(port)
            hasher.combine(processID)
            hasher.combine(protocolType)
        }
        
        static func == (lhs: PortInfo, rhs: PortInfo) -> Bool {
            return lhs.port == rhs.port && lhs.processID == rhs.processID && lhs.protocolType == rhs.protocolType
        }
    }
    
    private var portInfos: [PortInfo] = []
    private var filteredPortInfos: [PortInfo] = []
    private var portMonitoringTimer: Timer?
    private var isMonitoringEnabled = false
    
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let searchField = NSSearchField()
    private let refreshButton = NSButton()
    private let killButton = NSButton()
    private let monitorToggle = NSButton()
    private let portCountLabel = NSTextField()
    private let toolbarContainer = NSView()
    private let buttonStackView = NSStackView()
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        setupUI()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        refreshPortDataAsync()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        if let window = view.window {
            window.delegate = self
        }
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        // View is about to appear
    }
    
    private func setupUI() {
        let toolbarHeight: CGFloat = 40
        let margin: CGFloat = 16
        let buttonSpacing: CGFloat = 8
        
        toolbarContainer.frame = NSRect(x: 0, y: view.bounds.height - toolbarHeight, width: view.bounds.width, height: toolbarHeight)
        toolbarContainer.wantsLayer = true
        toolbarContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.addSubview(toolbarContainer)
        
        searchField.frame = NSRect(x: margin, y: 6, width: 200, height: 28)
        searchField.delegate = self
        searchField.placeholderString = "Search ports..."
        toolbarContainer.addSubview(searchField)
        
        buttonStackView.frame = NSRect(x: view.bounds.width - 400, y: 6, width: 384, height: 28)
        buttonStackView.orientation = .horizontal
        buttonStackView.alignment = .centerY
        buttonStackView.spacing = buttonSpacing
        buttonStackView.distribution = .fill
        toolbarContainer.addSubview(buttonStackView)
        
        refreshButton.title = "Refresh"
        refreshButton.bezelStyle = .rounded
        refreshButton.target = self
        refreshButton.action = #selector(refreshButtonClicked)
        refreshButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        buttonStackView.addArrangedSubview(refreshButton)
        
        portCountLabel.stringValue = "Ports: 0"
        portCountLabel.isBordered = false
        portCountLabel.isEditable = false
        portCountLabel.drawsBackground = false
        portCountLabel.textColor = .secondaryLabelColor
        portCountLabel.font = NSFont.systemFont(ofSize: 12)
        portCountLabel.alignment = .center
        portCountLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        buttonStackView.addArrangedSubview(portCountLabel)
        
        monitorToggle.title = "Monitor"
        monitorToggle.setButtonType(.switch)
        monitorToggle.target = self
        monitorToggle.action = #selector(monitorToggleClicked)
        monitorToggle.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        buttonStackView.addArrangedSubview(monitorToggle)
        
        killButton.title = "Kill"
        killButton.bezelStyle = .rounded
        killButton.target = self
        killButton.action = #selector(killButtonClicked)
        killButton.isEnabled = false
        killButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        buttonStackView.addArrangedSubview(killButton)
        
        scrollView.frame = NSRect(x: margin, y: margin, width: view.bounds.width - margin * 2, height: view.bounds.height - toolbarHeight - margin * 2)
        scrollView.autohidesScrollers = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder
        view.addSubview(scrollView)
        
        tableView.frame = scrollView.bounds
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.gridStyleMask = .solidHorizontalGridLineMask
        tableView.rowHeight = 24
        
        let portColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("port"))
        portColumn.title = "Port"
        portColumn.width = 80
        portColumn.headerCell.alignment = .center
        portColumn.minWidth = 60
        tableView.addTableColumn(portColumn)
        
        let protocolColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("protocol"))
        protocolColumn.title = "Protocol"
        protocolColumn.width = 80
        protocolColumn.headerCell.alignment = .center
        protocolColumn.minWidth = 60
        tableView.addTableColumn(protocolColumn)
        
        let processColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("process"))
        processColumn.title = "Process"
        processColumn.width = 200
        processColumn.minWidth = 100
        tableView.addTableColumn(processColumn)
        
        let pidColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pid"))
        pidColumn.title = "PID"
        pidColumn.width = 80
        pidColumn.headerCell.alignment = .center
        pidColumn.minWidth = 60
        tableView.addTableColumn(pidColumn)
        
        scrollView.documentView = tableView
    }
    
    @objc private func refreshButtonClicked() {
        refreshPortDataAsync()
    }
    
    @objc private func killButtonClicked() {
        let selectedRow = tableView.selectedRow
        if selectedRow >= 0 && selectedRow < filteredPortInfos.count {
            let portInfo = filteredPortInfos[selectedRow]
            killProcess(pid: portInfo.processID)
            refreshPortDataAsync()
        }
    }
    
    @objc private func monitorToggleClicked() {
        isMonitoringEnabled = monitorToggle.state == .on
        if isMonitoringEnabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }
    
    private func startMonitoring() {
        // Stop any existing timer
        stopMonitoring()
        
        // Start new timer to refresh every 5 seconds
        portMonitoringTimer = Timer.scheduledTimer(timeInterval: 5.0, target: self, selector: #selector(monitorPorts), userInfo: nil, repeats: true)
        print("Port monitoring started")
    }
    
    private func stopMonitoring() {
        portMonitoringTimer?.invalidate()
        portMonitoringTimer = nil
        print("Port monitoring stopped")
    }
    
    @objc private func monitorPorts() {
        refreshPortDataAsync()
    }
    
    private func refreshPortDataAsync() {
        refreshButton.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let infos = Self.getPortInfo()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.portInfos = infos
                self.filteredPortInfos = infos
                self.tableView.reloadData()
                self.refreshButton.isEnabled = true
                self.portCountLabel.stringValue = "Ports: \(infos.count)"
            }
        }
    }
    
    private nonisolated static func getPortInfo() -> [PortInfo] {
        var result: [PortInfo] = []
        
        let bufferSize = proc_listallpids(nil, 0)
        guard bufferSize > 0 else { return [] }
        
        var pids = [pid_t](repeating: 0, count: Int(bufferSize) / MemoryLayout<pid_t>.size)
        let actualSize = proc_listallpids(&pids, bufferSize)
        guard actualSize > 0 else { return [] }
        
        let pidCount = Int(actualSize) / MemoryLayout<pid_t>.size
        
        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0 else { continue }
            
            let processName = getProcessName(pid: pid)
            
            let fds = getProcessFDs(pid: pid)
            for fd in fds {
                if let portInfo = getSocketInfo(pid: pid, fd: fd, processName: processName) {
                    result.append(portInfo)
                }
            }
        }
        
        let uniqueResults = Array(Set(result))
        print("Found \(uniqueResults.count) ports")
        return uniqueResults.sorted { $0.port < $1.port }
    }
    
    private nonisolated static func getProcessName(pid: pid_t) -> String {
        let maxPathSize = 4096
        var name = [CChar](repeating: 0, count: maxPathSize)
        let length = proc_name(pid, &name, UInt32(maxPathSize))
        if length > 0 {
            return String(cString: name)
        }
        return "Unknown"
    }
    
    private nonisolated static func getProcessFDs(pid: pid_t) -> [Int32] {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        
        let fdCount = Int(size) / MemoryLayout<proc_fdinfo>.size
        var fdInfos = [proc_fdinfo](repeating: proc_fdinfo(proc_fd: 0, proc_fdtype: 0), count: fdCount)
        
        let actualSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fdInfos, size)
        guard actualSize > 0 else { return [] }
        
        var fds: [Int32] = []
        let actualCount = Int(actualSize) / MemoryLayout<proc_fdinfo>.size
        for i in 0..<actualCount {
            if fdInfos[i].proc_fdtype == PROX_FDTYPE_SOCKET {
                fds.append(fdInfos[i].proc_fd)
            }
        }
        return fds
    }
    
    private nonisolated static func getSocketInfo(pid: pid_t, fd: Int32, processName: String) -> PortInfo? {
        var socketInfo = socket_fdinfo()
        let size = proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, &socketInfo, Int32(MemoryLayout<socket_fdinfo>.size))
        guard size > 0 else { return nil }
        
        let family = socketInfo.psi.soi_family
        let kind = socketInfo.psi.soi_kind
        
        guard family == 2 || family == 30 else {
            return nil
        }
        
        var port: Int = 0
        var protocolType = "TCP"
        
        if kind == 1 {
            protocolType = "UDP"
            let sin = socketInfo.psi.soi_proto.pri_in
            let portValue = UInt16(truncatingIfNeeded: sin.insi_lport)
            port = Int(UInt16(bigEndian: portValue))
        } else if kind == 2 {
            protocolType = "TCP"
            let tcp = socketInfo.psi.soi_proto.pri_tcp
            let portValue = UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport)
            port = Int(UInt16(bigEndian: portValue))
        } else {
            return nil
        }
        
        guard port > 0 && port <= 65535 else { return nil }
        
        return PortInfo(port: port, processName: processName, processID: Int(pid), protocolType: protocolType)
    }
    

    
    private func killProcess(pid: Int) {
        let result = Darwin.kill(pid_t(pid), SIGKILL)
        if result == 0 {
            print("Killed process \(pid)")
        } else {
            print("Error killing process \(pid): \(errno)")
        }
    }
    
    // MARK: - NSTableViewDataSource
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return filteredPortInfos.count
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let portInfo = filteredPortInfos[row]
        
        if tableColumn?.identifier == NSUserInterfaceItemIdentifier("port") {
            return portInfo.port
        } else if tableColumn?.identifier == NSUserInterfaceItemIdentifier("protocol") {
            return portInfo.protocolType
        } else if tableColumn?.identifier == NSUserInterfaceItemIdentifier("process") {
            return portInfo.processName
        } else if tableColumn?.identifier == NSUserInterfaceItemIdentifier("pid") {
            return portInfo.processID
        }
        
        return nil
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let portInfo = filteredPortInfos[row]
        
        let cellIdentifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")
        
        // Create a container view for vertical centering
        var cellView: NSTableCellView
        
        if let existingView = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView {
            cellView = existingView
        } else {
            cellView = NSTableCellView()
            cellView.identifier = cellIdentifier
            
            let textField = NSTextField()
            textField.isBordered = false
            textField.isEditable = false
            textField.drawsBackground = false
            textField.lineBreakMode = .byTruncatingTail
            textField.translatesAutoresizingMaskIntoConstraints = false
            
            cellView.addSubview(textField)
            
            // Set constraints for vertical centering
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
            ])
        }
        
        guard let textField = cellView.subviews.first as? NSTextField else {
            return cellView
        }
        
        let font = NSFont.systemFont(ofSize: 13)
        textField.font = font
        textField.alignment = .center
        
        let isSelected = tableView.selectedRowIndexes.contains(row)
        
        if cellIdentifier.rawValue == "port" {
            textField.stringValue = "\(portInfo.port)"
        } else if cellIdentifier.rawValue == "protocol" {
            textField.stringValue = portInfo.protocolType
        } else if cellIdentifier.rawValue == "process" {
            textField.stringValue = portInfo.processName
            textField.alignment = .left
        } else if cellIdentifier.rawValue == "pid" {
            textField.stringValue = "\(portInfo.processID)"
        }
        
        if isSelected {
            textField.textColor = .white
            textField.backgroundColor = .selectedContentBackgroundColor
        } else {
            textField.textColor = .labelColor
            textField.backgroundColor = .clear
        }
        
        return cellView
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 28
    }
    
    // MARK: - NSTableViewDelegate
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        killButton.isEnabled = tableView.selectedRow >= 0
    }
    
    // MARK: - NSSearchFieldDelegate
    
    func controlTextDidChange(_ obj: Notification) {
        if let searchField = obj.object as? NSSearchField {
            let searchText = searchField.stringValue.lowercased()
            
            if searchText.isEmpty {
                filteredPortInfos = portInfos
            } else {
                filteredPortInfos = portInfos.filter { info in
                    return "\(info.port)".contains(searchText) ||
                           info.processName.lowercased().contains(searchText) ||
                           "\(info.processID)".contains(searchText) ||
                           info.protocolType.lowercased().contains(searchText)
                }
            }
            
            // Sort by port number
            filteredPortInfos.sort { $0.port < $1.port }
            tableView.reloadData()
        }
    }
    
    // MARK: - NSWindowDelegate
    
    func windowDidResize(_ notification: Notification) {
        // Update UI layout when window is resized
        updateLayout()
    }
    
    private func updateLayout() {
        let toolbarHeight: CGFloat = 40
        let margin: CGFloat = 16
        
        toolbarContainer.frame = NSRect(x: 0, y: view.bounds.height - toolbarHeight, width: view.bounds.width, height: toolbarHeight)
        
        buttonStackView.frame = NSRect(x: view.bounds.width - 400, y: 6, width: 384, height: 28)
        
        scrollView.frame = NSRect(x: margin, y: margin, width: view.bounds.width - margin * 2, height: view.bounds.height - toolbarHeight - margin * 2)
    }
}
