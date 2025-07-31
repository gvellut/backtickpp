# Backtick++ 

Advanced window switching for VS Code on macOS. This extension provides fast and intuitive window navigation using keyboard shortcuts.

## Architecture

This project consists of two main components:

1. **Swift Helper Process** (`swift-helper/`): A background macOS application that handles window management using Accessibility APIs
2. **VS Code Extension** (`vscode-extension/`): The user-facing extension that provides UI and commands

## Prerequisites

- macOS 12.0 or later
- Xcode Command Line Tools (for Swift compilation)
- Node.js 18+ (for VS Code extension development)
- VS Code 1.80.0 or later

## Building

### Swift Helper Process

The Swift helper is a background process that manages VS Code windows using macOS Accessibility APIs.

#### Compile for Development
```bash
cd swift-helper
./build.sh
```

#### Compile for Release (App Bundle)
```bash
cd swift-helper
./package.sh
```

This creates a `backtick-plus-plus-helper.app` bundle that can be distributed.

#### Manual Build Commands
```bash
cd swift-helper
swift build -c release          # Release build
swift build -c debug            # Debug build
```

### VS Code Extension

#### Install Dependencies
```bash
cd vscode-extension
npm install
```

#### Compile TypeScript
```bash
cd vscode-extension
npm run compile                  # One-time compilation
npm run watch                    # Watch mode for development
```

#### Package Extension (VSIX)
```bash
cd vscode-extension
npx vsce package
```

This creates a `.vsix` file that can be installed in VS Code.

## Development & Debugging

### Swift Helper

#### Debug Build
```bash
cd swift-helper
swift build -c debug
.build/debug/backtick-plus-plus-helper
```

#### Logging
The helper uses `os.log` for logging. View logs with:
```bash
log stream --predicate 'subsystem == "com.backtickpp.helper"'
```

#### Testing Socket Communication
```bash
# Test if helper is running
nc -U /tmp/backtick-plus-plus-helper.sock

# Send test commands
echo "getStatus" | nc -U /tmp/backtick-plus-plus-helper.sock
```

### VS Code Extension

#### Development Mode
1. Open the `vscode-extension` folder in VS Code
2. Press `F5` to launch Extension Development Host
3. The extension will be loaded in the new VS Code window

#### Debug Console
- Use `console.log()` in your TypeScript code
- View output in the Debug Console of the main VS Code window

#### Live Reload
```bash
cd vscode-extension
npm run watch
```

After making changes, reload the Extension Development Host window (`Cmd+R`).

## Installation

### Development Installation

1. Build the Swift helper:
   ```bash
   cd swift-helper
   ./build.sh
   ```

2. Build the VS Code extension:
   ```bash
   cd vscode-extension
   npm install
   npm run compile
   ```

3. Install the extension in VS Code:
   - Open VS Code
   - Press `Cmd+Shift+P`
   - Type "Extensions: Install from VSIX"
   - Select the generated `.vsix` file from `vscode-extension/`

### Production Installation

1. Package the Swift helper as an app bundle:
   ```bash
   cd swift-helper
   ./package.sh
   ```

2. Build and package the VS Code extension:
   ```bash
   cd vscode-extension
   npm install
   npm run vscode:prepublish
   npx vsce package
   ```

3. Distribute the `.vsix` file and the `.app` bundle

## Usage

### Keyboard Shortcuts

- `Cmd+\`` - Switch forward through windows
- `Cmd+Shift+\`` - Switch backward through windows  
- `Cmd+Alt+\`` - Instant switch to second window

### Configuration

The extension provides these settings:

- `backtick-plus-plus.activationMode`: How window activation is handled
  - `automatic` (default): Current window moves to top of list
  - `manual`: Preserves current window order

- `backtick-plus-plus.newWindowPosition`: Where new windows appear
  - `top` (default): New windows at top of list
  - `bottom`: New windows at bottom of list

### First-Time Setup

1. The extension will automatically start the helper process
2. You'll be prompted to grant Accessibility permissions
3. Click "Request Permission" and approve in System Preferences
4. Reload VS Code window when prompted

## Troubleshooting

### Helper Process Issues

**Helper not starting:**
```bash
# Check if binary exists
ls -la swift-helper/.build/release/backtick-plus-plus-helper

# Test manual launch
swift-helper/.build/release/backtick-plus-plus-helper
```

**Permission issues:**
- Go to System Preferences → Security & Privacy → Privacy → Accessibility
- Add the helper binary or app bundle
- Restart VS Code

**Socket issues:**
```bash
# Remove stale socket
rm -f /tmp/backtick-plus-plus-helper.sock

# Check for running processes
ps aux | grep backtick-plus-plus-helper
```

### Extension Issues

**TypeScript compilation errors:**
```bash
cd vscode-extension
npm run compile
```

**Extension not loading:**
- Check the VS Code Developer Console (`Help → Toggle Developer Tools`)
- Look for error messages in the Console tab

### Logs

**Swift helper logs:**
```bash
log stream --predicate 'subsystem == "com.backtickpp.helper"' --level debug
```

**VS Code extension logs:**
- Open Command Palette (`Cmd+Shift+P`)
- Type "Developer: Reload Window"
- Check Debug Console for output

## Project Structure

```
backtickpp/
├── swift-helper/                 # Swift background process
│   ├── Package.swift            # Swift Package Manager config
│   ├── Info.plist              # App bundle configuration
│   ├── build.sh                # Build script
│   ├── package.sh              # App bundle packaging script
│   └── Sources/
│       └── BacktickPlusPlusHelper/
│           ├── main.swift       # Entry point
│           ├── WindowHelper.swift # Core window management
│           └── SocketServer.swift # IPC server
├── vscode-extension/            # VS Code extension
│   ├── package.json            # Extension manifest
│   ├── tsconfig.json           # TypeScript configuration
│   └── src/
│       ├── extension.ts        # Extension entry point
│       ├── helperProcess.ts    # Helper process client
│       └── windowSwitcher.ts   # Window switching UI
├── prompts/                    # Development specifications
└── README.md                   # This file
```

## Contributing

1. Make changes in the appropriate subfolder
2. Test both components together
3. Update this README if needed
4. Follow the existing code style

## License

MIT License - see LICENSE file for details.
