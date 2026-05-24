import * as vscode from 'vscode';
import { SidebarProvider } from './webview/sidebarProvider';

export function activate(context: vscode.ExtensionContext) {
    const sidebarProvider = new SidebarProvider(context.extensionUri, context);

    context.subscriptions.push(
        vscode.window.registerWebviewViewProvider(
            SidebarProvider.viewType,
            sidebarProvider
        )
    );
}

export function deactivate() {}
