import ApplicationServices
import Cocoa
import Foundation

// MARK: - Data Structures

struct WindowInfo: Codable {
    let id: CGWindowID
    let title: String
    let isCurrentlyActive: Bool
}

struct StatusResponse: Codable {
    let hasAccessibilityPermission: Bool
}

struct GetWindowsRequest: Codable {
    let newWindowPosition: String
    let activationMode: String
}

struct ActivateWindowRequest: Codable {
    let id: CGWindowID
}

// MARK: - Helper Application

class BacktickPlusPlusHelper {
    private static let socketPath = "/tmp/backtick-plus-plus-helper.sock"
    private var server: CFSocket?
    private var runLoop: CFRunLoop?
    private var windowOrder: [CGWindowID] = []

    func start() {
        // Check if another instance is already running
        if !bindToSocket() {
            print("Another instance is already running. Exiting.")
            exit(0)
        }

        print("Backtick++ Helper started")

        // Start the run loop
        runLoop = CFRunLoopGetCurrent()
        CFRunLoopRun()
    }

    private func bindToSocket() -> Bool {
        // Remove existing socket file if it exists
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: Self.socketPath) {
            try? fileManager.removeItem(atPath: Self.socketPath)
        }

        // Create socket
        var context = CFSocketContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let callback: CFSocketCallBack = { socket, callbackType, address, data, info in
            let helper = Unmanaged<BacktickPlusPlusHelper>.fromOpaque(info!).takeUnretainedValue()
            helper.handleConnection(socket: socket!, address: address, data: data)
        }

        server = CFSocketCreate(
            kCFAllocatorDefault,
            PF_UNIX,
            SOCK_STREAM,
            0,
            CFSocketCallBackType.acceptCallBack.rawValue,
            callback,
            &context
        )

        guard let server = server else {
            return false
        }

        // Bind to socket path
        let addr = sockaddr_un.unix(path: Self.socketPath)
        let data = withUnsafePointer(to: addr) { pointer in
            Data(bytes: pointer, count: MemoryLayout<sockaddr_un>.size)
        }

        let address = data.withUnsafeBytes { bytes in
            CFDataCreate(
                kCFAllocatorDefault, bytes.bindMemory(to: UInt8.self).baseAddress, data.count)
        }

        let result = CFSocketSetAddress(server, address)
        if result != .success {
            return false
        }

