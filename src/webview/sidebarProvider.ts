import * as vscode from 'vscode';
import { LocalAgent } from '../agent/localAgent';
import { ensureMemoryFile, ensureGoalFile } from '../agent/tools';
import { TelegramSettingsPanel } from './telegramSettingsPanel';

type ChatEntryType = 'user' | 'assistant' | 'error';

interface ChatEntry {
    type: ChatEntryType;
    text: string;
    timestamp: number;
}

interface ModelMessage {
    role: 'user' | 'assistant';
    content: string;
}

export class SidebarProvider implements vscode.WebviewViewProvider {
    public static readonly viewType = 'noriter-ai.chatView';
    private static readonly historyStorageKey = 'noriter-ai.chatHistory';

    private _view?: vscode.WebviewView;
    private _agent: LocalAgent;
    private _cancellationTokenSource?: vscode.CancellationTokenSource;
    private _history: ChatEntry[] = [];
    private _maxHistoryEntries = 300;
    private _maxContextMessages = 20;

    constructor(
        private readonly _extensionUri: vscode.Uri,
        private readonly _context: vscode.ExtensionContext
    ) {
        this._agent = new LocalAgent();
        this.loadSettings();
        this.loadHistory();
    }

    private loadSettings() {
        const config = vscode.workspace.getConfiguration('noriter-ai');
        const configuredMax = config.get<number>('maxHistoryEntries', 300);
        const configuredContextMax = config.get<number>('maxContextMessages', 20);
        if (typeof configuredMax === 'number' && Number.isFinite(configuredMax) && configuredMax > 0) {
            this._maxHistoryEntries = Math.floor(configuredMax);
        }
        if (typeof configuredContextMax === 'number' && Number.isFinite(configuredContextMax) && configuredContextMax > 0) {
            this._maxContextMessages = Math.floor(configuredContextMax);
        }
    }

    private loadHistory() {
        const stored = this._context.workspaceState.get<ChatEntry[]>(SidebarProvider.historyStorageKey, []);
        if (Array.isArray(stored)) {
            this._history = stored
                .filter(item => item && typeof item.text === 'string' && typeof item.type === 'string')
                .map(item => ({
                    type: item.type as ChatEntryType,
                    text: item.text,
                    timestamp: typeof item.timestamp === 'number' ? item.timestamp : Date.now()
                }));
            this.trimHistory();
        }
    }

    private trimHistory() {
        if (this._history.length > this._maxHistoryEntries) {
            this._history = this._history.slice(this._history.length - this._maxHistoryEntries);
        }
    }

    private async persistHistory() {
        await this._context.workspaceState.update(SidebarProvider.historyStorageKey, this._history);
    }

    private async appendHistory(type: ChatEntryType, text: string) {
        this._history.push({
            type,
            text,
            timestamp: Date.now()
        });
        this.trimHistory();
        await this.persistHistory();
    }

    private async clearHistory() {
        this._history = [];
        await this.persistHistory();
    }

    private buildModelContextMessages(): ModelMessage[] {
        const conversationEntries = this._history.filter(
            (entry): entry is ChatEntry & { type: 'user' | 'assistant' } => entry.type === 'user' || entry.type === 'assistant'
        );
        const sliced = conversationEntries.slice(Math.max(0, conversationEntries.length - this._maxContextMessages));
        return sliced.map(entry => ({
            role: entry.type,
            content: entry.text
        }));
    }

    public resolveWebviewView(
        webviewView: vscode.WebviewView,
        _context: vscode.WebviewViewResolveContext,
        _token: vscode.CancellationToken
    ) {
        this._view = webviewView;
        this.loadSettings();
        this.loadHistory();

        webviewView.webview.options = {
            enableScripts: true,
            localResourceRoots: [
                this._extensionUri
            ]
        };

        webviewView.webview.html = this._getHtmlForWebview(webviewView.webview);

        webviewView.webview.onDidReceiveMessage(async (data) => {
            switch (data.type) {
                case 'webviewReady': {
                    this._view?.webview.postMessage({ type: 'loadHistory', entries: this._history });
                    break;
                }
                case 'sendMessage': {
                    this.startAgentSession(data.value);
                    break;
                }
                case 'clearHistory': {
                    await this.clearHistory();
                    this._view?.webview.postMessage({ type: 'historyCleared' });
                    break;
                }
                case 'openMemory': {
                    await this.openMemoryFile();
                    break;
                }
                case 'openGoal': {
                    await this.openGoalFile();
                    break;
                }
                case 'openTelegramSettings': {
                    this.openTelegramIntegrationWindow();
                    break;
                }
                case 'stopAgent': {
                    if (this._cancellationTokenSource) {
                        this._cancellationTokenSource.cancel();
                        this._cancellationTokenSource.dispose();
                        this._cancellationTokenSource = undefined;
                    }
                    break;
                }
            }
        });
    }

