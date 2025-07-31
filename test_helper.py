#!/usr/bin/env python3
"""
Simple test script for the backtick++ helper process
"""

import json
import socket
import time

SOCKET_PATH = "/tmp/backtick-plus-plus-helper.sock"


def _send_command(command, data=""):
    """Send a raw command to the helper process and return the raw response"""
    try:
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.connect(SOCKET_PATH)

        message = command if not data else f"{command}:{data}"
        client.send(message.encode("utf-8"))

        response = client.recv(4096).decode("utf-8")
        client.close()

        if response.startswith("OK:"):
            return response[3:]
        elif response.startswith("ERROR:"):
            raise Exception(f"Helper returned error: {response[6:]}")
        else:
            # Should not happen with the current helper implementation
            raise Exception(f"Received unexpected response: {response}")

    except Exception as e:
        print(f"Error communicating with helper: {e}")
        return None


def get_status():
    """Get the status from the helper."""
    print("1. Testing getStatus command...")
    try:
        response = _send_command("getStatus")
        if response:
            return json.loads(response)
    except Exception as e:
        print(f"   Failed to get status: {e}")
    return None


def get_windows(new_window_position="top", activation_mode="automatic"):
    """Get the list of windows from the helper."""
    print("\n2. Testing getWindows command...")
    try:
        request = {
            "newWindowPosition": new_window_position,
            "activationMode": activation_mode,
        }
        response = _send_command("getWindows", json.dumps(request))
        if response:
            return json.loads(response)
    except Exception as e:
        print(f"   Failed to get windows: {e}")
    return None


def activate_window(window_id):
    """Request the helper to activate a specific window."""
    print("\n3. Testing activateWindow command...")
    try:
        request = {"id": window_id}
        print(f"   Activating window with ID: {window_id}")
        response = _send_command("activateWindow", json.dumps(request))
        return response
    except Exception as e:
        print(f"   Failed to activate window: {e}")
    return None


def shutdown_helper():
    """Request the helper to shut down."""
    print("\n4. Testing shutdown command...")
    try:
        response = _send_command("shutdown")
        return response
    except Exception as e:
        print(f"   Failed to send shutdown command: {e}")
    return None


def test_helper():
    """Test the helper process functionality"""
    print("Testing Backtick++ Helper Process")
    print("=" * 40)

    # Test 1: Get Status
    status = get_status()
    if status:
        print(f"   Status: {status}")
    else:
        print("   getStatus test failed.")

    # Test 2: Get Windows
    windows = get_windows()
    if windows:
        print(f"   Found {len(windows)} windows:")
        for window in windows:
            print(
                f"      - ID: {window['id']}, "
                f"Title: {window['title']}, "
                f"Active: {window['isCurrentlyActive']}"
            )
    else:
        print("   getWindows test failed.")
        # If we can't get windows, we can't continue to other tests
        return

    # Test 3: Activate Window
    if len(windows) > 1:
        # Activate the second window in the list to test activation
        window_to_activate = windows[3]
        response = activate_window(window_to_activate["id"])
        print(f"   Activation response: {response}")
    else:
        print("\nSkipping activateWindow test: less than 2 windows available.")

    windows = get_windows()
    if windows:
        print(f"   Found {len(windows)} windows:")
        for window in windows:
            print(
                f"      - ID: {window['id']}, "
                f"Title: {window['title']}, "
                f"Active: {window['isCurrentlyActive']}"
            )
    else:
        print("   getWindows test failed.")
        # If we can't get windows, we can't continue to other tests
        return

    if len(windows) > 1:
        # Activate the second window in the list to test activation
        window_to_activate = windows[1]
        response = activate_window(window_to_activate["id"])
        print(f"   Activation response: {response}")
    else:
        print("\nSkipping activateWindow test: less than 2 windows available.")

    # Test 4: Shutdown (comment out to keep helper running)
    # response = shutdown_helper()
    # print(f"   Shutdown response: {response}")


if __name__ == "__main__":
    test_helper()
