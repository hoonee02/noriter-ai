import * as vscode from 'vscode';
import { LocalAgent } from '../agent/localAgent';

export class SidebarProvider implements vscode.WebviewViewProvider {
    public static readonly viewType = 'noriter-ai.chatView';
    private _view?: vscode.WebviewView;
    private _agent: LocalAgent;
    private _cancellationTokenSource?: vscode.CancellationTokenSource;

    constructor(private readonly _extensionUri: vscode.Uri) {
        this._agent = new LocalAgent();
    }

    public resolveWebviewView(
        webviewView: vscode.WebviewView,
        context: vscode.WebviewViewResolveContext,
        _token: vscode.CancellationToken
    ) {
        this._view = webviewView;

        webviewView.webview.options = {
            enableScripts: true,
            localResourceRoots: [
                this._extensionUri
            ]
        };

        webviewView.webview.html = this._getHtmlForWebview(webviewView.webview);

        webviewView.webview.onDidReceiveMessage(async (data) => {
            switch (data.type) {
                case 'sendMessage': {
                    this.startAgentSession(data.value);
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

        if (this._cancellationTokenSource) {
            this._cancellationTokenSource.cancel();
            this._cancellationTokenSource.dispose();
        }

        this._cancellationTokenSource = new vscode.CancellationTokenSource();
        const token = this._cancellationTokenSource.token;

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
                        this._view?.webview.postMessage({ type: 'finalAnswer', value: text });
                        this._cancellationTokenSource?.dispose();
                        this._cancellationTokenSource = undefined;
                    },
                    onError: (err) => {
                        this._view?.webview.postMessage({ type: 'error', value: err });
                        this._cancellationTokenSource?.dispose();
                        this._cancellationTokenSource = undefined;
                    }
                },
                token
            );
        } catch (e: any) {
            this._view?.webview.postMessage({ type: 'error', value: e.message });
            this._cancellationTokenSource?.dispose();
            this._cancellationTokenSource = undefined;
        }
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
        </header>

        <div id="chat-messages" class="chat-messages">
            <div class="system-message">
                안녕하세요! 로컬 AI 에이전트 Noriter AI입니다. LM Studio 서버를 켜두시면 워크스페이스 내 파일 읽기/쓰기 및 터미널 명령어 실행을 통해 개발을 자동화할 수 있습니다.
            </div>
        </div>

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
