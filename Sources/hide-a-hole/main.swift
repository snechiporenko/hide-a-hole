import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panels: [NSPanel] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        updatePanels()
        NotificationCenter.default.addObserver(self, selector: #selector(updatePanels), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func updatePanels() {
        panels.forEach { $0.close() }
        panels = NSScreen.screens.map { screen in
            let height = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
            let panel = NSPanel(contentRect: NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .mainMenu
            panel.backgroundColor = .black
            panel.isOpaque = true
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.orderFrontRegardless()
            return panel
        }
    }
}

let label = "com.hide-a-hole.agent"
let fileManager = FileManager.default
let home = fileManager.homeDirectoryForCurrentUser
let agentURL = home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
let binaryURL = home.appendingPathComponent("Library/Application Support/hide-a-hole/hide-a-hole")
let oldBinaryURL = binaryURL.deletingLastPathComponent().appendingPathComponent("HideAHole")
let domain = "gui/\(getuid())"

@discardableResult
func launchctl(_ arguments: [String], quiet: Bool = false) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    if quiet {
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
    }
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

func manageService(_ command: String) throws {
    switch command {
    case "install":
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
        try fileManager.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: binaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if try launchctl(["print", "\(domain)/\(label)"], quiet: true) == 0 {
            guard try launchctl(["bootout", "\(domain)/\(label)"]) == 0 else {
                throw ServiceError("Не удалось остановить существующий сервис.")
            }
        }
        if executable != binaryURL {
            let data = try Data(contentsOf: executable)
            try data.write(to: binaryURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
        }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [binaryURL.path],
            "RunAtLoad": true,
            "KeepAlive": true
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: agentURL, options: .atomic)
        guard try launchctl(["bootstrap", domain, agentURL.path]) == 0 else {
            try fileManager.removeItem(at: agentURL)
            throw ServiceError("Не удалось запустить сервис. Проверьте, что команда выполняется в графической сессии macOS.")
        }
        if fileManager.fileExists(atPath: oldBinaryURL.path) { try fileManager.removeItem(at: oldBinaryURL) }
        print("Сервис установлен и запущен. Он будет запускаться при входе в систему.")
    case "uninstall":
        if try launchctl(["print", "\(domain)/\(label)"], quiet: true) == 0 {
            guard try launchctl(["bootout", "\(domain)/\(label)"]) == 0 else {
                throw ServiceError("Не удалось остановить сервис.")
            }
        }
        if fileManager.fileExists(atPath: agentURL.path) { try fileManager.removeItem(at: agentURL) }
        if fileManager.fileExists(atPath: binaryURL.path) { try fileManager.removeItem(at: binaryURL) }
        if fileManager.fileExists(atPath: oldBinaryURL.path) { try fileManager.removeItem(at: oldBinaryURL) }
        print("Сервис удалён.")
    case "status":
        if try launchctl(["print", "\(domain)/\(label)"], quiet: true) == 0 {
            print("Сервис зарегистрирован в текущей сессии.")
        } else {
            print("Сервис не зарегистрирован в текущей сессии.")
            exit(1)
        }
    default:
        throw ServiceError("Использование: hide-a-hole [install|uninstall|status]")
    }
}

struct ServiceError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

if CommandLine.arguments.count > 1 {
    do {
        guard CommandLine.arguments.count == 2 else { throw ServiceError("Использование: hide-a-hole [install|uninstall|status]") }
        try manageService(CommandLine.arguments[1])
        exit(0)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
