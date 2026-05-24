import * as vscode from 'vscode';
import { findTelegramChatCandidates, sendTelegramMessageWithConfig } from '../agent/tools';

export class TelegramSettingsPanel {
    public static readonly viewType = 'noriter-ai.telegramSettings';
    private static currentPanel: TelegramSettingsPanel | undefined;

    private readonly panel: vscode.WebviewPanel;
    private readonly extensionUri: vscode.Uri;
    private readonly disposables: vscode.Disposable[] = [];

    public static createOrShow(extensionUri: vscode.Uri) {
        const column = vscode.window.activeTextEditor?.viewColumn;

        if (TelegramSettingsPanel.currentPanel) {
            TelegramSettingsPanel.currentPanel.panel.reveal(column);
            void TelegramSettingsPanel.currentPanel.refresh();
            return;
        }

        const panel = vscode.window.createWebviewPanel(
            TelegramSettingsPanel.viewType,
            'Telegram Integration',
            column || vscode.ViewColumn.One,
            {
                enableScripts: true,
                retainContextWhenHidden: true
            }
        );

        TelegramSettingsPanel.currentPanel = new TelegramSettingsPanel(panel, extensionUri);
    }

    private constructor(panel: vscode.WebviewPanel, extensionUri: vscode.Uri) {
        this.panel = panel;
        this.extensionUri = extensionUri;

        this.panel.onDidDispose(() => this.dispose(), null, this.disposables);
        this.panel.webview.onDidReceiveMessage((message) => {
            void this.handleMessage(message);
        }, null, this.disposables);

        void this.refresh();
    }

    private async refresh() {
        const config = vscode.workspace.getConfiguration('noriter-ai');
        const botToken = config.get<string>('telegramBotToken') || '';
        const chatId = config.get<string>('telegramChatId') || '';
        const enabled = config.get<boolean>('telegramEnableChatBridge', false);

        this.panel.webview.html = this.getHtml(botToken, chatId, enabled);
    }

    private async handleMessage(message: any) {
        switch (message.type) {
            case 'saveSettings': {
                const botToken = typeof message.botToken === 'string' ? message.botToken.trim() : '';
                const chatId = typeof message.chatId === 'string' ? message.chatId.trim() : '';
                const enableBridge = Boolean(message.enableBridge);
                const target = vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders.length > 0
                    ? vscode.ConfigurationTarget.Workspace
                    : vscode.ConfigurationTarget.Global;

                await vscode.workspace.getConfiguration('noriter-ai').update('telegramBotToken', botToken, target);
                await vscode.workspace.getConfiguration('noriter-ai').update('telegramChatId', chatId, target);
                await vscode.workspace.getConfiguration('noriter-ai').update('telegramEnableChatBridge', enableBridge, target);

                void vscode.window.showInformationMessage('Telegram settings saved.');
                break;
            }
            case 'testMessage': {
                const botToken = typeof message.botToken === 'string' ? message.botToken.trim() : '';
                const chatId = typeof message.chatId === 'string' ? message.chatId.trim() : '';
                const text = typeof message.text === 'string' && message.text.trim()
                    ? message.text.trim()
                    : `[Noriter AI] Telegram integration test at ${new Date().toLocaleString()}`;

                if (!botToken || !chatId) {
                    void vscode.window.showErrorMessage('Please enter bot token and chat ID first.');
                    return;
                }

                const result = await sendTelegramMessageWithConfig(botToken, chatId, text);
                if (result.startsWith('Telegram message sent successfully')) {
                    void vscode.window.showInformationMessage('Telegram test message sent.');
                    void this.panel.webview.postMessage({ type: 'diagnostic', value: 'Test message sent successfully.' });
                } else {
                    void vscode.window.showErrorMessage(result);
                    void this.panel.webview.postMessage({ type: 'diagnostic', value: result });
                }
                break;
            }
            case 'findChatId': {
                const botToken = typeof message.botToken === 'string' ? message.botToken.trim() : '';
                if (!botToken) {
                    void vscode.window.showErrorMessage('Please enter bot token first.');
                    return;
                }

                const result = await findTelegramChatCandidates(botToken);
                void this.panel.webview.postMessage({ type: 'chatCandidates', value: result });
                break;
            }
        }
    }

