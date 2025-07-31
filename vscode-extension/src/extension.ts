import * as vscode from 'vscode';
import { HelperProcess } from './helperProcess';
import { WindowSwitcher } from './windowSwitcher';

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
