import * as net from 'net';
import * as fs from 'fs';
import * as path from 'path';
import { spawn, ChildProcess } from 'child_process';

export interface WindowInfo {
    id: number;
    title: string;
    isCurrentlyActive: boolean;
}

export interface StatusResponse {
    hasAccessibilityPermission: boolean;
}

export class HelperProcess {
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
        const vscode = await import('vscode');
        return vscode.window.showInformationMessage(
            'Backtick++ needs Accessibility permissions to manage VS Code windows.',
            'Request Permission',
            'Cancel'
        );
    }
}
