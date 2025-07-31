import * as vscode from 'vscode';
import { HelperProcess, WindowInfo } from './helperProcess';

export class WindowSwitcher {
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
