import AppKit

func containsCursor(_ point: CGPoint, in frame: CGRect) -> Bool {
    frame.contains(point) || (frame.width > 0 && frame.height > 0 && point.y == frame.maxY && point.x >= frame.minX && point.x < frame.maxX)
}

func collapsedFrame(_ frame: CGRect) -> CGRect {
    CGRect(x: frame.midX - 0.5, y: frame.minY, width: 1, height: frame.height)
}

func shouldShowBackdrop(for appearance: NSAppearance?) -> Bool {
    appearance?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
}

final class AppearanceObserverView: NSView {
    var onChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onChange?()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panels: [NSPanel] = []
    private var fullFrames: [NSPanel: CGRect] = [:]
    private var animationGeneration = 0
    private var appearanceItem: NSStatusItem!
    private var appearanceUpdate: DispatchWorkItem?
    private var probeSized = false
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var showBackdrop = false
    private var lastMouseLocation = NSEvent.mouseLocation
    private var cursorColor: GradientColor = .transparent
    private var cursorRadius: CGFloat = 100
    private var lastConfigError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appearanceItem = NSStatusBar.system.statusItem(withLength: 0)
        appearanceItem.isVisible = true
        if let button = appearanceItem.button {
            let observer = AppearanceObserverView(frame: .zero)
            observer.onChange = { [weak self] in self?.scheduleAppearanceUpdate() }
            button.addSubview(observer)
            if let window = button.window {
                NotificationCenter.default.addObserver(self, selector: #selector(probeWindowResized), name: NSWindow.didResizeNotification, object: window)
            }
        }
        refreshConfiguration()
        scheduleAppearanceUpdate()
        updatePanels()
        let configTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshConfiguration()
        }
        RunLoop.main.add(configTimer, forMode: .common)
        let mouseEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            self?.updateMouseLocation()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            self?.updateMouseLocation()
            return event
        }
        if mouseMonitor == nil {
            // shortcut: poll if AppKit cannot install a global monitor; remove once monitoring is guaranteed.
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                self?.updateMouseLocation()
            }
            RunLoop.main.add(timer, forMode: .common)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(updatePanels), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private func updateMouseLocation() {
        guard showBackdrop, cursorColor != .black else { return }
        let location = NSEvent.mouseLocation
        guard location != lastMouseLocation else { return }
        for panel in panels where containsCursor(location, in: panel.frame) || containsCursor(lastMouseLocation, in: panel.frame) {
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

    @objc private func probeWindowResized() {
        if !probeSized { scheduleAppearanceUpdate() }
    }

    private func scheduleAppearanceUpdate() {
        appearanceUpdate?.cancel()
        let update = DispatchWorkItem { [weak self] in self?.refreshAppearance() }
        appearanceUpdate = update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: update)
    }

    private func refreshAppearance() {
        if !probeSized, let window = appearanceItem.button?.window, window.frame.height > 0, let content = window.contentView,
           let constraint = content.constraintsAffectingLayout(for: .horizontal).first(where: {
               $0.firstItem as? NSView === content && $0.firstAttribute == .width && $0.secondAttribute == .width && $0.constant == 16
           }) {
            // shortcut: AppKit's status-item padding constraint may change, then the probe occupies its normal width.
            probeSized = true
            constraint.isActive = false
            window.setContentSize(NSSize(width: 1, height: window.frame.height))
        }
        let show = shouldShowBackdrop(for: appearanceItem.button?.effectiveAppearance)
        guard show != showBackdrop else { return }
        showBackdrop = show
        animationGeneration += 1
        let generation = animationGeneration
        for panel in panels {
            guard let fullFrame = fullFrames[panel] else { continue }
            if show && !panel.isVisible {
                panel.setFrame(collapsedFrame(fullFrame), display: true)
                panel.orderFrontRegardless()
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                panel.animator().setFrame(show ? fullFrame : collapsedFrame(fullFrame), display: true)
            } completionHandler: { [weak self, weak panel] in
                guard let self, let panel, self.animationGeneration == generation, !self.showBackdrop else { return }
                panel.orderOut(nil)
            }
        }
    }

    @objc private func updatePanels() {
        animationGeneration += 1
        panels.forEach { $0.close() }
        fullFrames.removeAll()
        panels = NSScreen.screens.map { screen in
            let height = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
            let panel = NSPanel(contentRect: NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .mainMenu
            panel.backgroundColor = .clear
            panel.isOpaque = false
            fullFrames[panel] = panel.frame
            let view = BackdropView(frame: NSRect(origin: .zero, size: panel.frame.size))
            view.autoresizingMask = [.width, .height]
            view.cursorColor = cursorColor
            view.cursorRadius = cursorRadius
            panel.contentView = view
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            if showBackdrop { panel.orderFrontRegardless() }
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
        guard containsCursor(screenPoint, in: window.frame) else { return }
        let center = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        drawCursorGradient(in: context, center: center, radius: cursorRadius, color: cursorColor)
    }
}

func drawCursorGradient(in context: CGContext, center: CGPoint, radius: CGFloat, color: GradientColor) {
    let value = color.value
    let centerColor = NSColor(srgbRed: CGFloat((value >> 24) & 255) / 255, green: CGFloat((value >> 16) & 255) / 255, blue: CGFloat((value >> 8) & 255) / 255, alpha: CGFloat(value & 255) / 255)
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [centerColor.cgColor, NSColor.black.cgColor] as CFArray, locations: [0, 1])!
    context.saveGState()
    context.setBlendMode(.copy)
    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: .drawsAfterEndLocation)
    context.restoreGState()
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
