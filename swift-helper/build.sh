#!/bin/bash

# Build script for the Swift helper
cd "$(dirname "$0")" || exit 1

echo "Building Swift helper..."

# Try Swift Package Manager first, fall back to manual compilation
if swift build -c release 2>/dev/null; then
    echo "✅ Swift helper built successfully with Swift Package Manager"
    echo "Binary location: .build/release/backtick-plus-plus-helper"
elif make release; then
    echo "✅ Swift helper built successfully with Makefile"
    echo "Binary location: build/backtick-plus-plus-helper"
else
    echo "❌ Failed to build Swift helper"
    exit 1
fi
