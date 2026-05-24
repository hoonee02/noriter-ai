import * as vscode from 'vscode';
import { SidebarProvider } from './webview/sidebarProvider';
import { TelegramBridge } from './telegram/telegramBridge';

let telegramBridge: TelegramBridge | undefined;

export function activate(context: vscode.ExtensionContext) {
    const sidebarProvider = new SidebarProvider(context.extensionUri, context);
    telegramBridge = new TelegramBridge(context);

    context.subscriptions.push(
        vscode.window.registerWebviewViewProvider(
            SidebarProvider.viewType,
            sidebarProvider
        )
    );

    context.subscriptions.push(
        vscode.workspace.onDidChangeConfiguration((event) => {
            if (
                event.affectsConfiguration('noriter-ai.telegramEnableChatBridge') ||
                event.affectsConfiguration('noriter-ai.telegramBotToken') ||
                event.affectsConfiguration('noriter-ai.telegramChatId')
            ) {
                telegramBridge?.stop();
                void telegramBridge?.refresh();
            }
        })
    );

    void telegramBridge?.refresh();
}

export function deactivate() {
    telegramBridge?.stop();
}
