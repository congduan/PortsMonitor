import AppKit
import Foundation
import Darwin


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
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 20, width: view.bounds.width - 40, height: view.bounds.height - 80))
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
        
        let task = Process()
        task.launchPath = "/usr/sbin/lsof"
        task.arguments = ["-i", "-P", "-n", "-sTCP:LISTEN", "-sTCP:ESTABLISHED"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.split(separator: "\n")
                for line in lines {
                    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                    guard parts.count >= 9 else { continue }
                    
                    let processName = String(parts[0])
                    guard let processID = Int(parts[1]), processID > 0 else { continue }
                    
                    var protocolType = "TCP"
                    let protoField = String(parts[7])
                    if protoField.hasPrefix("UDP") {
                        protocolType = "UDP"
                    }
                    
                    let nameField = String(parts[8])
                    
                    var port: Int?
                    if nameField.contains(":") {
                        let components = nameField.split(separator: ":")
                        if let lastComponent = components.last {
                            let portStr = String(lastComponent)
                            port = Int(portStr)
                        }
                    }
                    
                    guard let validPort = port, validPort > 0, validPort <= 65535 else { continue }
                    
                    result.append(PortInfo(port: validPort, processName: processName, processID: processID, protocolType: protocolType))
                }
            }
        } catch {
            print("Error running lsof: \(error)")
        }
        
        let uniqueResults = Array(Set(result))
        print("Found \(uniqueResults.count) ports")
        return uniqueResults.sorted { $0.port < $1.port }
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
        if let scrollView = tableView.superview as? NSScrollView {
            scrollView.frame = NSRect(x: 20, y: 20, width: view.bounds.width - 40, height: view.bounds.height - 80)
        }
    }
}
