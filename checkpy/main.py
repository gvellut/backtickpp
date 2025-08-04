#!/usr/bin/env python3

import sys

from AppKit import NSRunningApplication
from ApplicationServices import (
    AXUIElementCopyAttributeValue,
    AXUIElementCreateApplication,
    kAXTitleAttribute,
    kAXWindowsAttribute,
)
from HIServices import kAXErrorAPIDisabled


def main():
    """
    Final correct script for listing VS Code window titles using Accessibility.
    This version uses the correct 3-argument signature for AXUIElementCopyAttributeValue.
    """
    print("--- Looking for Visual Studio Code application ---")

    vscode_bundle_id = "com.microsoft.VSCode"
    running_apps = NSRunningApplication.runningApplicationsWithBundleIdentifier_(
        vscode_bundle_id
    )

    if not running_apps:
        print("Error: Visual Studio Code is not running.")
        sys.exit(1)

    vscode_app = running_apps[0]
    pid = vscode_app.processIdentifier()
    print(f"Found VS Code running with PID: {pid}\n")

    app_element = AXUIElementCreateApplication(pid)

    # --- THE CORRECT 3-ARGUMENT CALL ---
    # The 3rd argument is a placeholder for the C output pointer.
    error, window_elements = AXUIElementCopyAttributeValue(
        app_element, kAXWindowsAttribute, None
    )

    if error == kAXErrorAPIDisabled:
        print("\n[X] ACTION REQUIRED: Accessibility permission is NOT granted.")
        print("This script needs permission to control other applications.")
        print("\n--> Please do the following: <--")
        print("1. Open System Settings > Privacy & Security > Accessibility.")
        print(
            "2. Find and enable the application running this script (e.g., 'Terminal')."
        )
        print(
            "3. You MUST quit and relaunch the Terminal/editor for the change to take effect."
        )
        print("\nAfter granting permission, run this script again.\n")
        sys.exit(1)

    elif error != 0 or not window_elements:
        print("Could not retrieve window list from VS Code.")
        print("This could be because no windows are open or another error occurred.")
        sys.exit(1)

    print("Accessibility permission is granted. Proceeding...")
    print(f"--- Found {len(window_elements)} VS Code Window(s) via Accessibility ---")

    for i, window_element in enumerate(window_elements):
        # --- APPLYING THE SAME 3-ARGUMENT FIX HERE ---
        err, window_title = AXUIElementCopyAttributeValue(
            window_element, kAXTitleAttribute, None
        )

        print(f"\nWindow {i + 1}:")
        if err == 0 and window_title:
            print(f"  Title: '{window_title}'")
        else:
            print("  Title: <No title available for this window element>")


if __name__ == "__main__":
    main()
