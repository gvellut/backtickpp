import AppKit
from Quartz import (
    CGWindowListCopyWindowInfo,
    kCGNullWindowID,
    kCGWindowListOptionOnScreenOnly,
)


def main():
    print(
        "--- Listing windows belonging to the frontmost application (using Core Graphics API) ---"
    )
    ws = AppKit.NSWorkspace.sharedWorkspace()
    front_app = ws.frontmostApplication()
    pid = int(front_app.processIdentifier())
    bundle_id = front_app.bundleIdentifier()
    print(f"Frontmost app: {bundle_id} (PID: {pid})\n")

    # Get all on-screen windows
    window_list = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly, kCGNullWindowID
    )
    own_windows = [w for w in window_list if w.get("kCGWindowOwnerPID") == pid]

    if not own_windows:
        print("No windows found for this process.")
        return

    print(f"Found {len(own_windows)} window(s) for this process:")
    for i, win in enumerate(own_windows):
        title = win.get("kCGWindowName", "<No title>")
        wid = win.get("kCGWindowNumber", "<No ID>")
        print(f"\nWindow {i + 1}:")
        print(f"  Window ID: {wid}")
        print(f"  Title: '{title}'")
        print(f"  Bounds: {win.get('kCGWindowBounds')}")


if __name__ == "__main__":
    main()