    private getHtml(botToken: string, chatId: string, enabled: boolean): string {
        const nonce = getNonce();
        const escapedToken = escapeHtml(botToken);
        const escapedChatId = escapeHtml(chatId);
        const checked = enabled ? 'checked' : '';

        return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';">
    <title>Telegram Integration</title>
    <style>
        body {
            font-family: var(--vscode-font-family);
            color: var(--vscode-foreground);
            background: var(--vscode-editor-background);
            padding: 16px;
        }
        .wrap {
            display: grid;
            gap: 12px;
            max-width: 640px;
        }
        label {
            font-size: 12px;
            color: var(--vscode-descriptionForeground);
        }
        input[type="text"], input[type="password"], textarea {
            width: 100%;
            box-sizing: border-box;
            background: var(--vscode-input-background);
            color: var(--vscode-input-foreground);
            border: 1px solid var(--vscode-input-border);
            border-radius: 6px;
            padding: 8px;
            font-family: inherit;
        }
        input[type="checkbox"] {
            margin-right: 8px;
            vertical-align: middle;
        }
        textarea { min-height: 90px; resize: vertical; }
        .row {
            display: flex;
            gap: 8px;
        }
        button {
            border: none;
            border-radius: 6px;
            padding: 8px 12px;
            cursor: pointer;
            background: var(--vscode-button-background);
            color: var(--vscode-button-foreground);
        }
        button:hover { background: var(--vscode-button-hoverBackground); }
        .hint {
            font-size: 12px;
            color: var(--vscode-descriptionForeground);
            line-height: 1.5;
        }
        pre {
            margin: 0;
            background: var(--vscode-textCodeBlock-background);
            border-radius: 6px;
            padding: 10px;
            white-space: pre-wrap;
            font-family: var(--vscode-editor-font-family, monospace);
            font-size: 12px;
            border: 1px solid var(--vscode-panel-border);
        }
    </style>
</head>
<body>
    <div class="wrap">
        <h2>Telegram Bot Integration</h2>
        <div class="hint">Bot token and chat ID are saved in Noriter AI settings. Use this window to configure and test delivery.</div>
        <div class="hint">If you see "Bad Request: chat not found", click "Find Chat IDs" after sending a message to your bot in Telegram.</div>

        <div>
            <label>
                <input id="enableBridge" type="checkbox" ${checked} />
                Enable Telegram chat bridge (agent replies to Telegram messages)
            </label>
        </div>

        <div>
            <label for="botToken">Bot Token</label>
            <input id="botToken" type="password" value="${escapedToken}" placeholder="123456:ABC..." />
        </div>

        <div>
            <label for="chatId">Chat ID</label>
            <input id="chatId" type="text" value="${escapedChatId}" placeholder="e.g. 123456789 or -100..." />
        </div>

        <div>
            <label for="testMessage">Test Message</label>
            <textarea id="testMessage" placeholder="Optional custom test message"></textarea>
        </div>

        <div class="row">
            <button id="saveBtn">Save Settings</button>
            <button id="testBtn">Send Test Message</button>
            <button id="findBtn">Find Chat IDs</button>
        </div>

        <div>
            <label>Diagnostics</label>
            <pre id="diagnostic">No diagnostics yet.</pre>
        </div>
    </div>

    <script nonce="${nonce}">
        const vscode = acquireVsCodeApi();
        const botTokenEl = document.getElementById('botToken');
        const chatIdEl = document.getElementById('chatId');
        const enableBridgeEl = document.getElementById('enableBridge');
        const testMessageEl = document.getElementById('testMessage');
        const diagnosticEl = document.getElementById('diagnostic');
        const saveBtn = document.getElementById('saveBtn');
        const testBtn = document.getElementById('testBtn');
        const findBtn = document.getElementById('findBtn');

        saveBtn.addEventListener('click', () => {
            vscode.postMessage({
                type: 'saveSettings',
                botToken: botTokenEl.value,
                chatId: chatIdEl.value,
                enableBridge: enableBridgeEl.checked
            });
        });

        testBtn.addEventListener('click', () => {
            vscode.postMessage({
                type: 'testMessage',
                botToken: botTokenEl.value,
                chatId: chatIdEl.value,
                text: testMessageEl.value
            });
        });

        findBtn.addEventListener('click', () => {
            vscode.postMessage({
                type: 'findChatId',
                botToken: botTokenEl.value
            });
        });

        window.addEventListener('message', (event) => {
            const message = event.data;
            if (message.type === 'chatCandidates' || message.type === 'diagnostic') {
                diagnosticEl.textContent = message.value || 'No result.';
            }
        });
    </script>
</body>
</html>`;
    }

    public dispose() {
        TelegramSettingsPanel.currentPanel = undefined;
        this.panel.dispose();

        while (this.disposables.length) {
            const disposable = this.disposables.pop();
            if (disposable) {
                disposable.dispose();
            }
        }
    }
}

function getNonce() {
    let text = '';
    const possible = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    for (let i = 0; i < 32; i++) {
        text += possible.charAt(Math.floor(Math.random() * possible.length));
    }
    return text;
}

function escapeHtml(value: string): string {
    return value
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}
