import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panels: [NSPanel] = []
    private var lastMouseLocation = NSEvent.mouseLocation
    private var cursorColor: GradientColor = .transparent
    private var cursorRadius: CGFloat = 100
    private var lastConfigError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshConfiguration()
        updatePanels()
        let configTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshConfiguration()
        }
        RunLoop.main.add(configTimer, forMode: .common)
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.updateMouseLocation()
        }
        RunLoop.main.add(timer, forMode: .common)
        NotificationCenter.default.addObserver(self, selector: #selector(updatePanels), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private func updateMouseLocation() {
        guard cursorColor != .black else { return }
        let location = NSEvent.mouseLocation
        guard location != lastMouseLocation else { return }
        for panel in panels where panel.frame.contains(location) || panel.frame.contains(lastMouseLocation) {
            panel.contentView?.needsDisplay = true
        }
        lastMouseLocation = location
    }

    private func refreshConfiguration() {
        do {
            let color = try configuration.cursorColor()
            let radius = CGFloat(try configuration.cursorRadius())
            lastConfigError = nil
            guard color != cursorColor || radius != cursorRadius else { return }
            cursorColor = color
            cursorRadius = radius
            for panel in panels {
                guard let view = panel.contentView as? BackdropView else { continue }
                view.cursorColor = color
                view.cursorRadius = radius
                view.needsDisplay = true
            }
        } catch {
            if lastConfigError != error.localizedDescription {
                fputs("Configuration error: \(error.localizedDescription)\n", stderr)
                lastConfigError = error.localizedDescription
            }
        }
    }

    @objc private func updatePanels() {
        panels.forEach { $0.close() }
        panels = NSScreen.screens.map { screen in
            let height = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
            let panel = NSPanel(contentRect: NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .mainMenu
            panel.backgroundColor = .clear
            panel.isOpaque = false
            let view = BackdropView(frame: NSRect(origin: .zero, size: panel.frame.size))
            view.cursorColor = cursorColor
            view.cursorRadius = cursorRadius
            panel.contentView = view
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.orderFrontRegardless()
            return panel
        }
    }
}

final class BackdropView: NSView {
    var cursorColor: GradientColor = .transparent
    var cursorRadius: CGFloat = 100

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard cursorColor != .black, let window, let context = NSGraphicsContext.current?.cgContext else { return }
        let screenPoint = NSEvent.mouseLocation
        guard window.frame.contains(screenPoint) else { return }
        let center = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        let value = cursorColor.value
        let color = NSColor(srgbRed: CGFloat((value >> 24) & 255) / 255, green: CGFloat((value >> 16) & 255) / 255, blue: CGFloat((value >> 8) & 255) / 255, alpha: CGFloat(value & 255) / 255)
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color.cgColor, NSColor.black.cgColor] as CFArray, locations: [0, 1])!
        context.saveGState()
        context.addEllipse(in: CGRect(x: center.x - cursorRadius, y: center.y - cursorRadius, width: cursorRadius * 2, height: cursorRadius * 2))
        context.clip()
        context.setBlendMode(.copy)
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: cursorRadius, options: [])
        context.restoreGState()
    }
}

let label = "com.hide-a-hole.agent"
let fileManager = FileManager.default
let home = fileManager.homeDirectoryForCurrentUser
let agentURL = home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
let binaryURL = home.appendingPathComponent("Library/Application Support/hide-a-hole/hide-a-hole")
let configuration = Configuration(url: binaryURL.deletingLastPathComponent().appendingPathComponent("config.json"))
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
    case "help", "--help", "-h":
        print("""
        Usage: hide-a-hole [command]

        Without a command, run in the foreground until Ctrl+C.

        Commands:
          help, --help, -h       Show this help
          install                Install and start the login service
          uninstall              Stop and remove the login service
          status                 Check service registration
          cursor-color #RRGGBBAA Set gradient center color and opacity
          cursor-radius NUMBER   Set radius in macOS points (1–10000, default: 100)

        Color examples: '#00000000' transparent, '#FF000080' semi-transparent red,
                        '#000000FF' solid black (no visible effect).
        Configuration: ~/Library/Application Support/hide-a-hole/config.json
        Changes apply within one second; uninstall preserves the configuration.
        """)
    case "install":
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath()
        try fileManager.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: binaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if try launchctl(["print", "\(domain)/\(label)"], quiet: true) == 0 {
            guard try launchctl(["bootout", "\(domain)/\(label)"]) == 0 else {
                throw ServiceError("Could not stop the existing service.")
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
            throw ServiceError("Could not start the service. Run this command in a macOS graphical session.")
        }
        if fileManager.fileExists(atPath: oldBinaryURL.path) { try fileManager.removeItem(at: oldBinaryURL) }
        print("Service installed and started. It will start at login.")
    case "uninstall":
        if try launchctl(["print", "\(domain)/\(label)"], quiet: true) == 0 {
            guard try launchctl(["bootout", "\(domain)/\(label)"]) == 0 else {
                throw ServiceError("Could not stop the service.")
            }
        }
        if fileManager.fileExists(atPath: agentURL.path) { try fileManager.removeItem(at: agentURL) }
        if fileManager.fileExists(atPath: binaryURL.path) { try fileManager.removeItem(at: binaryURL) }
        if fileManager.fileExists(atPath: oldBinaryURL.path) { try fileManager.removeItem(at: oldBinaryURL) }
        print("Service removed.")
    case "status":
        if try launchctl(["print", "\(domain)/\(label)"], quiet: true) == 0 {
            print("Service is registered in the current session.")
        } else {
            print("Service is not registered in the current session.")
            exit(1)
        }
    default:
        throw ServiceError("Usage: hide-a-hole [help|install|uninstall|status|cursor-color #RRGGBBAA|cursor-radius NUMBER]")
    }
}

struct ServiceError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

if CommandLine.arguments.count > 1 {
    do {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.count == 2 && args[0] == "cursor-color" {
            let color = try GradientColor(args[1])
            try configuration.setCursorColor(color)
            print("Cursor color: \(color.hex).")
        } else if args.count == 2 && args[0] == "cursor-radius" {
            guard let radius = Double(args[1]) else { throw ServiceError("Radius must be a number between 1 and 10000.") }
            try configuration.setCursorRadius(radius)
            print("Cursor radius: \(radius) pt.")
        } else if args.count == 1 {
            try manageService(args[0])
        } else {
            throw ServiceError("Usage: hide-a-hole [help|install|uninstall|status|cursor-color #RRGGBBAA|cursor-radius NUMBER]")
        }
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
