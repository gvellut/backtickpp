import type * as vscode from 'vscode';
import * as net from 'net';
import * as fs from 'fs';
import * as path from 'path';
import { spawn, ChildProcess } from 'child_process';
import { execSync } from 'child_process';

let vscodeAPI: typeof vscode;

try {
    vscodeAPI = require('vscode');
} catch (e) {
    console.log('Running outside of VS Code, using mock vscode API');
    vscodeAPI = {
        window: {
            showInformationMessage: (message: string) => { console.log(`INFO: ${message}`); return Promise.resolve(undefined); },
            showErrorMessage: (message: string) => { console.error(`ERROR: ${message}`); return Promise.resolve(undefined); },
            createQuickPick: () => ({
                items: [],
                activeItems: [],
                placeholder: '',
                canSelectMany: false,
                onDidAccept: () => ({ dispose: () => { } }),
                onDidChangeActive: () => ({ dispose: () => { } }),
                onDidHide: () => ({ dispose: () => { } }),
                show: () => { },
                hide: () => { },
                dispose: () => { },
            } as any),
        },
        workspace: {
            getConfiguration: () => ({
                get: (key: string, defaultValue: any) => defaultValue,
            } as any),
        },
        commands: {
            registerCommand: () => ({ dispose: () => { } }),
        },
    } as any;
}

// MARK: - Interfaces

export interface WindowInfo {
    id: number;
    title: string;
    isCurrentlyActive: boolean;
}

export interface StatusResponse {
    hasAccessibilityPermission: boolean;
}

// MARK: - Helper Process

export class HelperProcess {
    private static readonly SOCKET_PATH = '/tmp/backtick-plus-plus-helper.sock';
    private helperProcess: ChildProcess | null = null;
    private vscode: typeof vscodeAPI | undefined;

    constructor(vscodeInstance?: typeof vscodeAPI) {
        this.vscode = vscodeInstance;
    }

    async start(isDev: boolean): Promise<void> {
        if (isDev) {
            // do not initialize : assumes helper is launched externally in debug mode
            return;
        }

        // Kill any existing helper processes
        await this.killExistingHelpers();

        // Find and start the helper binary
        const helperPath = this.findHelperBinary(isDev);
        if (!helperPath) {
            throw new Error('Helper binary not found. Please build the Swift helper first.');
        }
        console.log(`Found helper binary at: ${helperPath}`);

        console.log('Spawning helper process...');
        this.helperProcess = spawn(helperPath, [], {
            detached: false, // Tie helper lifecycle to the extension
            stdio: 'ignore'
        });
        // this.helperProcess.unref(); // No longer needed with detached: false

        // Wait a moment for the helper to start
        await new Promise(resolve => setTimeout(resolve, 1000));
    }

    async checkStatusAndPermissions(): Promise<void> {
        // Check if helper is responding
        const status = await this.getStatus();
        if (!status.hasAccessibilityPermission) {
            const action = await this.showPermissionDialog();
            if (action === 'Request Permission') {
                await this.requestPermission();
            }
        }
    }

    async shutdown(): Promise<void> {
        try {
            await this.sendCommand('shutdown', '');
        } catch (error) {
            // Helper might already be down
        }

        if (this.helperProcess) {
            this.helperProcess.kill();
            this.helperProcess = null;
        }
    }

    async getStatus(): Promise<StatusResponse> {
        const response = await this.sendCommand('getStatus', '');
        return JSON.parse(response);
    }

    async requestPermission(): Promise<void> {
        await this.sendCommand('requestPermission', '');
    }

    async getWindows(newWindowPosition: string, activationMode: string): Promise<WindowInfo[]> {
        const request = JSON.stringify({ newWindowPosition, activationMode });
        const response = await this.sendCommand('getWindows', request);
        return JSON.parse(response);
    }

    async activateWindow(id: number): Promise<void> {
        const request = JSON.stringify({ id });
        await this.sendCommand('activateWindow', request);
    }

    private async killExistingHelpers(): Promise<void> {
        try {
            // Try to connect to existing socket and send shutdown
            await this.sendCommand('shutdown', '');
        } catch (error) {
            // No existing helper or already shut down
        }

        // Remove socket file if it exists
        if (fs.existsSync(HelperProcess.SOCKET_PATH)) {
            fs.unlinkSync(HelperProcess.SOCKET_PATH);
        }
    }

