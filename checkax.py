# test_accessibility.py
import subprocess
import sys

# Try to use accessibility API (requires PyObjC)
try:
    from ApplicationServices import AXIsProcessTrusted

    print(f"Python path: {sys.executable}")
    print(f"Process trusted: {AXIsProcessTrusted()}")
except ImportError:
    print("PyObjC not available - install with: pip install pyobjc")
