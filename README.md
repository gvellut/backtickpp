# Backtick++ 

Quick window switching for VS Code on macOS (with shortcuts).

The order of the windows will be updated and recalled (similar to the "View: Quick Open Previous Recently Used Editor in Group" command).

## Architecture

This project consists of two main components:

1. **Swift Helper Process** (`swift-helper/`): A background macOS executable that handles window management using Accessibility APIs
2. **VS Code Extension** (`vscode-extension/`): The user-facing extension that provides UI and commands

The Swift Helper Process is the one doing the window switching. It handles the gathering of the VS Code window titles using the macOS Accessibility API.

## Prerequisites

- macOS 12.0 or later
- Xcode Command Line Tools (for Swift compilation)
- Node.js 18+ (for VS Code extension development)
- VS Code 1.80.0 or later

## Building

### Swift Helper Process

The Swift helper is a background process that manages VS Code windows using macOS Accessibility APIs.

```bash
cd swift-helper
./package.sh
```

This creates a `Backtick++ Helper.app` bundle that can be distributed. It simply contains a command-line executable (so cannot be launched manually, but will be launched by the VS Code extension).

Copy the `.app` in `/Applications` (this is the default name and will be found by the VS Code extension). Or use the `backtick-plus-plus.helperAppPath` VS Code setting to point at the executable `Contents/MacOS/backtick-plus-plus-helper` inside the `.app` anywhere.

### VS Code Extension

#### Install Dependencies
```bash
cd vscode-extension
npm install
```

#### Package Extension (VSIX)
```bash
cd vscode-extension
npx vsce package
```

This creates a `.vsix` file that can be installed in VS Code: In the Extensions view, click the ellipsis (...) and select "Install from VSIX...".

## Usage

### Keyboard Shortcuts

- `cmd+alt+shift+f` - Switch forward through windows
- `cmd+alt+shift+g` - Switch backward through windows  
- `cmd+alt+shift+d` - Instant switch to second window (to switch between 2 windows quickly)

The *Switch forward* and *Switch backward* can be pressed multiple times while the quick switch listbox is open in VS Code. 

However, *Enter* must be pressed to select the window to switch to: This differs from the "View: Quick Open Previous Recently Used Editor in Group", usually Ctrl-Tab, where an editor is selected when Ctrl is let go (that behaviour doesn't seem to be available for extensions).

*Escape* or focusing outside the listbox will dismiss the quick switch.

### Configuration

The extension provides these settings:

- `backtick-plus-plus.activationMode`: How window activation is handled (if done outside the extension)
  - `automatic` (default): Current window moves to top of list
  - `manual`: Preserves current window order

- `backtick-plus-plus.newWindowPosition`: Where new windows appear
  - `top` (default): New windows at top of list
  - `bottom`: New windows at bottom of list

- `backtick-plus-plus.helperAppPath`: Full path to the executable of the Backtick++ Helper (usually inside an `.app`)

### First-Time Setup

1. The extension will automatically start the helper process
2. You'll be prompted to grant Accessibility permissions (used by the Backtick++ Helper to gather the titles of all the VS Code windows)
3. Click "Request Permission" and approve in System Preferences. VS Code will be the application requesting that permission since it is launching the Helper.
4. Reload VS Code window when prompted

## Development & Debugging

### Swift Helper

The simplest is to use the Swift VS Code extension and launch the executable in debug mode.

Manually:

#### Debug Build
```bash
cd swift-helper
swift build -c debug
.build/debug/backtick-plus-plus-helpers
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

1. Create a task that run `npm run compile` and called **Extension: Compile TypeScript** (used by 2.)
2. Create an `extensionHost` launch configuration. Set the path since the code for the extension is not at the root of the project. For example:
```json
 {
    "name": "Run Extension",
    "type": "extensionHost",
    "request": "launch",
    "args": [
        "--extensionDevelopmentPath=${workspaceFolder}/vscode-extension"
    ],
    "preLaunchTask": "Extension: Compile TypeScript"
}
```
3. Launch the *Backtick++ Helper* manually (in dev mode, it is not launched by the extension)
4. Press `F5` to launch Extension Development Host
5. The extension will be loaded in the new VS Code window

#### Debug Console
- Use `console.log()` in your TypeScript code
- View output in the Debug Console of the main VS Code window

#### Live Reload
```bash
cd vscode-extension
npm run watch
```

After making changes, reload the Extension Development Host window (`Cmd+R`).