    private findHelperBinary(isDev: boolean): string | null {
        // 1. Check config option (should be a direct path to the executable)
        let configPath = '';
        if (this.vscode && this.vscode.workspace) {
            const config = this.vscode.workspace.getConfiguration('backtick-plus-plus');
            configPath = config.get<string>('helperAppPath', '').trim();
        }
        if (configPath && fs.existsSync(configPath)) {
            return configPath;
        }
        // 2. Check /Applications for .app bundle executable
        const appExe = '/Applications/Backtick++ Helper.app/Contents/MacOS/backtick-plus-plus-helper';
        if (fs.existsSync(appExe)) {
            return appExe;
        }
        // 3. Only check dev locations if isDev
        if (isDev) {
            const extensionPath = path.dirname(path.dirname(__dirname));
            const possiblePaths = [
                path.join(extensionPath, 'swift-helper', '.build', 'release', 'backtick-plus-plus-helper'),
                path.join(extensionPath, 'swift-helper', '.build', 'debug', 'backtick-plus-plus-helper'),
                path.join(extensionPath, '..', 'swift-helper', '.build', 'release', 'backtick-plus-plus-helper'),
                path.join(extensionPath, '..', 'swift-helper', '.build', 'debug', 'backtick-plus-plus-helper'),
                path.join(extensionPath, 'swift-helper', 'build', 'backtick-plus-plus-helper'),
                path.join(extensionPath, '..', 'swift-helper', 'build', 'backtick-plus-plus-helper'),
                path.join(extensionPath, 'swift-helper', 'backtick-plus-plus-helper.app', 'Contents', 'MacOS', 'backtick-plus-plus-helper'),
                path.join(extensionPath, '..', 'swift-helper', 'backtick-plus-plus-helper.app', 'Contents', 'MacOS', 'backtick-plus-plus-helper'),
            ];
            for (const helperPath of possiblePaths) {
                if (fs.existsSync(helperPath)) {
                    return helperPath;
                }
            }
        }
        return null;
    }

    /**
     * Sends a command to the helper process socket using the synchronous `netcat` utility.
     *
     * This method uses `execSync` to call `nc` because the Swift server is highly responsive
     * and closes the connection immediately after its first read. The standard async `net`
     * module in Node.js can introduce a micro-delay, causing a race condition where the
     * server closes the socket before the client can write to it, resulting in an EPIPE error.
     * Using a blocking, synchronous tool like `netcat` ensures the connect-and-write operation
     * is atomic and fast enough to succeed.
     *
     * @param command The command to send.
     * @param data The data payload for the command.
     * @returns A Promise that resolves with the server's response.
     */
    private async sendCommand(command: string, data: string): Promise<string> {
        return new Promise((resolve, reject) => {
            const socketPath = HelperProcess.SOCKET_PATH;
            const message = data ? `${command}:${data}` : command;

            // --- CRITICAL SECURITY STEP: Sanitize input to prevent shell command injection ---
            // This replaces every single quote with '\'' which is the safe way to embed a
            // single quote within another single-quoted shell string.
            const sanitizedMessage = message.replace(/'/g, "'\\''");

            // The shell command to execute:
            // 1. `echo '${sanitizedMessage}'`: Prints our sanitized message to standard output.
            // 2. `|`: Pipes that output to the standard input of the next command.
            // 3. `nc -U '${socketPath}'`: `netcat` connects to the specified Unix Domain Socket (`-U`)
            //    and writes whatever it receives from its standard input.
            const shellCommand = `echo '${sanitizedMessage}' | nc -U '${socketPath}'`;

            try {
                // `execSync` blocks until the shell command finishes. We wrap it in a Promise
                // to maintain the async signature of the parent function.
                const responseBuffer = execSync(shellCommand, {
                    // Set a timeout for the entire operation to prevent indefinite hangs.
                    // timeout: 5000, // 5 seconds
                    // Suppress stderr from appearing in the main console to handle errors gracefully.
                    stdio: 'pipe'
                });

                // Convert the response buffer to a string and trim any trailing newline.
                const response = responseBuffer.toString('utf8').trim();

                if (response.startsWith('ERROR:')) {
                    reject(new Error(response.substring(6)));
                } else {
                    resolve(response.startsWith('OK:') ? response.substring(3) : response);
                }

            } catch (error: any) {
                // This block catches errors from execSync, such as:
                //  - The `nc` command timing out.
                //  - `nc` not being installed on the system.
                //  - `nc` failing to connect (e.g., socket doesn't exist).
                reject(new Error(`Socket communication failed: ${error.message}`));
            }
        });
    }

    private async showPermissionDialog(): Promise<string | undefined> {
        if (this.vscode && this.vscode.window) {
            return this.vscode.window.showInformationMessage(
                'Backtick++ needs Accessibility permissions to manage VS Code windows.',
                'Request Permission',
                'Cancel'
            );
        } else {
            console.log('Backtick++ needs Accessibility permissions. Please grant them in System Settings.');
            // For a CLI, we might not be able to programmatically ask.
            // Let's assume 'Request Permission' for CLI testing purposes.
            return 'Request Permission';
        }
    }
}

// MARK: - Window Switcher

class WindowSwitcher {
    private quickPick: vscode.QuickPick<vscode.QuickPickItem> | null = null;
    private windows: WindowInfo[] = [];
    private currentIndex = 0;
    private helperProcess: HelperProcess;
    private vscode: typeof vscodeAPI;

    constructor(helperProcess: HelperProcess, vscodeInstance: typeof vscodeAPI) {
        this.helperProcess = helperProcess;
        this.vscode = vscodeInstance;
    }

