import * as vscode from 'vscode';
import * as net from 'net';
import * as fs from 'fs';
import * as path from 'path';
import { spawn, ChildProcess } from 'child_process';

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

class HelperProcess {
    private static readonly SOCKET_PATH = '/tmp/backtick-plus-plus-helper.sock';
    private helperProcess: ChildProcess | null = null;

    async start(): Promise<void> {
        // Kill any existing helper processes
        await this.killExistingHelpers();

        // Find and start the helper binary
        const helperPath = this.findHelperBinary();
        if (!helperPath) {
            throw new Error('Helper binary not found. Please build the Swift helper first.');
        }

        this.helperProcess = spawn(helperPath, [], {
            detached: true,
            stdio: 'ignore'
        });

        // Wait a moment for the helper to start
        await new Promise(resolve => setTimeout(resolve, 1000));

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

    private findHelperBinary(): string | null {
        const extensionPath = path.dirname(path.dirname(__dirname));
        const possiblePaths = [
            // Swift Package Manager builds
            path.join(extensionPath, 'swift-helper', '.build', 'release', 'backtick-plus-plus-helper'),
            path.join(extensionPath, 'swift-helper', '.build', 'debug', 'backtick-plus-plus-helper'),
            path.join(extensionPath, '..', 'swift-helper', '.build', 'release', 'backtick-plus-plus-helper'),
            path.join(extensionPath, '..', 'swift-helper', '.build', 'debug', 'backtick-plus-plus-helper'),
            // Makefile builds
            path.join(extensionPath, 'swift-helper', 'build', 'backtick-plus-plus-helper'),
            path.join(extensionPath, '..', 'swift-helper', 'build', 'backtick-plus-plus-helper'),
            // App bundle
            path.join(extensionPath, 'swift-helper', 'backtick-plus-plus-helper.app', 'Contents', 'MacOS', 'backtick-plus-plus-helper'),
            path.join(extensionPath, '..', 'swift-helper', 'backtick-plus-plus-helper.app', 'Contents', 'MacOS', 'backtick-plus-plus-helper'),
        ];

        for (const helperPath of possiblePaths) {
            if (fs.existsSync(helperPath)) {
                return helperPath;
            }
        }

        return null;
    }

    private async sendCommand(command: string, data: string): Promise<string> {
        return new Promise((resolve, reject) => {
            const client = net.createConnection(HelperProcess.SOCKET_PATH);
            let response = '';

            client.on('connect', () => {
                const message = data ? `${command}:${data}` : command;
                client.write(message);
            });

            client.on('data', (chunk) => {
                response += chunk.toString();
            });

            client.on('end', () => {
                if (response.startsWith('ERROR:')) {
                    reject(new Error(response.substring(6)));
                } else {
                    resolve(response.startsWith('OK:') ? response.substring(3) : response);
                }
            });

            client.on('error', (error) => {
                reject(error);
            });

            // Timeout after 5 seconds
            setTimeout(() => {
                client.destroy();
                reject(new Error('Command timeout'));
            }, 5000);
        });
    }

    private async showPermissionDialog(): Promise<string | undefined> {
        return vscode.window.showInformationMessage(
            'Backtick++ needs Accessibility permissions to manage VS Code windows.',
            'Request Permission',
            'Cancel'
        );
    }
}

// MARK: - Window Switcher

class WindowSwitcher {
    private quickPick: vscode.QuickPick<vscode.QuickPickItem> | null = null;
    private windows: WindowInfo[] = [];
    private currentIndex = 0;

    constructor(private helperProcess: HelperProcess) { }

    async showSwitcher(direction: 'forward' | 'backward'): Promise<void> {
        try {
            const config = vscode.workspace.getConfiguration('backtick-plus-plus');
            const newWindowPosition = config.get<string>('newWindowPosition', 'top');
            const activationMode = config.get<string>('activationMode', 'automatic');

            this.windows = await this.helperProcess.getWindows(newWindowPosition, activationMode);

            if (this.windows.length <= 1) {
                vscode.window.showInformationMessage('Only one VS Code window found');
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
            vscode.window.showErrorMessage(`Failed to get windows: ${error.message}`);
        }
    }

    async instantSwitch(): Promise<void> {
        try {
            const config = vscode.workspace.getConfiguration('backtick-plus-plus');
            const newWindowPosition = config.get<string>('newWindowPosition', 'top');
            const activationMode = config.get<string>('activationMode', 'automatic');

            const windows = await this.helperProcess.getWindows(newWindowPosition, activationMode);

            if (windows.length < 2) {
                vscode.window.showInformationMessage('Need at least 2 VS Code windows for instant switch');
                return;
            }

            // Activate the second window in the list
            await this.helperProcess.activateWindow(windows[1].id);
        } catch (error: any) {
            vscode.window.showErrorMessage(`Failed to switch windows: ${error.message}`);
        }
    }

    private showQuickPick(): void {
        if (this.quickPick) {
            this.quickPick.dispose();
        }

        this.quickPick = vscode.window.createQuickPick();
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
                vscode.window.showErrorMessage(`Failed to activate window: ${error.message}`);
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
    helperProcess = new HelperProcess();
    windowSwitcher = new WindowSwitcher(helperProcess);

    // Register commands
    const switchForward = vscode.commands.registerCommand('backtick-plus-plus.switchForward', () => {
        windowSwitcher.showSwitcher('forward');
    });

    const switchBackward = vscode.commands.registerCommand('backtick-plus-plus.switchBackward', () => {
        windowSwitcher.showSwitcher('backward');
    });

    const instantSwitch = vscode.commands.registerCommand('backtick-plus-plus.instantSwitch', () => {
        windowSwitcher.instantSwitch();
    });

    context.subscriptions.push(switchForward, switchBackward, instantSwitch);

    // Start helper process
    helperProcess.start().catch((error: any) => {
        vscode.window.showErrorMessage(`Failed to start Backtick++ helper: ${error.message}`);
    });
}

export function deactivate() {
    console.log('Backtick++ extension is being deactivated');
    if (helperProcess) {
        helperProcess.shutdown();
    }
}