        // Add to run loop
        let source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, server, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)

        return true
    }

    private func handleConnection(socket: CFSocket, address: CFData?, data: UnsafeRawPointer?) {
        let clientSocket = CFSocketGetNative(socket)

        // Accept the connection
        var clientAddr = sockaddr()
        var clientAddrLen = socklen_t(MemoryLayout<sockaddr>.size)
        let client = accept(clientSocket, &clientAddr, &clientAddrLen)

        if client == -1 {
            return
        }

        // Read the command
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(client, &buffer, buffer.count)

        if bytesRead > 0 {
            let command = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
            let response = handleCommand(command)

            let responseData = response.data(using: .utf8) ?? Data()
            _ = responseData.withUnsafeBytes { bytes in
                write(client, bytes.bindMemory(to: UInt8.self).baseAddress, responseData.count)
            }
        }

        close(client)
    }

    private func handleCommand(_ command: String) -> String {
        let parts = command.components(separatedBy: ":")
        let cmd = parts[0]
        let data = parts.count > 1 ? parts[1...].joined(separator: ":") : ""

        switch cmd {
        case "getStatus":
            return handleGetStatus()
        case "requestPermission":
            return handleRequestPermission()
        case "getWindows":
            return handleGetWindows(data)
        case "activateWindow":
            return handleActivateWindow(data)
        case "shutdown":
            return handleShutdown()
        default:
            return "ERROR:Unknown command"
        }
    }

    private func handleGetStatus() -> String {
        let hasPermission = AXIsProcessTrustedWithOptions(nil)

        let response = StatusResponse(hasAccessibilityPermission: hasPermission)

        do {
            let jsonData = try JSONEncoder().encode(response)
            return "OK:" + String(data: jsonData, encoding: .utf8)!
        } catch {
            return "ERROR:Failed to encode status response"
        }
    }

    private func handleRequestPermission() -> String {
        // Check if we're running as a bundled app
        let bundle = Bundle.main
        if bundle.bundleIdentifier != nil {
            // Trigger permission prompt
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }

        return "OK:"
    }

    private func handleGetWindows(_ data: String) -> String {
        do {
            let request = try JSONDecoder().decode(
                GetWindowsRequest.self, from: data.data(using: .utf8)!)

            // Get current VS Code windows
            let currentWindows = getVSCodeWindows()

            // Handle activation mode
            if request.activationMode == "automatic" {
                updateWindowOrderWithFrontmost(currentWindows)
            }

            // Update window order with new/closed windows
            updateWindowOrder(currentWindows, newWindowPosition: request.newWindowPosition)

            // Build response
            let windowInfos = windowOrder.compactMap { windowId in
                currentWindows.first { $0.id == windowId }
            }.map { window in
                WindowInfo(
                    id: window.id,
                    title: window.title,
                    isCurrentlyActive: window.isCurrentlyActive
                )
            }

            let jsonData = try JSONEncoder().encode(windowInfos)
            return "OK:" + String(data: jsonData, encoding: .utf8)!
        } catch {
            return "ERROR:Failed to get windows: \(error)"
        }
    }

    private func handleActivateWindow(_ data: String) -> String {
        do {
            let request = try JSONDecoder().decode(
                ActivateWindowRequest.self, from: data.data(using: .utf8)!)

            if activateWindowWithId(request.id) {
                // Move activated window to top of order
                windowOrder.removeAll { $0 == request.id }
                windowOrder.insert(request.id, at: 0)
                return "OK:"
            } else {
                return "ERROR:Failed to activate window"
            }
        } catch {
            return "ERROR:Failed to parse activate window request"
        }
    }

    private func handleShutdown() -> String {
        DispatchQueue.main.async {
            exit(0)
        }
        return "OK:"
    }

    // MARK: - Window Management

    private func getVSCodeWindows() -> [(id: CGWindowID, title: String, isCurrentlyActive: Bool)] {
        guard
            let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
                as? [[String: Any]]
        else {
            return []
        }

        var windows: [(id: CGWindowID, title: String, isCurrentlyActive: Bool)] = []
        var frontmostWindow: CGWindowID?

        // Get the frontmost window
        if let frontmostApp = NSWorkspace.shared.frontmostApplication,
            let frontmostPID = frontmostApp.processIdentifier as pid_t?,
            frontmostApp.bundleIdentifier?.contains("com.microsoft.VSCode") == true
        {

            for windowInfo in windowList {
                if let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                    pid == frontmostPID,
                    let windowId = windowInfo[kCGWindowNumber as String] as? CGWindowID
                {
                    frontmostWindow = windowId
                    break
                }
            }
        }

        for windowInfo in windowList {
            guard let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                ownerName.contains("Code") || ownerName.contains("Visual Studio Code"),
                let windowId = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                let windowTitle = windowInfo[kCGWindowName as String] as? String,
                !windowTitle.isEmpty
            else {
                continue
            }

            // Skip non-document windows
            if windowTitle.contains("— ") || windowTitle.contains("Visual Studio Code") {
                let isActive = windowId == frontmostWindow
                windows.append((id: windowId, title: windowTitle, isCurrentlyActive: isActive))
            }
        }

        return windows
    }

    private func updateWindowOrderWithFrontmost(
        _ currentWindows: [(id: CGWindowID, title: String, isCurrentlyActive: Bool)]
    ) {
        if let frontmost = currentWindows.first(where: { $0.isCurrentlyActive }) {
            windowOrder.removeAll { $0 == frontmost.id }
            windowOrder.insert(frontmost.id, at: 0)
        }
    }

    private func updateWindowOrder(
        _ currentWindows: [(id: CGWindowID, title: String, isCurrentlyActive: Bool)],
        newWindowPosition: String
    ) {
        let currentWindowIds = Set(currentWindows.map { $0.id })

        // Remove closed windows
        windowOrder.removeAll { !currentWindowIds.contains($0) }

        // Add new windows
        let existingWindowIds = Set(windowOrder)
        let newWindowIds = currentWindowIds.subtracting(existingWindowIds)

        for windowId in newWindowIds {
            if newWindowPosition.lowercased() == "top" {
                windowOrder.insert(windowId, at: 0)
            } else {
                windowOrder.append(windowId)
            }
        }
    }

    private func activateWindowWithId(_ windowId: CGWindowID) -> Bool {
        // Get the window info
        guard
            let windowList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
                as? [[String: Any]]
        else {
            return false
        }

        var targetPID: pid_t?

        for windowInfo in windowList {
            if let id = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                id == windowId,
                let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t
            {
                targetPID = pid
                break
            }
        }

        guard let pid = targetPID else {
            return false
        }

        // Get the application
        let app = NSRunningApplication(processIdentifier: pid)

        // Activate the application first
        if #available(macOS 14.0, *) {
            app?.activate()
        } else {
            app?.activate(options: [.activateIgnoringOtherApps])
        }

        // Use Accessibility API to focus the specific window
        let appRef = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appRef, kAXWindowsAttribute as CFString, &windowsRef)

        if result == .success,
            let windows = windowsRef as? [AXUIElement]
        {

            for window in windows {
                var windowIdRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(
                    window, kAXIdentifierAttribute as CFString, &windowIdRef) == .success,
                    let windowIdNum = windowIdRef as? NSNumber,
                    windowIdNum.uint32Value == windowId
                {

                    // Raise and focus the window
                    AXUIElementSetAttributeValue(
                        window, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                    return true
                }
            }

            // Fallback: just raise the first window
            if let firstWindow = windows.first {
                AXUIElementSetAttributeValue(
                    firstWindow, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(firstWindow, kAXRaiseAction as CFString)
                return true
            }
        }

        return false
    }
}

// MARK: - Unix Socket Helper

extension sockaddr_un {
    static func unix(path: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = path.utf8CString
        let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
        let pathLength = min(pathBytes.count - 1, maxPathLength - 1)

        withUnsafeMutablePointer(to: &addr.sun_path.0) { pathPtr in
            pathBytes.prefix(pathLength).withUnsafeBufferPointer { buffer in
                pathPtr.initialize(from: buffer.baseAddress!, count: pathLength)
            }
        }

        // Set sun_len field for BSD systems
        let sunLenSize = MemoryLayout<UInt8>.size + MemoryLayout<sa_family_t>.size + pathLength
        addr.sun_len = UInt8(sunLenSize)

        return addr
    }
}

// MARK: - Main Entry Point

let helper = BacktickPlusPlusHelper()
helper.start()
