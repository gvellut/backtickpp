import sys

from AppKit import NSRunningApplication
from Quartz import (
    CGWindowListCopyWindowInfo,
    kCGNullWindowID,
    kCGWindowListOptionOnScreenOnly,
)


def get_vscode_pid():
    """Find the process ID (PID) for Visual Studio Code."""
    # The bundle identifier for VS Code is consistent.
    vscode_bundle_id = "com.microsoft.VSCode"

    # Get a list of all running applications
    running_apps = NSRunningApplication.runningApplicationsWithBundleIdentifier_(
        vscode_bundle_id
    )

    if not running_apps:
        return None

    # Return the processIdentifier of the first instance found
    return running_apps[0].processIdentifier()


def main():
    """
    Main function to find and print VS Code window information.
    """
    print("--- Looking for Visual Studio Code windows ---")

    vscode_pid = get_vscode_pid()

    if not vscode_pid:
        print("\nError: Visual Studio Code is not running.")
        print("Please open some VS Code windows and run this script again.")
        sys.exit(1)

    print(f"Found VS Code running with PID: {vscode_pid}\n")

    # Get a list of all on-screen windows.
    # The result is a list of dictionaries, one for each window.
    window_list = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly, kCGNullWindowID
    )

    vscode_windows_found = 0
    for window in window_list:
        # Check if the window belongs to the VS Code process
        if window.get("kCGWindowOwnerPID") == vscode_pid:
            # Not all windows have names (e.g., helper or background windows)
            window_name = window.get("kCGWindowName")
            if window_name:
                vscode_windows_found += 1

                # Encode the string to see its raw bytes
                raw_unicode_bytes = window_name.encode("utf-8")

                print(f"Window ID:  {window.get('kCGWindowNumber')}")
                print(f"Window Name (Text):  '{window_name}'")
                print(f"Window Name (Raw UTF-8 Bytes): {raw_unicode_bytes}\n")

    if vscode_windows_found == 0:
        print("VS Code is running, but no named windows were found.")
        print("This can happen if only the initial welcome screen is open.")


if __name__ == "__main__":
    main()
