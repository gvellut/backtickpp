# Backtick++ Swift Helper

This is the Swift helper process for Backtick++. It's a background macOS application that manages VS Code windows using Accessibility APIs.

## Building

### Quick Build
```bash
./build.sh
```

### App Bundle
```bash
./package.sh
```

### Manual Build
```bash
swift build -c release
swift build -c debug
```

## Running

The helper process runs as a background daemon and communicates via Unix domain socket at `/tmp/backtick-plus-plus-helper.sock`.

### Direct Execution
```bash
.build/release/backtick-plus-plus-helper
```

### As App Bundle
```bash
open backtick-plus-plus-helper.app
```

## Requirements

- macOS 12.0+
- Xcode Command Line Tools
- Accessibility permissions (will be requested on first use)