    private async startAgentSession(message: string) {
        if (!this._view) { return; }
        this.loadSettings();

        if (this._cancellationTokenSource) {
            this._cancellationTokenSource.cancel();
            this._cancellationTokenSource.dispose();
        }

        this._cancellationTokenSource = new vscode.CancellationTokenSource();
        const token = this._cancellationTokenSource.token;
        const contextMessages = this.buildModelContextMessages();

        await this.appendHistory('user', message);
        this._view.webview.postMessage({ type: 'sessionStart', userPrompt: message });

        try {
            await this._agent.run(
                message,
                {
                    onThought: (text) => {
                        this._view?.webview.postMessage({ type: 'thought', value: text });
                    },
                    onToolStart: (toolName, args) => {
                        this._view?.webview.postMessage({ type: 'toolStart', name: toolName, args: args });
                    },
                    onToolEnd: (toolName, output) => {
                        this._view?.webview.postMessage({ type: 'toolEnd', name: toolName, output: output });
                    },
                    onFinalAnswer: (text) => {
                        void this.appendHistory('assistant', text);
                        this._view?.webview.postMessage({ type: 'finalAnswer', value: text });
                        this._cancellationTokenSource?.dispose();
                        this._cancellationTokenSource = undefined;
                    },
                    onError: (err) => {
                        void this.appendHistory('error', err);
                        this._view?.webview.postMessage({ type: 'error', value: err });
                        this._cancellationTokenSource?.dispose();
                        this._cancellationTokenSource = undefined;
                    }
                },
                token,
                contextMessages
            );
        } catch (e: any) {
            void this.appendHistory('error', e.message);
            this._view?.webview.postMessage({ type: 'error', value: e.message });
            this._cancellationTokenSource?.dispose();
            this._cancellationTokenSource = undefined;
        }
    }

    private async openMemoryFile() {
        const workspaceFolders = vscode.workspace.workspaceFolders;
        if (!workspaceFolders || workspaceFolders.length === 0) {
            void vscode.window.showErrorMessage('No workspace folder open.');
            return;
        }

        const workspaceRoot = workspaceFolders[0].uri.fsPath;

        try {
            const memoryPath = ensureMemoryFile(workspaceRoot);
            const memoryUri = vscode.Uri.file(memoryPath);

            const doc = await vscode.workspace.openTextDocument(memoryUri);
            await vscode.window.showTextDocument(doc, { preview: false });
        } catch (error: any) {
            void vscode.window.showErrorMessage(`Failed to open memory file: ${error.message}`);
        }
    }

    private async openGoalFile() {
        const workspaceFolders = vscode.workspace.workspaceFolders;
        if (!workspaceFolders || workspaceFolders.length === 0) {
            void vscode.window.showErrorMessage('No workspace folder open.');
            return;
        }

        const workspaceRoot = workspaceFolders[0].uri.fsPath;

        try {
            const goalPath = ensureGoalFile(workspaceRoot);
            const goalUri = vscode.Uri.file(goalPath);

            const doc = await vscode.workspace.openTextDocument(goalUri);
            await vscode.window.showTextDocument(doc, { preview: false });
        } catch (error: any) {
            void vscode.window.showErrorMessage(`Failed to open goal file: ${error.message}`);
        }
    }

    private openTelegramIntegrationWindow() {
        TelegramSettingsPanel.createOrShow(this._extensionUri);
    }

    private _getHtmlForWebview(webview: vscode.Webview) {
        const styleMainUri = webview.asWebviewUri(vscode.Uri.joinPath(this._extensionUri, 'media', 'main.css'));
        const scriptMainUri = webview.asWebviewUri(vscode.Uri.joinPath(this._extensionUri, 'media', 'main.js'));
        const nonce = getNonce();

        return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${webview.cspSource}; script-src 'nonce-${nonce}';">
    <link href="${styleMainUri}" rel="stylesheet">
    <title>Noriter AI Chat</title>
</head>
<body>
    <div class="chat-container">
        <header class="chat-header">
            <h3>Noriter AI Agent</h3>
            <span class="status-indicator">Local Engine</span>
            <button id="open-goal-btn" class="goal-btn" title="에이전트 목표 파일 열기">목표</button>
            <button id="open-memory-btn" class="memory-btn" title="메모리 파일 열기">메모리</button>
            <button id="telegram-test-btn" class="telegram-btn" title="텔레그램 연동 창 열기">텔레그램</button>
            <button id="clear-history-btn" class="clear-btn" title="저장된 대화 삭제">기록 삭제</button>
        </header>

        <div id="chat-messages" class="chat-messages"></div>

        <div class="agent-activity-container" id="agent-activity" style="display: none;">
            <div class="spinner-container">
                <div class="spinner"></div>
                <span id="agent-status-text">에이전트가 생각하는 중...</span>
            </div>
            <button id="stop-btn" class="stop-btn">중단</button>
        </div>

        <div class="chat-input-area">
            <textarea id="chat-input" placeholder="로컬 에이전트에게 내릴 명령을 입력하세요..." rows="2"></textarea>
            <button id="send-btn">전송</button>
        </div>
    </div>

    <script nonce="${nonce}" src="${scriptMainUri}"></script>
</body>
</html>`;
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
