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
        print("=== Backtick++ Helper Starting ===")

        // Set up signal handlers for cleanup
        setupSignalHandlers()

        // Check if another instance is already running
        print("Checking for existing instances...")
        if !bindToSocket() {
            print("ERROR: Another instance is already running. Exiting.")
            exit(0)
        }
        print("✓ Socket bound successfully")

        print("Backtick++ Helper started successfully")
        print("Socket path: \(Self.socketPath)")

        // Start the run loop
        print("Starting CFRunLoop...")
        runLoop = CFRunLoopGetCurrent()
        print("Entering run loop - helper is now listening for connections")
        CFRunLoopRun()
    }

    private func setupSignalHandlers() {
        print("⚡ Setting up signal handlers for cleanup...")

        // Handle SIGTERM (normal termination)
        signal(SIGTERM) { _ in
            print("🛑 Received SIGTERM - cleaning up...")
            BacktickPlusPlusHelper.cleanup()
            exit(0)
        }

        // Handle SIGINT (Ctrl+C)
        signal(SIGINT) { _ in
            print("🛑 Received SIGINT - cleaning up...")
            BacktickPlusPlusHelper.cleanup()
            exit(0)
        }

        // Handle SIGHUP (terminal hangup)
        signal(SIGHUP) { _ in
            print("🛑 Received SIGHUP - cleaning up...")
            BacktickPlusPlusHelper.cleanup()
            exit(0)
        }

        // Handle SIGQUIT (quit signal)
        signal(SIGQUIT) { _ in
            print("🛑 Received SIGQUIT - cleaning up...")
            BacktickPlusPlusHelper.cleanup()
            exit(0)
        }

        // Handle SIGPIPE (broken pipe)
        signal(SIGPIPE) { _ in
            print("🛑 Received SIGPIPE - cleaning up...")
            BacktickPlusPlusHelper.cleanup()
            exit(0)
        }

        // Set up at-exit handler for other termination scenarios
        atexit {
            print("🧹 atexit handler called - performing final cleanup...")
            BacktickPlusPlusHelper.cleanup()
        }

        print("✅ Signal handlers and exit handlers set up")
    }

    static func cleanup() {
        print("🧹 Static cleanup function called...")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: socketPath) {
            print("🗑️  Removing socket file at exit...")
            do {
                try fileManager.removeItem(atPath: socketPath)
                print("✅ Socket file removed successfully during cleanup")
            } catch {
                print("⚠️  Failed to remove socket file during cleanup: \(error)")
            }
        } else {
            print("ℹ️  No socket file to clean up")
        }
    }

    private func bindToSocket() -> Bool {
        print("🔌 Starting socket binding process...")

        // Remove existing socket file if it exists (handles dirty quits)
        let fileManager = FileManager.default
        print("📁 Checking for existing socket file at: \(Self.socketPath)")
        if fileManager.fileExists(atPath: Self.socketPath) {
            print("⚠️  Found existing socket file - checking if it's stale...")

            // Try to connect to existing socket to see if it's active
            let testSocket = socket(AF_UNIX, SOCK_STREAM, 0)
            if testSocket != -1 {
                var addr = sockaddr_un()
                addr.sun_family = sa_family_t(AF_UNIX)
                let pathBytes = Self.socketPath.utf8CString
                let pathLength = min(
                    pathBytes.count - 1, MemoryLayout.size(ofValue: addr.sun_path) - 1)

                withUnsafeMutablePointer(to: &addr.sun_path.0) { pathPtr in
                    pathBytes.prefix(pathLength).withUnsafeBufferPointer { buffer in
                        pathPtr.initialize(from: buffer.baseAddress!, count: pathLength)
                    }
                }

                let connectResult = withUnsafePointer(to: addr) { addrPtr in
                    connect(
                        testSocket,
                        UnsafeRawPointer(addrPtr).bindMemory(to: sockaddr.self, capacity: 1),
                        socklen_t(MemoryLayout<sockaddr_un>.size))
                }

                close(testSocket)

                if connectResult == 0 {
                    print("❌ Another instance is already running and active")
                    return false
                } else {
                    print("✅ Socket file is stale (from dirty quit) - removing...")
                }
            }

            // Remove the stale socket file
            do {
                try fileManager.removeItem(atPath: Self.socketPath)
                print("✅ Successfully removed stale socket file")
            } catch {
                print("❌ Failed to remove existing socket file: \(error)")
                return false
            }
        } else {
            print("✅ No existing socket file found")
        }

        print("🏗️  Creating CFSocket...")
        // Create socket
        var context = CFSocketContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let callback: CFSocketCallBack = { socket, callbackType, address, data, info in
            print("📞 Socket callback triggered - accepting connection")
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
            print("❌ Failed to create CFSocket")
            return false
        }
        print("✅ CFSocket created successfully")

        print("🔗 Setting up socket address...")
        // Bind to socket path
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = Self.socketPath.utf8CString
        let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
        let pathLength = min(pathBytes.count - 1, maxPathLength - 1)
        print("📏 Socket path length: \(pathLength) bytes")

        withUnsafeMutablePointer(to: &addr.sun_path.0) { pathPtr in
            pathBytes.prefix(pathLength).withUnsafeBufferPointer { buffer in
                pathPtr.initialize(from: buffer.baseAddress!, count: pathLength)
            }
        }

        // Set sun_len field correctly for BSD systems
        addr.sun_len = UInt8(MemoryLayout<UInt8>.size + MemoryLayout<sa_family_t>.size + pathLength)
        print("📐 Set sun_len to: \(addr.sun_len)")

        let data = withUnsafePointer(to: addr) { pointer in
            Data(bytes: pointer, count: Int(addr.sun_len))
        }

        let address = data.withUnsafeBytes { bytes in
            CFDataCreate(
                kCFAllocatorDefault, bytes.bindMemory(to: UInt8.self).baseAddress, data.count)
        }

        print("🎯 Binding socket to address...")
        let result = CFSocketSetAddress(server, address)
        if result != .success {
            print("❌ Failed to bind socket to address. Result: \(result)")
            return false
        }
        print("✅ Socket bound to address successfully")

        // Start listening for connections
        print("👂 Starting to listen for connections...")
        let nativeSocket = CFSocketGetNative(server)

        // Set socket to non-blocking mode
        let flags = fcntl(nativeSocket, F_GETFL, 0)
        let setResult = fcntl(nativeSocket, F_SETFL, flags | O_NONBLOCK)
        print("⚡ Set server socket to non-blocking mode: \(setResult == 0 ? "✅" : "❌")")

        let listenResult = listen(nativeSocket, 5)  // Allow up to 5 pending connections
        if listenResult != 0 {
            print("❌ Failed to listen on socket: \(String(cString: strerror(errno)))")
            return false
        }
        print("✅ Socket is now listening for connections")

        print("⚡ Adding socket to run loop...")
        // Add to run loop
        let source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, server, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        print("✅ Socket added to run loop successfully")

        print("🎉 Socket binding process completed successfully")
        return true
    }

    private func handleConnection(socket: CFSocket, address: CFData?, data: UnsafeRawPointer?) {
        print("🔗 === New Connection Handler Started ===")

        // With acceptCallBack, the 'data' parameter is a pointer to the native socket handle
        // for the new connection.
        guard let clientSocketPtr = data?.assumingMemoryBound(to: Int32.self) else {
            print("❌ Invalid data pointer in connection handler")
            return
        }
        let clientSocket = clientSocketPtr.pointee
        print("📡 Got accepted client socket: \(clientSocket)")

        // Process each connection on a background queue to handle multiple connections concurrently
        DispatchQueue.global(qos: .userInitiated).async {
            self.processClientConnection(clientSocket)
        }

        print("🏁 === Connection Handler Completed (dispatched to background) ===")
    }

    private func processClientConnection(_ client: Int32) {
        print("🔄 === Processing Client Connection on Background Queue ===")

        defer {
            print("🔒 Closing client connection...")
            close(client)
            print("✅ Client connection closed")
        }

        print("⏰ Setting socket timeouts...")
        // Set socket timeout (5 seconds)
        var timeout = timeval()
        timeout.tv_sec = 5
        timeout.tv_usec = 0
        let rcvResult = setsockopt(
            client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let sndResult = setsockopt(
            client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        print("📥 Receive timeout set: \(rcvResult == 0 ? "✅" : "❌")")
        print("📤 Send timeout set: \(sndResult == 0 ? "✅" : "❌")")

        // Read the command with timeout
        print("📖 Reading command from client...")
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(client, &buffer, buffer.count)
        print("📊 Bytes read: \(bytesRead)")

        if bytesRead > 0 {
            let command = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
            print("📝 Command received: '\(command)'")
            print("🔄 Processing command...")
            let response = handleCommand(command)
            print("📋 Command processed. Response: '\(response.prefix(100))...' (truncated)")

            print("📤 Sending response to client...")
            let responseData = response.data(using: .utf8) ?? Data()
            print("📏 Response data size: \(responseData.count) bytes")
            let bytesWritten = responseData.withUnsafeBytes { bytes in
                write(client, bytes.bindMemory(to: UInt8.self).baseAddress, responseData.count)
            }
            print("📊 Bytes written: \(bytesWritten)")
            if bytesWritten == responseData.count {
                print("✅ Response sent successfully")
            } else {
                print("⚠️  Partial response sent or error occurred")
            }
        } else if bytesRead == 0 {
            print("📪 Client closed connection gracefully")
        } else {
            print("❌ Failed to read from socket: \(String(cString: strerror(errno)))")
        }

        print("🏁 === Client Connection Processing Completed ===")
    }

    private func handleCommand(_ command: String) -> String {
        print("🎯 === Command Handler Started ===")
        print("📥 Raw command: '\(command)'")

        let parts = command.components(separatedBy: ":")
        let cmd = parts[0]
        let data = parts.count > 1 ? parts[1...].joined(separator: ":") : ""

        print("🔍 Parsed command: '\(cmd)'")
        print("📦 Command data: '\(data.isEmpty ? "(empty)" : data)'")

        let response: String
        switch cmd {
        case "getStatus":
            print("🏥 Handling getStatus command")
            response = handleGetStatus()
        case "requestPermission":
            print("🔐 Handling requestPermission command")
            response = handleRequestPermission()
        case "getWindows":
            print("🪟 Handling getWindows command")
            response = handleGetWindows(data)
        case "activateWindow":
            print("🎯 Handling activateWindow command")
            response = handleActivateWindow(data)
        case "shutdown":
            print("🛑 Handling shutdown command")
            response = handleShutdown()
        default:
            print("❓ Unknown command: '\(cmd)'")
            response = "ERROR:Unknown command"
        }

        print("✅ Command handler completed")
        print("📤 Response: '\(response.prefix(50))...' (truncated)")
        print("🏁 === Command Handler Finished ===")
        return response
    }

    private func handleGetStatus() -> String {
        print("🏥 === GetStatus Handler Started ===")
        print("🔍 Checking accessibility permission...")
        let hasPermission = AXIsProcessTrustedWithOptions(nil)
        print("🔐 Accessibility permission: \(hasPermission ? "✅ GRANTED" : "❌ DENIED")")

        let response = StatusResponse(hasAccessibilityPermission: hasPermission)
        print("📋 Created StatusResponse object")

        do {
            print("🔄 Encoding response to JSON...")
            let jsonData = try JSONEncoder().encode(response)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            print("✅ JSON encoded successfully: \(jsonString)")
            return "OK:" + jsonString
        } catch {
            print("❌ Failed to encode status response: \(error)")
            return "ERROR:Failed to encode status response"
        }
    }

    private func handleRequestPermission() -> String {
        print("🔐 === RequestPermission Handler Started ===")

        // Check if we're running as a bundled app
        let bundle = Bundle.main
        print("📦 Bundle identifier: \(bundle.bundleIdentifier ?? "nil")")

        if bundle.bundleIdentifier != nil {
            print("🎯 Running as bundled app - triggering permission prompt")
            // Trigger permission prompt
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            print("✅ Permission prompt triggered")
        } else {
            print("⚠️  Not running as bundled app - cannot trigger permission prompt")
        }

        print("🏁 === RequestPermission Handler Completed ===")
        return "OK:"
    }

    private func handleGetWindows(_ data: String) -> String {
        print("🪟 === GetWindows Handler Started ===")
        print("📥 Request data: '\(data)'")

        do {
            print("🔄 Decoding request JSON...")
            let request = try JSONDecoder().decode(
                GetWindowsRequest.self, from: data.data(using: .utf8)!)
            print(
                "✅ Request decoded - newWindowPosition: '\(request.newWindowPosition)', activationMode: '\(request.activationMode)'"
            )

            // Get current VS Code windows
            print("🔍 Getting VS Code windows...")
            let currentWindows = getVSCodeWindows()
            print("📊 Found \(currentWindows.count) VS Code windows")
            for (index, window) in currentWindows.enumerated() {
                print(
                    "  Window \(index + 1): ID=\(window.id), Title='\(window.title)', Active=\(window.isCurrentlyActive)"
                )
            }

            // Handle activation mode
            print("🎮 Processing activation mode: '\(request.activationMode)'")
            if request.activationMode == "automatic" {
                print("🔄 Updating window order with frontmost window...")
                updateWindowOrderWithFrontmost(currentWindows)
                print("📋 Current window order: \(windowOrder)")
            } else {
                print("📝 Manual mode - preserving current order")
            }

            // Update window order with new/closed windows
            print("🔄 Updating window order with new/closed windows...")
            updateWindowOrder(currentWindows, newWindowPosition: request.newWindowPosition)
            print("📋 Final window order: \(windowOrder)")

            // Build response
            print("🏗️  Building response...")
            let windowInfos = windowOrder.compactMap { windowId in
                currentWindows.first { $0.id == windowId }
            }.map { window in
                WindowInfo(
                    id: window.id,
                    title: window.title,
                    isCurrentlyActive: window.isCurrentlyActive
                )
            }
            print("📊 Response will contain \(windowInfos.count) windows")

            print("🔄 Encoding response to JSON...")
            let jsonData = try JSONEncoder().encode(windowInfos)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            print("✅ Response encoded successfully")
            print("🏁 === GetWindows Handler Completed ===")
            return "OK:" + jsonString
        } catch {
            print("❌ Error in GetWindows handler: \(error)")
            print("🏁 === GetWindows Handler Failed ===")
            return "ERROR:Failed to get windows: \(error)"
        }
    }

    private func handleActivateWindow(_ data: String) -> String {
        print("🎯 === ActivateWindow Handler Started ===")
        print("📥 Request data: '\(data)'")

        do {
            print("🔄 Decoding request JSON...")
            let request = try JSONDecoder().decode(
                ActivateWindowRequest.self, from: data.data(using: .utf8)!)
            print("✅ Request decoded - Window ID: \(request.id)")

            print("🔄 Attempting to activate window with ID: \(request.id)")
            if activateWindowWithId(request.id) {
                print("✅ Window activated successfully")
                print("🔄 Moving activated window to top of order...")
                // Move activated window to top of order
                windowOrder.removeAll { $0 == request.id }
                windowOrder.insert(request.id, at: 0)
                print("📋 Updated window order: \(windowOrder)")
                print("🏁 === ActivateWindow Handler Completed Successfully ===")
                return "OK:"
            } else {
                print("❌ Failed to activate window")
                print("🏁 === ActivateWindow Handler Failed ===")
                return "ERROR:Failed to activate window"
            }
        } catch {
            print("❌ Error in ActivateWindow handler: \(error)")
            print("🏁 === ActivateWindow Handler Failed ===")
            return "ERROR:Failed to parse activate window request"
        }
    }

    private func handleShutdown() -> String {
        print("🛑 === Shutdown Handler Started ===")
        print("🧹 Cleaning up resources...")

        // Close the server socket
        if let server = server {
            print("🔌 Closing server socket...")
            CFSocketInvalidate(server)
            self.server = nil
            print("✅ Server socket closed")
        }

        // Remove socket file
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: Self.socketPath) {
            print("🗑️  Removing socket file...")
            do {
                try fileManager.removeItem(atPath: Self.socketPath)
                print("✅ Socket file removed successfully")
            } catch {
                print("⚠️  Failed to remove socket file: \(error)")
            }
        }

        print("✅ Cleanup completed")
        print("🏁 === Shutdown Handler Completed ===")

        DispatchQueue.main.async {
            print("👋 Exiting application...")
            exit(0)
        }
        return "OK:"
    }

    // MARK: - Window Management

    private func getVSCodeWindows() -> [(id: CGWindowID, title: String, isCurrentlyActive: Bool)] {
        print("🔍 === GetVSCodeWindows Started ===")

        // Use a more targeted window list query for better performance
        print("📋 Requesting window list from Core Graphics...")
        guard
            let windowList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            print("❌ Failed to get window list from Core Graphics")
            return []
        }
        print("✅ Got window list with \(windowList.count) total windows")

        var windows: [(id: CGWindowID, title: String, isCurrentlyActive: Bool)] = []
        var frontmostWindow: CGWindowID?

        // Get the frontmost VS Code window more efficiently
        print("🔍 Looking for frontmost VS Code application...")
        if let frontmostApp = NSWorkspace.shared.frontmostApplication,
            frontmostApp.bundleIdentifier?.contains("com.microsoft.VSCode") == true
        {
            let frontmostPID = frontmostApp.processIdentifier
            print("✅ Found frontmost VS Code app with PID: \(frontmostPID)")
            print("📱 Bundle ID: \(frontmostApp.bundleIdentifier ?? "unknown")")

            // Find the frontmost window for this PID
            print("🔍 Searching for frontmost window...")
            for (index, windowInfo) in windowList.enumerated() {
                if let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                    pid == frontmostPID,
                    let windowId = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                    let windowTitle = windowInfo[kCGWindowName as String] as? String,
                    !windowTitle.isEmpty,
                    windowTitle.contains("— ")
                {
                    frontmostWindow = windowId
                    print(
                        "✅ Found frontmost window at index \(index): ID=\(windowId), Title='\(windowTitle)'"
                    )
                    break
                }
            }

            if frontmostWindow == nil {
                print("⚠️  No frontmost document windows found for VS Code")
            }
        } else {
            print("⚠️  VS Code is not the frontmost application")
        }

        // Process windows more efficiently
        print("🔄 Processing all windows to find VS Code instances...")
        var processedCount = 0
        var vsCodeCount = 0

        for (index, windowInfo) in windowList.enumerated() {
            processedCount += 1

            guard let ownerName = windowInfo[kCGWindowOwnerName as String] as? String else {
                continue
            }

            print("🔍 Processing window \(index + 1)/\(windowList.count): Owner='\(ownerName)'")

            if ownerName == "Code" || ownerName == "Visual Studio Code" {
                vsCodeCount += 1

                guard let windowId = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                    let windowTitle = windowInfo[kCGWindowName as String] as? String,
                    !windowTitle.isEmpty,
                    windowTitle.contains("— ")  // Only document windows
                else {
                    print("🔄 Skipping VS Code window at index \(index) - not a document window")
                    continue
                }

                let isActive = windowId == frontmostWindow
                windows.append((id: windowId, title: windowTitle, isCurrentlyActive: isActive))
                print(
                    "✅ Added VS Code window: ID=\(windowId), Title='\(windowTitle)', Active=\(isActive)"
                )
            }
        }

        print("📊 Window processing complete:")
        print("  - Total windows processed: \(processedCount)")
        print("  - VS Code windows found: \(vsCodeCount)")
        print("  - Document windows returned: \(windows.count)")
        print("🏁 === GetVSCodeWindows Completed ===")

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
        print("🎯 === ActivateWindowWithId Started ===")
        print("📥 Target window ID: \(windowId)")

        // Get the window info
        print("📋 Requesting full window list for window lookup...")
        guard
            let windowList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
                as? [[String: Any]]
        else {
            print("❌ Failed to get window list")
            return false
        }
        print("✅ Got window list with \(windowList.count) windows")

        var targetPID: pid_t?

        print("🔍 Searching for target window...")
        for (index, windowInfo) in windowList.enumerated() {
            if let id = windowInfo[kCGWindowNumber as String] as? CGWindowID,
                id == windowId,
                let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t
            {
                targetPID = pid
                print("✅ Found target window at index \(index) with PID: \(pid)")
                break
            }
        }

        guard let pid = targetPID else {
            print("❌ Could not find window with ID \(windowId)")
            return false
        }

        // Get the application
        print("🖥️  Getting NSRunningApplication for PID: \(pid)")
        let app = NSRunningApplication(processIdentifier: pid)
        print("📱 App found: \(app?.localizedName ?? "unknown")")

        // Activate the application first
        print("⚡ Activating application...")
        if #available(macOS 14.0, *) {
            let activated = app?.activate()
            print("📱 App activation result: \(activated == true ? "✅" : "❌")")
        } else {
            let activated = app?.activate(options: [.activateIgnoringOtherApps])
            print("📱 App activation result: \(activated == true ? "✅" : "❌")")
        }

        // Use Accessibility API to focus the specific window
        print("🔧 Creating AX application reference...")
        let appRef = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        print("📋 Getting windows list from Accessibility API...")
        let result = AXUIElementCopyAttributeValue(
            appRef, kAXWindowsAttribute as CFString, &windowsRef)

        if result == .success,
            let windows = windowsRef as? [AXUIElement]
        {
            print("✅ Got \(windows.count) windows from Accessibility API")

            print("🔍 Searching for target window in AX windows...")
            for (index, window) in windows.enumerated() {
                var windowIdRef: CFTypeRef?
                print("🔍 Checking window \(index + 1)/\(windows.count)...")

                if AXUIElementCopyAttributeValue(
                    window, kAXIdentifierAttribute as CFString, &windowIdRef) == .success,
                    let windowIdNum = windowIdRef as? NSNumber,
                    windowIdNum.uint32Value == windowId
                {
                    print("✅ Found matching window! Activating...")
                    // Raise and focus the window
                    let frontmostResult = AXUIElementSetAttributeValue(
                        window, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                    print("🎯 Set frontmost result: \(frontmostResult == .success ? "✅" : "❌")")

                    let raiseResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                    print("⬆️  Raise action result: \(raiseResult == .success ? "✅" : "❌")")

                    print("🏁 === ActivateWindowWithId Completed Successfully ===")
                    return true
                }
            }

            // Fallback: just raise the first window
            print("⚠️  Target window not found, using fallback...")
            if let firstWindow = windows.first {
                print("🔄 Activating first available window as fallback...")
                let frontmostResult = AXUIElementSetAttributeValue(
                    firstWindow, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                print("🎯 Fallback frontmost result: \(frontmostResult == .success ? "✅" : "❌")")

                let raiseResult = AXUIElementPerformAction(firstWindow, kAXRaiseAction as CFString)
                print("⬆️  Fallback raise result: \(raiseResult == .success ? "✅" : "❌")")

                print("🏁 === ActivateWindowWithId Completed with Fallback ===")
                return true
            } else {
                print("❌ No windows available for fallback")
            }
        } else {
            print("❌ Failed to get windows from Accessibility API. Result: \(result)")
        }

        print("🏁 === ActivateWindowWithId Failed ===")
        return false
    }
}

// MARK: - Main Entry Point

let helper = BacktickPlusPlusHelper()
helper.start()
