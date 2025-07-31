
### **Final Revised Specification for "backtick-plus-plus" (v4)**

This document specifies the core components and functionality for the `backtick-plus-plus` VS Code extension and its helper process.

#### **1. Swift Background Process (`backtick-plus-plus-helper.app`)**

A faceless macOS agent application responsible for all window state management and OS interaction.

*   **Project Setup:**
    *   **Packaging:** Distributed as a bundled application (`.app`) with the `LSUIElement` key set to `true`. A raw binary can be used for development.

*   **Architecture & Lifetime:**
    *   **IPC:** Listens for commands on a Unix domain socket.
    *   **Singleton:** On launch, the helper attempts to bind to the socket file path. If this fails, another instance is already running, and the new instance will immediately terminate.

*   **Commands (API via Socket):**
    *   **`getStatus()`:** Checks and returns its Accessibility permission status.
    *   **`requestPermission()`:** If running as a bundled app, triggers the system permission prompt for itself. Does nothing if it's a raw binary.
    *   **`getWindows(newWindowPosition: 'TOP' | 'BOTTOM', activationMode: 'automatic' | 'manual')`:** **(Updated)**
        1.  Receives the current settings from the VS Code extension.
        2.  Fetches the current list of all VS Code windows.
        3.  If `activationMode` is `'automatic'`, it first moves the true frontmost window to the top of its internal list.
        4.  It then compares the fetched list with its internal state to identify new/closed windows, placing new ones **according to the `newWindowPosition` argument.**
        5.  Returns the final ordered list as a JSON array: `[{ "id": CGWindowID, "title": String, "isCurrentlyActive": Bool }]`.
    *   **`activateWindow(id: CGWindowID)`:**
        1.  Receives a window ID from the extension.
        2.  Uses the Accessibility API to bring the window to the foreground.
        3.  If successful, moves that same window ID to the top of its internal ordered list.
    *   **`shutdown()`:** Receives this command and cleanly terminates its own process.

#### **2. VS Code Extension (`backtick-plus-plus`)**

The user-facing component providing UI, shortcuts, and process orchestration.

*   **Activation & Deactivation (Lifecycle Management):**
    *   **Activation:** On activation, checks for and shuts down any orphan helper processes before launching a fresh instance.
    *   **Deactivation:** Implements the `deactivate()` function to send the `shutdown` command to the helper, ensuring a clean exit when VS Code closes.

*   **Permission Handling Flow:**
    *   On first use, calls `getStatus()`. If permission is not granted, it displays a modal information message with buttons to trigger the helper's `requestPermission()` command and reload the window.

*   **Shortcuts and Commands:**
    *   `...switchForward`/`...switchBackward`: Shows the main switcher UI.
    *   `...instantSwitch`: Immediately activates the second window in the list without UI.

*   **UI & Interaction Flow (Main Switcher):**
    1.  On shortcut press, the extension first reads the `backtick-plus-plus.newWindowPosition` and `backtick-plus-plus.activationMode` settings from the VS Code configuration.
    2.  It then calls the helper's `getWindows()` command, **passing these settings as arguments.**
    3.  It finds the index of the `isCurrentlyActive` window and displays a Quick Pick menu, with the initial highlighted item based on the active window's index and the shortcut direction.
    4.  Subsequent shortcut presses update the highlighted item.
    5.  User confirms selection with `Enter`.
    6.  On confirmation, it makes a single call to the helper's `activateWindow(id:)` command.

*   **UI & Interaction Flow (Instant Switch):**
    1.  On shortcut press, the extension first reads the required settings.
    2.  It calls `getWindows()`, passing the settings as arguments.
    3.  It identifies the second item in the returned list (`list[1]`).
    4.  It makes a single call to the helper's `activateWindow(id:)` command with that window's ID.

*   **Configuration (`package.json` contributions):**
    *   `backtick-plus-plus.activationMode`: `["automatic", "manual"]`.
    *   `backtick-plus-plus.newWindowPosition`: `["top", "bottom"]`.
    *   Definitions for all commands and their default keyboard shortcuts.