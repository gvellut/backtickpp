#!/usr/bin/env python3
"""
Simple test script for the backtick++ helper process
"""

import json
import socket
import time

SOCKET_PATH = "/tmp/backtick-plus-plus-helper.sock"


def send_command(command, data=""):
    """Send a command to the helper process and return the response"""
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
            raise Exception(response[6:])
        else:
            return response

    except Exception as e:
        print(f"Error communicating with helper: {e}")
        return None


def test_helper():
    """Test the helper process functionality"""
    print("Testing Backtick++ Helper Process")
    print("=" * 40)

    # Test 1: Get Status
    print("1. Testing getStatus command...")
    response = send_command("getStatus")
    if response:
        try:
            status = json.loads(response)
            print(f"   Status: {status}")
        except json.JSONDecodeError:
            print(f"   Response: {response}")
    else:
        print("   Failed to get status")

    # Test 2: Get Windows
    print("\n2. Testing getWindows command...")
    request = {"newWindowPosition": "top", "activationMode": "automatic"}
    response = send_command("getWindows", json.dumps(request))
    if response:
        try:
            windows = json.loads(response)
            print(f"   Found {len(windows)} windows:")
            for window in windows:
                print(
                    f"      - ID: {window['id']}, Title: {window['title']}, Active: {window['isCurrentlyActive']}"
                )
        except json.JSONDecodeError:
            print(f"   Response: {response}")
    else:
        print("   Failed to get windows")

    # Test 3: Shutdown (comment out to keep helper running)
    # print("\n3. Testing shutdown command...")
    # response = send_command("shutdown")
    # print(f"   Shutdown response: {response}")


if __name__ == "__main__":
    test_helper()
