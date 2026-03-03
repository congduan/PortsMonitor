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
    
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let searchField = NSSearchField()
    private let refreshButton = NSButton()
    private let killButton = NSButton()
    
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
        // Search field
        searchField.frame = NSRect(x: 20, y: view.bounds.height - 40, width: view.bounds.width - 180, height: 25)
        searchField.delegate = self
        searchField.placeholderString = "Search ports..."
        view.addSubview(searchField)
        
        // Refresh button
        refreshButton.frame = NSRect(x: view.bounds.width - 150, y: view.bounds.height - 40, width: 65, height: 25)
        refreshButton.title = "Refresh"
        refreshButton.target = self
        refreshButton.action = #selector(refreshButtonClicked)
        view.addSubview(refreshButton)
        
        // Kill button
        killButton.frame = NSRect(x: view.bounds.width - 80, y: view.bounds.height - 40, width: 65, height: 25)
        killButton.title = "Kill"
        killButton.target = self
        killButton.action = #selector(killButtonClicked)
        killButton.isEnabled = false
        view.addSubview(killButton)
        
        // Table view
        scrollView.frame = NSRect(x: 20, y: 20, width: view.bounds.width - 40, height: view.bounds.height - 80)
        scrollView.autohidesScrollers = false
        view.addSubview(scrollView)
        
        tableView.frame = scrollView.bounds
        tableView.delegate = self
        tableView.dataSource = self
        
        let portColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("port"))
        portColumn.title = "Port"
        portColumn.width = 80
        tableView.addTableColumn(portColumn)
        
        let protocolColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("protocol"))
        protocolColumn.title = "Protocol"
        protocolColumn.width = 80
        tableView.addTableColumn(protocolColumn)
        
        let processColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("process"))
        processColumn.title = "Process"
        processColumn.width = 200
        tableView.addTableColumn(processColumn)
        
        let pidColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pid"))
        pidColumn.title = "PID"
        pidColumn.width = 80
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
    
    private func refreshPortDataAsync() {
        refreshButton.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let infos = Self.getPortInfo()
            DispatchQueue.main.async {
                self.portInfos = infos
                self.filteredPortInfos = infos
                self.tableView.reloadData()
                self.refreshButton.isEnabled = true
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
        let task = Process()
        task.launchPath = "/usr/bin/kill"
        task.arguments = ["-9", "\(pid)"]
        
        do {
            try task.run()
            task.waitUntilExit()
            print("Killed process \(pid)")
        } catch {
            print("Error killing process: \(error)")
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
            
            tableView.reloadData()
        }
    }
    
    // MARK: - NSWindowDelegate
    
    func windowDidResize(_ notification: Notification) {
        // Update UI layout when window is resized
        updateLayout()
    }
    
    private func updateLayout() {
        // Update search field frame
        searchField.frame = NSRect(x: 20, y: view.bounds.height - 40, width: view.bounds.width - 180, height: 25)
        
        // Update refresh button frame
        refreshButton.frame = NSRect(x: view.bounds.width - 150, y: view.bounds.height - 40, width: 65, height: 25)
        
        // Update kill button frame
        killButton.frame = NSRect(x: view.bounds.width - 80, y: view.bounds.height - 40, width: 65, height: 25)
        
        // Update scroll view frame
        scrollView.frame = NSRect(x: 20, y: 20, width: view.bounds.width - 40, height: view.bounds.height - 80)
    }
}