    async showSwitcher(direction: 'forward' | 'backward'): Promise<void> {
        try {
            const config = this.vscode.workspace.getConfiguration('backtick-plus-plus');
            const newWindowPosition = config.get<string>('newWindowPosition', 'top');
            const activationMode = config.get<string>('activationMode', 'automatic');

            this.windows = await this.helperProcess.getWindows(newWindowPosition, activationMode);

            if (this.windows.length <= 1) {
                this.vscode.window.showInformationMessage('Only one VS Code window found');
                return;
            }

            // Find current active window index
            const activeIndex = this.windows.findIndex(w => w.isCurrentlyActive);

            // Calculate initial selection based on direction
            if (direction === 'forward') {
                this.currentIndex = activeIndex === -1 ? 1 : (activeIndex + 1) % this.windows.length;
            } else {
                this.currentIndex = activeIndex === -1 ? this.windows.length - 1 :
                    (activeIndex - 1 + this.windows.length) % this.windows.length;
            }

            this.showQuickPick();
        } catch (error: any) {
            this.vscode.window.showErrorMessage(`Failed to get windows: ${error.message}`);
        }
    }

    async instantSwitch(): Promise<void> {
        try {
            const config = this.vscode.workspace.getConfiguration('backtick-plus-plus');
            const newWindowPosition = config.get<string>('newWindowPosition', 'top');
            const activationMode = config.get<string>('activationMode', 'automatic');

            const windows = await this.helperProcess.getWindows(newWindowPosition, activationMode);

            if (windows.length < 2) {
                this.vscode.window.showInformationMessage('Need at least 2 VS Code windows for instant switch');
                return;
            }

            // Activate the second window in the list
            await this.helperProcess.activateWindow(windows[1].id);
        } catch (error: any) {
            this.vscode.window.showErrorMessage(`Failed to switch windows: ${error.message}`);
        }
    }

    private showQuickPick(): void {
        if (this.quickPick) {
            this.quickPick.dispose();
        }

        this.quickPick = this.vscode.window.createQuickPick();
        this.quickPick.placeholder = 'Select a VS Code window';
        this.quickPick.canSelectMany = false;

        // Create quick pick items
        this.quickPick.items = this.windows.map((window, index) => ({
            label: window.title,
            description: window.isCurrentlyActive ? '(current)' : '',
            detail: `Window ID: ${window.id}`,
            picked: index === this.currentIndex
        }));

        // Set initial selection
        this.quickPick.activeItems = [this.quickPick.items[this.currentIndex]];

        // Handle selection
        this.quickPick.onDidAccept(() => {
            this.activateSelectedWindow();
        });

        // Handle key navigation
        this.quickPick.onDidChangeActive((items) => {
            if (items.length > 0) {
                const selectedIndex = this.quickPick!.items.indexOf(items[0]);
                if (selectedIndex !== -1) {
                    this.currentIndex = selectedIndex;
                }
            }
        });

        // Handle hide
        this.quickPick.onDidHide(() => {
            this.quickPick?.dispose();
            this.quickPick = null;
        });

        this.quickPick.show();
    }

    private async activateSelectedWindow(): Promise<void> {
        if (this.currentIndex >= 0 && this.currentIndex < this.windows.length) {
            const selectedWindow = this.windows[this.currentIndex];
            try {
                await this.helperProcess.activateWindow(selectedWindow.id);
            } catch (error: any) {
                this.vscode.window.showErrorMessage(`Failed to activate window: ${error.message}`);
            }
        }

        if (this.quickPick) {
            this.quickPick.hide();
        }
    }
}

// MARK: - Extension Entry Point

let helperProcess: HelperProcess;
let windowSwitcher: WindowSwitcher;

export function activate(context: vscode.ExtensionContext) {
    console.log('Backtick++ extension is now active');

    // Initialize helper process
    helperProcess = new HelperProcess(vscodeAPI);
    windowSwitcher = new WindowSwitcher(helperProcess, vscodeAPI);

    // Register commands
    const switchForward = vscodeAPI.commands.registerCommand('backtick-plus-plus.switchForward', () => {
        windowSwitcher.showSwitcher('forward');
    });

    const switchBackward = vscodeAPI.commands.registerCommand('backtick-plus-plus.switchBackward', () => {
        windowSwitcher.showSwitcher('backward');
    });

    const instantSwitch = vscodeAPI.commands.registerCommand('backtick-plus-plus.instantSwitch', () => {
        windowSwitcher.instantSwitch();
    });

    context.subscriptions.push(switchForward, switchBackward, instantSwitch);

    // Start helper process
    helperProcess.start(context.extensionMode == vscodeAPI.ExtensionMode.Development)
        .then(() => helperProcess.checkStatusAndPermissions())
        .catch((error: any) => {
            if (vscodeAPI.window) {
                vscodeAPI.window.showErrorMessage(`Failed to start Backtick++ helper: ${error.message}`);
            } else {
                console.error(`Failed to start Backtick++ helper: ${error.message}`);
            }
        });
}

export function deactivate() {
    console.log('Backtick++ extension is being deactivated');
    if (helperProcess) {
        helperProcess.shutdown();
    }
}
