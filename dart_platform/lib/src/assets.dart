// Embedded static assets for standalone EXE deployment.
// HTML/CSS/JS are inlined here so dart compile exe produces a single binary.

const String kChatHtml = r'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link href="/main.css" rel="stylesheet">
    <title>Noriter AI Chat</title>
    <style>
        :root {
            --vscode-sideBar-background: #1e1e2e;
            --vscode-sideBar-foreground: #cdd6f4;
            --vscode-panel-border: rgba(255,255,255,0.1);
            --vscode-button-background: #89b4fa;
            --vscode-button-foreground: #1e1e2e;
            --vscode-button-hoverBackground: #74c7ec;
            --vscode-input-background: #313244;
            --vscode-input-foreground: #cdd6f4;
            --vscode-input-border: rgba(255,255,255,0.2);
            --vscode-editor-background: #181825;
            --vscode-focusBorder: #89b4fa;
            --vscode-descriptionForeground: #a6adc8;
            --vscode-textPreformat-foreground: #f9e2af;
            --vscode-textCodeBlock-background: rgba(0,0,0,0.3);
            --vscode-progressBar-background: #89b4fa;
            --vscode-font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            --vscode-font-size: 13px;
        }
    </style>
</head>
<body>
    <div class="chat-container">
        <header class="chat-header">
            <h3>Noriter AI Agent</h3>
            <span class="status-indicator">Local Engine</span>
            <button id="open-goal-btn" class="goal-btn" title="Open Goal File">Goal</button>
            <button id="open-memory-btn" class="memory-btn" title="Open Memory File">Memory</button>
            <button id="engine-btn" class="engine-btn" title="LLM Engine Manager">Engine</button>
            <button id="telegram-btn" class="engine-btn" title="Telegram Bot Bridge">Telegram</button>
            <button id="clear-history-btn" class="clear-btn" title="Clear History">Clear</button>
        </header>

        <!-- Telegram Panel -->
        <div id="telegram-panel" style="display:none; padding:10px 14px; background:rgba(0,0,0,0.2); border-bottom:1px solid var(--vscode-panel-border); font-size:12px;">
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                <strong>&#128172; Telegram Bot Bridge</strong>
                <button id="telegram-panel-close" style="background:transparent;border:none;color:var(--vscode-descriptionForeground);cursor:pointer;font-size:14px;">&#10005;</button>
            </div>
            <div id="telegram-status-text" style="margin-bottom:8px; color:var(--vscode-descriptionForeground);">Loading status...</div>
            <div style="margin-bottom:6px;">
                <label for="telegram-bot-token" style="display:block; margin-bottom:2px; font-weight:600;">Bot Token</label>
                <input type="password" id="telegram-bot-token" placeholder="From @BotFather" style="width:100%; box-sizing:border-box; padding:4px 6px; background:var(--vscode-input-background); color:var(--vscode-input-foreground); border:1px solid var(--vscode-input-border); border-radius:3px;">
            </div>
            <div style="margin-bottom:6px;">
                <label for="telegram-chat-id" style="display:block; margin-bottom:2px; font-weight:600;">Chat ID</label>
                <input type="text" id="telegram-chat-id" placeholder="e.g. 123456789" style="width:100%; box-sizing:border-box; padding:4px 6px; background:var(--vscode-input-background); color:var(--vscode-input-foreground); border:1px solid var(--vscode-input-border); border-radius:3px;">
            </div>
            <div style="display:flex; align-items:center; gap:6px; margin-bottom:10px;">
                <input type="checkbox" id="telegram-enabled">
                <label for="telegram-enabled">Enable Telegram bridge</label>
            </div>
            <button id="telegram-save-btn" class="action-btn">Save &amp; Apply</button>
            <div style="color:var(--vscode-descriptionForeground); font-size:10px; margin-top:8px;">Create a bot with @BotFather, message it once, then get your chat ID from @userinfobot. The token is stored locally in .noriter-ai/telegram-config.json and never shown back in full.</div>
        </div>

        <!-- Engine Panel -->
        <div id="engine-panel" style="display:none; padding:10px 14px; background:rgba(0,0,0,0.2); border-bottom:1px solid var(--vscode-panel-border); font-size:12px; max-height:300px; overflow-y:auto;">
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                <strong>&#9881;&#65039; LLM Engine Manager</strong>
                <button id="engine-panel-close" style="background:transparent;border:none;color:var(--vscode-descriptionForeground);cursor:pointer;font-size:14px;">&#10005;</button>
            </div>
            <div id="engine-status-text" class="engine-status-line">Loading status...</div>
            <div id="engine-backend-text" class="engine-backend-line">&#9881;&#65039; Engine: —</div>
            <div id="engine-model-row" class="engine-model-row">
                <select id="engine-model-select" class="engine-model-select" disabled>
                    <option value="">(no local models yet)</option>
                </select>
                <button id="engine-run-btn" class="action-btn run-btn" disabled>&#9654;&#65039; Run</button>
            </div>
            <div style="margin-bottom:10px;">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:2px;">
                    <label for="context-size-slider" style="font-weight:600;">Context Size</label>
                    <span id="context-size-value" style="color:var(--vscode-descriptionForeground);">4096 tokens</span>
                </div>
                <input type="range" id="context-size-slider" min="512" max="32768" step="512" value="4096" style="width:100%;">
                <div style="color:var(--vscode-descriptionForeground); font-size:10px; margin-top:2px;">Applied the next time you start the engine. Larger values use more RAM.</div>
            </div>
            <div id="local-models-section" style="margin-bottom:10px;">
                <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:4px;">
                    <span style="font-weight:600;">Local Models</span>
                    <button id="open-models-folder-btn" class="action-btn" style="padding:2px 8px; font-size:11px;" title="Open the models folder in File Explorer">&#128193; 폴더에서 보기</button>
                </div>
                <div id="engine-models-dir-text" style="color:var(--vscode-descriptionForeground); font-size:10px; margin-bottom:4px; word-break:break-all;"></div>
                <div id="local-models-list" style="color:var(--vscode-descriptionForeground);">(none)</div>
            </div>
            <div id="recommended-section">
                <div style="font-weight:600; margin-bottom:4px;">Download Recommended Models</div>
                <div id="recommended-models-list"></div>
            </div>
        </div>

        <div id="chat-messages" class="chat-messages"></div>

        <div class="agent-activity-container" id="agent-activity" style="display: none;">
            <div class="spinner-container">
                <div class="spinner"></div>
                <span id="agent-status-text">Agent is thinking...</span>
            </div>
            <button id="stop-btn" class="stop-btn">Stop</button>
        </div>

        <div id="attachment-chip" style="display:none; align-items:center; gap:6px; padding:4px 14px; font-size:11px; color:var(--vscode-descriptionForeground);">
            <span>&#128206;</span>
            <span id="attachment-chip-name"></span>
            <button id="attachment-remove-btn" style="background:transparent; border:none; color:var(--vscode-descriptionForeground); cursor:pointer;">&#10005;</button>
        </div>
        <div class="chat-input-area">
            <input type="file" id="file-input" style="display:none;" accept=".txt,.md,.markdown,.json,.csv,.log,.js,.ts,.dart,.py,.java,.c,.cpp,.h,.html,.css,.yaml,.yml,.xml,.ini,.env">
            <button id="attach-btn" title="Attach a local file">&#128206;</button>
            <textarea id="chat-input" placeholder="Send a message to the local AI agent..." rows="2"></textarea>
            <button id="send-btn">Send</button>
        </div>
    </div>

    <script src="/main.js"></script>
</body>
</html>''';

const String kMainCss = r''':root {
    --border-radius: 6px;
    --font-family: var(--vscode-font-family, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif);
}

body {
    padding: 0;
    margin: 0;
    background-color: var(--vscode-sideBar-background);
    color: var(--vscode-sideBar-foreground, #cccccc);
    font-family: var(--font-family);
    font-size: var(--vscode-font-size, 13px);
    height: 100vh;
    overflow: hidden;
}

.chat-container {
    display: flex;
    flex-direction: column;
    height: 100vh;
    box-sizing: border-box;
}

.chat-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 10px 14px;
    background: rgba(0, 0, 0, 0.1);
    border-bottom: 1px solid var(--vscode-panel-border, rgba(255, 255, 255, 0.1));
}

.chat-header h3 {
    margin: 0;
    font-weight: 600;
}

.goal-btn {
    margin-left: auto;
    margin-right: 8px;
    background: transparent;
    color: var(--vscode-descriptionForeground);
    border: 1px solid var(--vscode-panel-border, rgba(255, 255, 255, 0.15));
    border-radius: var(--border-radius);
    padding: 2px 8px;
    font-size: 11px;
    cursor: pointer;
}

.goal-btn:hover {
    color: var(--vscode-foreground);
    border-color: var(--vscode-focusBorder);
}

.memory-btn {
    margin-right: 8px;
    background: transparent;
    color: var(--vscode-descriptionForeground);
    border: 1px solid var(--vscode-panel-border, rgba(255, 255, 255, 0.15));
    border-radius: var(--border-radius);
    padding: 2px 8px;
    font-size: 11px;
    cursor: pointer;
}

.memory-btn:hover {
    color: var(--vscode-foreground);
    border-color: var(--vscode-focusBorder);
}

.engine-btn {
    margin-right: 8px;
    background: transparent;
    color: #89b4fa;
    border: 1px solid rgba(137, 180, 250, 0.4);
    border-radius: var(--border-radius);
    padding: 2px 8px;
    font-size: 11px;
    cursor: pointer;
}

.engine-btn:hover {
    color: #cdd6f4;
    border-color: #89b4fa;
    background: rgba(137, 180, 250, 0.1);
}

.clear-btn {
    margin-right: 8px;
    background: transparent;
    color: var(--vscode-descriptionForeground);
    border: 1px solid var(--vscode-panel-border, rgba(255, 255, 255, 0.15));
    border-radius: var(--border-radius);
    padding: 2px 8px;
    font-size: 11px;
    cursor: pointer;
}

.clear-btn:hover {
    color: var(--vscode-foreground);
    border-color: var(--vscode-focusBorder);
}

.status-indicator {
    font-size: 10px;
    background: rgba(0, 255, 100, 0.15);
    color: #00ff66;
    padding: 2px 6px;
    border-radius: 10px;
    border: 1px solid rgba(0, 255, 100, 0.3);
}

.chat-messages {
    flex: 1;
    overflow-y: auto;
    padding: 12px;
    display: flex;
    flex-direction: column;
    gap: 12px;
}

.system-message {
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(255, 255, 255, 0.05);
    padding: 10px;
    border-radius: var(--border-radius);
    line-height: 1.4;
    color: var(--vscode-descriptionForeground);
}

.message {
    display: flex;
    flex-direction: column;
    max-width: 90%;
    padding: 8px 12px;
    border-radius: var(--border-radius);
    line-height: 1.4;
}

.message.user {
    align-self: flex-end;
    background-color: var(--vscode-button-background);
    color: var(--vscode-button-foreground);
}

.message.assistant {
    align-self: flex-start;
    background-color: var(--vscode-editor-background);
    border: 1px solid var(--vscode-panel-border, rgba(255, 255, 255, 0.1));
}

.message-text {
    white-space: pre-wrap;
}

.message-time {
    align-self: flex-end;
    font-size: 10px;
    opacity: 0.6;
    margin-top: 3px;
}

.message.assistant .message-time {
    align-self: flex-start;
}

.log-block {
    background: rgba(255, 255, 255, 0.02);
    border: 1px solid rgba(255, 255, 255, 0.05);
    border-radius: var(--border-radius);
    margin: 4px 0;
    overflow: hidden;
}

.log-header {
    background: rgba(255, 255, 255, 0.03);
    padding: 6px 10px;
    cursor: pointer;
    font-weight: 500;
    display: flex;
    justify-content: space-between;
    align-items: center;
    user-select: none;
    color: var(--vscode-textPreformat-foreground, #e5c07b);
}

.log-header::after {
    content: "??;
    font-size: 8px;
    transition: transform 0.2s;
}

.log-block.collapsed .log-header::after {
    content: "??;
}

.log-content {
    padding: 10px;
    border-top: 1px solid rgba(255, 255, 255, 0.03);
    font-family: var(--vscode-editor-font-family, monospace);
    font-size: 11px;
    white-space: pre-wrap;
    overflow-x: auto;
    background-color: var(--vscode-textCodeBlock-background, rgba(0, 0, 0, 0.2));
}

.log-block.collapsed .log-content {
    display: none;
}

.agent-activity-container {
    padding: 10px 12px;
    background: rgba(0, 0, 0, 0.2);
    border-top: 1px solid var(--vscode-panel-border, rgba(255, 255, 255, 0.1));
    display: flex;
    justify-content: space-between;
    align-items: center;
}

.spinner-container {
    display: flex;
    align-items: center;
    gap: 8px;
}

.spinner {
    width: 14px;
    height: 14px;
    border: 2px solid rgba(255, 255, 255, 0.1);
    border-top: 2px solid var(--vscode-progressBar-background, #007acc);
    border-radius: 50%;
    animation: spin 1s linear infinite;
}

@keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
}

.stop-btn {
    background: #c7254e;
    color: white;
    border: none;
    padding: 4px 10px;
    border-radius: var(--border-radius);
    cursor: pointer;
    font-size: 11px;
}

.stop-btn:hover {
    background: #b11b3e;
}

.chat-input-area {
    display: flex;
    padding: 10px;
    gap: 8px;
    border-top: 1px solid var(--vscode-panel-border, rgba(255, 255, 255, 0.1));
}

.chat-input-area textarea {
    flex: 1;
    background-color: var(--vscode-input-background);
    color: var(--vscode-input-foreground);
    border: 1px solid var(--vscode-input-border, rgba(255, 255, 255, 0.15));
    border-radius: var(--border-radius);
    padding: 6px;
    resize: none;
    font-family: inherit;
    font-size: inherit;
}

.chat-input-area textarea:focus {
    outline: 1px solid var(--vscode-focusBorder);
}

.chat-input-area button {
    background-color: var(--vscode-button-background);
    color: var(--vscode-button-foreground);
    border: none;
    padding: 0 16px;
    border-radius: var(--border-radius);
    cursor: pointer;
    font-weight: 500;
}

.chat-input-area button:hover {
    background-color: var(--vscode-button-hoverBackground);
}

.error-message {
    color: #ff5555;
    background: rgba(255, 85, 85, 0.1);
    border: 1px solid rgba(255, 85, 85, 0.2);
    padding: 8px;
    border-radius: var(--border-radius);
    margin: 4px 0;
}

.action-btn {
    background: var(--vscode-button-background);
    color: var(--vscode-button-foreground);
    border: none;
    padding: 4px 12px;
    border-radius: var(--border-radius);
    cursor: pointer;
    font-size: 12px;
    font-weight: 500;
}

.action-btn:hover {
    background: var(--vscode-button-hoverBackground);
}

.action-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
}

.run-btn {
    background: #40a02b;
}

.run-btn:hover {
    background: #2d8020;
}

.engine-status-line {
    margin-bottom: 8px;
    color: var(--vscode-descriptionForeground);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}

.engine-backend-line {
    margin-bottom: 8px;
    color: var(--vscode-descriptionForeground);
    font-size: 11px;
}

.engine-model-row {
    display: flex;
    gap: 6px;
    margin-bottom: 10px;
}

.engine-model-select {
    flex: 1;
    min-width: 0;
    padding: 4px 6px;
    background-color: var(--vscode-input-background);
    color: var(--vscode-input-foreground);
    border: 1px solid var(--vscode-input-border, rgba(255, 255, 255, 0.2));
    border-radius: var(--border-radius);
    font-family: inherit;
    font-size: inherit;
}

.engine-model-row .action-btn {
    flex: none;
    white-space: nowrap;
}

.danger-btn {
    background: rgba(255, 85, 85, 0.3);
    color: #ff5555;
    border: 1px solid rgba(255, 85, 85, 0.4);
}

.danger-btn:hover {
    background: rgba(255, 85, 85, 0.5);
}''';

const String kMainJs = r'''(function () {
    const chatMessages = document.getElementById('chat-messages');
    const chatInput = document.getElementById('chat-input');
    const sendButton = document.getElementById('send-btn');
    const stopButton = document.getElementById('stop-btn');
    const openGoalButton = document.getElementById('open-goal-btn');
    const openMemoryButton = document.getElementById('open-memory-btn');
    const clearHistoryButton = document.getElementById('clear-history-btn');
    const agentActivity = document.getElementById('agent-activity');
    const agentStatusText = document.getElementById('agent-status-text');
    const engineBtn = document.getElementById('engine-btn');
    const enginePanel = document.getElementById('engine-panel');
    const enginePanelClose = document.getElementById('engine-panel-close');
    const engineStatusText = document.getElementById('engine-status-text');
    const engineBackendText = document.getElementById('engine-backend-text');
    const engineModelsDirText = document.getElementById('engine-models-dir-text');
    const openModelsFolderBtn = document.getElementById('open-models-folder-btn');
    const engineModelSelect = document.getElementById('engine-model-select');
    const engineRunBtn = document.getElementById('engine-run-btn');
    const localModelsList = document.getElementById('local-models-list');
    const recommendedModelsList = document.getElementById('recommended-models-list');
    const contextSizeSlider = document.getElementById('context-size-slider');
    const contextSizeValue = document.getElementById('context-size-value');
    const telegramBtn = document.getElementById('telegram-btn');
    const telegramPanel = document.getElementById('telegram-panel');
    const telegramPanelClose = document.getElementById('telegram-panel-close');
    const telegramStatusText = document.getElementById('telegram-status-text');
    const telegramBotToken = document.getElementById('telegram-bot-token');
    const telegramChatId = document.getElementById('telegram-chat-id');
    const telegramEnabled = document.getElementById('telegram-enabled');
    const telegramSaveBtn = document.getElementById('telegram-save-btn');
    const attachBtn = document.getElementById('attach-btn');
    const fileInput = document.getElementById('file-input');
    const attachmentChip = document.getElementById('attachment-chip');
    const attachmentChipName = document.getElementById('attachment-chip-name');
    const attachmentRemoveBtn = document.getElementById('attachment-remove-btn');
    let pendingAttachment = null;
    const MAX_ATTACHMENT_BYTES = 500 * 1024;

    let currentLogBlock = null;
    let ws = null;
    let reconnectTimer = null;
    let engineReady = false;  // tracks whether embedded engine is running
    let engineInstalled = false;
    let engineMode = 'embedded';

    if (contextSizeSlider && contextSizeValue) {
        contextSizeSlider.addEventListener('input', function () {
            contextSizeValue.textContent = contextSizeSlider.value + ' tokens';
        });
    }

    function getSelectedContextSize() {
        return contextSizeSlider ? parseInt(contextSizeSlider.value, 10) : 4096;
    }

    // Banner shown when engine is not ready
    var engineBanner = document.createElement('div');
    engineBanner.id = 'engine-banner';
    engineBanner.style.cssText = 'display:none; background:rgba(255,165,0,0.15); border:1px solid rgba(255,165,0,0.4); color:#ffcc80; padding:8px 14px; font-size:12px; text-align:center; cursor:pointer;';
    engineBanner.innerHTML = '\u26A0\uFE0F Engine not started &mdash; click <strong>[Engine]</strong> to set up a local model.';
    engineBanner.addEventListener('click', function () {
        enginePanel.style.display = enginePanel.style.display === 'none' ? 'block' : 'none';
    });
    document.querySelector('.chat-container').insertBefore(engineBanner, document.getElementById('chat-messages'));

    function setEngineReady(ready) {
        engineReady = ready;
        if (engineMode === 'external') {
            engineBanner.style.display = 'none';
            chatInput.disabled = false;
            sendButton.disabled = false;
            return;
        }
        if (ready) {
            engineBanner.style.display = 'none';
            chatInput.placeholder = 'Send a message to the local AI agent...';
        } else {
            engineBanner.style.display = 'block';
            chatInput.placeholder = 'Start the engine first \u2192 click [Engine] in the header';
        }
    }

    function connect() {
        ws = new WebSocket('ws://localhost:3742/ws');

        ws.onopen = function () {
            ws.send(JSON.stringify({ type: 'webviewReady' }));
            ws.send(JSON.stringify({ type: 'getEngineStatus' }));
        };

        ws.onmessage = function (event) {
            const message = JSON.parse(event.data);
            switch (message.type) {
                case 'loadHistory':
                    renderHistory(message.entries);
                    currentLogBlock = null;
                    break;
                case 'historyCleared':
                    renderHistory([]);
                    currentLogBlock = null;
                    break;
                case 'sessionStart':
                    addMessage(message.userPrompt, 'user');
                    showActivity(true, 'Agent is thinking...');
                    currentLogBlock = null;
                    break;
                case 'thought':
                    currentLogBlock = createLogBlock('\uD83E\uDD14 Agent Thought', message.value);
                    showActivity(true, truncateForStatus(message.value));
                    break;
                case 'toolStart':
                    var argsStr = JSON.stringify(message.args, null, 2);
                    currentLogBlock = createLogBlock('\u2699\uFE0F Tool: ' + message.name, 'Arguments:\n' + argsStr + '\n\nRunning tool...');
                    currentLogBlock.expand();
                    showActivity(true, 'Running tool: ' + message.name);
                    break;
                case 'toolEnd':
                    if (currentLogBlock) {
                        currentLogBlock.setContent(currentLogBlock.contentElement.textContent.replace('Running tool...', '') + 'Output:\n' + message.output);
                    } else {
                        createLogBlock('\u2699\uFE0F Tool done: ' + message.name, 'Output:\n' + message.output);
                    }
                    showActivity(true, 'Agent is summarizing results...');
                    break;
                case 'finalAnswer':
                    addMessage(message.value, 'assistant');
                    showActivity(false);
                    currentLogBlock = null;
                    break;
                case 'engineStatus':
                    engineMode = message.state && message.state.mode ? message.state.mode : 'embedded';
                    engineInstalled = !!message.isInstalled;
                    var isReady = message.state && message.state.status === 'ready';
                    setEngineReady(isReady);
                    // Update engine panel UI
                    if (engineStatusText) {
                        var statusMsg = message.state ? (message.state.statusMessage || message.state.status) : 'Unknown';
                        engineStatusText.textContent = statusMsg;
                    }
                    if (engineBackendText && message.engineBackend) {
                        engineBackendText.textContent = '⚙️ Engine: ' + message.engineBackend;
                    }
                    if (engineModelsDirText && message.modelsDir) {
                        engineModelsDirText.textContent = 'Models folder: ' + message.modelsDir;
                    }
                    updateEngineModelRow(message);
                    updateLocalModels(message.localModels || []);
                    updateRecommendedModels(message.recommendedModels || []);
                    if (contextSizeSlider && contextSizeValue && message.state && message.state.contextSize) {
                        contextSizeSlider.value = message.state.contextSize;
                        contextSizeValue.textContent = message.state.contextSize + ' tokens';
                    }
                    break;
                case 'localModelsList':
                    updateLocalModels(message.models || []);
                    break;
                case 'telegramStatus':
                    updateTelegramPanel(message);
                    break;
                case 'lastEngineFound':
                    var modelLabel = message.modelPath.split('/').pop().split('\\').pop();
                    var confirmed = window.confirm(
                        'Automatically start the last used engine?\n\n' +
                        'Model: ' + modelLabel + '\n' +
                        'Context size: ' + message.contextSize + ' tokens'
                    );
                    if (confirmed && ws && ws.readyState === WebSocket.OPEN) {
                        ws.send(JSON.stringify({ type: 'startEngine', modelPath: message.modelPath, contextSize: message.contextSize }));
                        if (contextSizeSlider && contextSizeValue) {
                            contextSizeSlider.value = message.contextSize;
                            contextSizeValue.textContent = message.contextSize + ' tokens';
                        }
                    }
                    break;
                case 'engineNotReady':
                    var bannerDiv = document.createElement('div');
                    bannerDiv.className = 'error-message';
                    bannerDiv.style.cssText = 'background:rgba(255,165,0,0.1); border-color:rgba(255,165,0,0.4); color:#ffcc80;';
                    bannerDiv.textContent = '\u26A0\uFE0F ' + message.value;
                    chatMessages.appendChild(bannerDiv);
                    scrollToBottom();
                    // Auto-open engine panel
                    enginePanel.style.display = 'block';
                    if (ws && ws.readyState === WebSocket.OPEN) {
                        ws.send(JSON.stringify({ type: 'getEngineStatus' }));
                    }
                    break;
                case 'error':
                    var errDiv = document.createElement('div');
                    errDiv.className = 'error-message';
                    errDiv.textContent = '\u26A0\uFE0F Error: ' + message.value;
                    chatMessages.appendChild(errDiv);
                    showActivity(false);
                    currentLogBlock = null;
                    scrollToBottom();
                    break;
            }
        };

        ws.onclose = function () {
            if (!reconnectTimer) {
                reconnectTimer = setTimeout(function () {
                    reconnectTimer = null;
                    connect();
                }, 2000);
            }
        };

        ws.onerror = function () {
            ws.close();
        };
    }

    connect();

    engineBtn.addEventListener('click', function () {
        enginePanel.style.display = enginePanel.style.display === 'none' ? 'block' : 'none';
        if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({ type: 'getEngineStatus' }));
        }
    });

    enginePanelClose.addEventListener('click', function () {
        enginePanel.style.display = 'none';
    });

    if (openModelsFolderBtn) {
        openModelsFolderBtn.addEventListener('click', function () {
            if (ws && ws.readyState === WebSocket.OPEN) {
                ws.send(JSON.stringify({ type: 'openModelsFolder' }));
            }
        });
    }

    telegramBtn.addEventListener('click', function () {
        telegramPanel.style.display = telegramPanel.style.display === 'none' ? 'block' : 'none';
        if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({ type: 'getTelegramStatus' }));
        }
    });

    telegramPanelClose.addEventListener('click', function () {
        telegramPanel.style.display = 'none';
    });

    telegramSaveBtn.addEventListener('click', function () {
        if (!ws || ws.readyState !== WebSocket.OPEN) return;
        var payload = {
            type: 'updateTelegramConfig',
            chatId: telegramChatId.value.trim(),
            enabled: telegramEnabled.checked
        };
        var tokenInput = telegramBotToken.value.trim();
        if (tokenInput) {
            payload.botToken = tokenInput;
        }
        ws.send(JSON.stringify(payload));
        telegramBotToken.value = '';
    });

    sendButton.addEventListener('click', function () {
        sendMessage();
    });

    chatInput.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            sendMessage();
        }
    });

    stopButton.addEventListener('click', function () {
        if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({ type: 'stopAgent' }));
        }
        showActivity(false);
    });

    clearHistoryButton.addEventListener('click', function () {
        if (ws && ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({ type: 'clearHistory' }));
        }
    });

    openMemoryButton.addEventListener('click', function () {
        alert('Edit memory file directly: .noriter-ai/agent-memory.md');
    });

    openGoalButton.addEventListener('click', function () {
        alert('Edit goal file directly: .noriter-ai/agent-goal.md');
    });

    attachBtn.addEventListener('click', function () {
        fileInput.click();
    });

    fileInput.addEventListener('change', function () {
        var file = fileInput.files && fileInput.files[0];
        fileInput.value = '';
        if (!file) return;
        if (file.size > MAX_ATTACHMENT_BYTES) {
            alert('File too large (' + (file.size / 1024).toFixed(0) + ' KB). Max ' + (MAX_ATTACHMENT_BYTES / 1024) + ' KB for attachments.');
            return;
        }
        var reader = new FileReader();
        reader.onload = function () {
            pendingAttachment = { name: file.name, content: String(reader.result) };
            attachmentChipName.textContent = file.name + ' (' + (file.size / 1024).toFixed(1) + ' KB)';
            attachmentChip.style.display = 'flex';
        };
        reader.onerror = function () {
            alert('Failed to read file: ' + file.name);
        };
        reader.readAsText(file);
    });

    attachmentRemoveBtn.addEventListener('click', function () {
        clearAttachment();
    });

    function clearAttachment() {
        pendingAttachment = null;
        attachmentChip.style.display = 'none';
        attachmentChipName.textContent = '';
    }

    function sendMessage() {
        var text = chatInput.value.trim();
        if ((text || pendingAttachment) && ws && ws.readyState === WebSocket.OPEN) {
            var payload = { type: 'sendMessage', value: text };
            if (pendingAttachment) {
                payload.attachment = pendingAttachment;
            }
            ws.send(JSON.stringify(payload));
            chatInput.value = '';
            clearAttachment();
        }
    }

    function truncateForStatus(text, maxLength) {
        maxLength = maxLength || 80;
        if (!text) return 'Thinking...';
        var oneLine = String(text).replace(/\s+/g, ' ').trim();
        return oneLine.length > maxLength ? oneLine.slice(0, maxLength) + '…' : oneLine;
    }

    function showActivity(show, text) {
        if (show) {
            agentActivity.style.display = 'flex';
            agentStatusText.textContent = text || 'Thinking...';
            sendButton.disabled = true;
            chatInput.disabled = true;
        } else {
            agentActivity.style.display = 'none';
            sendButton.disabled = false;
            chatInput.disabled = false;
        }
    }

    function formatMessageTime(timestamp) {
        var date = timestamp ? new Date(timestamp) : new Date();
        var hh = String(date.getHours()).padStart(2, '0');
        var mm = String(date.getMinutes()).padStart(2, '0');
        return hh + ':' + mm;
    }

    function addMessage(text, sender, timestamp) {
        var msgDiv = document.createElement('div');
        msgDiv.className = 'message ' + sender;

        var textDiv = document.createElement('div');
        textDiv.className = 'message-text';
        textDiv.textContent = text;
        msgDiv.appendChild(textDiv);

        var timeDiv = document.createElement('div');
        timeDiv.className = 'message-time';
        timeDiv.textContent = formatMessageTime(timestamp);
        msgDiv.appendChild(timeDiv);

        chatMessages.appendChild(msgDiv);
        scrollToBottom();
    }

    function showSystemMessage() {
        var systemDiv = document.createElement('div');
        systemDiv.className = 'system-message';
        systemDiv.textContent = 'Welcome to Noriter AI Agent! Type a message to start chatting. Use /models to list available models, or click [Engine] to manage local LLM.';
        chatMessages.appendChild(systemDiv);
    }

    function renderHistory(entries) {
        chatMessages.innerHTML = '';

        if (!Array.isArray(entries) || entries.length === 0) {
            showSystemMessage();
            scrollToBottom();
            return;
        }

        entries.forEach(function (entry) {
            if (!entry || typeof entry.text !== 'string') {
                return;
            }

            if (entry.type === 'user') {
                addMessage(entry.text, 'user', entry.timestamp);
                return;
            }

            if (entry.type === 'assistant') {
                addMessage(entry.text, 'assistant', entry.timestamp);
                return;
            }

            if (entry.type === 'error') {
                var errDiv = document.createElement('div');
                errDiv.className = 'error-message';
                errDiv.textContent = '\u26A0\uFE0F Error: ' + entry.text + ' (' + formatMessageTime(entry.timestamp) + ')';
                chatMessages.appendChild(errDiv);
            }
        });

        scrollToBottom();
    }

    function createLogBlock(title, initialContent) {
        var block = document.createElement('div');
        block.className = 'log-block';

        var header = document.createElement('div');
        header.className = 'log-header';
        header.textContent = title;

        var content = document.createElement('div');
        content.className = 'log-content';
        content.textContent = initialContent || '';

        header.addEventListener('click', function () {
            block.classList.toggle('collapsed');
        });

        block.appendChild(header);
        block.appendChild(content);
        chatMessages.appendChild(block);
        scrollToBottom();

        return {
            element: block,
            contentElement: content,
            setContent: function (text) {
                content.textContent = text;
            },
            expand: function () {
                block.classList.remove('collapsed');
            }
        };
    }

    // Rebuilds the single "model select + Run" row from the latest engine
    // status: the button's label/action changes with state (Download / Run /
    // Stop), and the select lists local models when one can be picked.
    function updateEngineModelRow(msg) {
        if (!engineModelSelect || !engineRunBtn) return;
        var isInstalled = !!msg.isInstalled;
        var status = msg.state ? msg.state.status : 'idle';
        var models = msg.localModels || [];
        var activeModelPath = msg.activeModelPath || (msg.state && msg.state.activeModelPath) || '';
        var isBusy = status === 'starting' || status === 'downloadingEngine' || status === 'downloadingModel';

        function modelLabel(path) {
            return path.split('/').pop().split('\\').pop();
        }

        var previousSelection = engineModelSelect.value;
        engineModelSelect.innerHTML = '';

        if (!isInstalled) {
            var opt = document.createElement('option');
            opt.value = '';
            opt.textContent = 'Engine not installed yet';
            engineModelSelect.appendChild(opt);
            engineModelSelect.disabled = true;
            engineRunBtn.className = 'action-btn';
            engineRunBtn.textContent = '\u2B07\uFE0F Download Engine';
            engineRunBtn.disabled = isBusy;
            engineRunBtn.onclick = function () {
                ws.send(JSON.stringify({ type: 'downloadEngine' }));
            };
            return;
        }

        if (models.length === 0) {
            var noModelOpt = document.createElement('option');
            noModelOpt.value = '';
            noModelOpt.textContent = '(no local models yet -- download one below)';
            engineModelSelect.appendChild(noModelOpt);
            engineModelSelect.disabled = true;
        } else {
            models.forEach(function (m) {
                var modelOpt = document.createElement('option');
                modelOpt.value = m;
                modelOpt.textContent = modelLabel(m);
                engineModelSelect.appendChild(modelOpt);
            });
            engineModelSelect.disabled = status === 'ready' || isBusy;
            var preselect = activeModelPath || previousSelection;
            if (preselect && models.includes(preselect)) {
                engineModelSelect.value = preselect;
            }
        }

        if (status === 'ready') {
            engineRunBtn.className = 'action-btn danger-btn';
            engineRunBtn.textContent = '\u23F9\uFE0F Stop Engine';
            engineRunBtn.disabled = false;
            engineRunBtn.onclick = function () {
                ws.send(JSON.stringify({ type: 'stopEngine' }));
            };
        } else {
            engineRunBtn.className = 'action-btn run-btn';
            engineRunBtn.textContent = isBusy ? '\u23F3 Working...' : '\u25B6\uFE0F Run';
            engineRunBtn.disabled = isBusy || models.length === 0;
            engineRunBtn.onclick = function () {
                var selected = engineModelSelect.value;
                if (!selected) return;
                ws.send(JSON.stringify({ type: 'startEngine', modelPath: selected, contextSize: getSelectedContextSize() }));
            };
        }
    }

    function updateTelegramPanel(msg) {
        if (!telegramStatusText) return;
        var cfg = msg.config || {};
        var running = !!msg.running;
        telegramStatusText.textContent = (running ? '✅ Running — ' : '⚪ Stopped — ') + (msg.statusMessage || '');
        if (document.activeElement !== telegramChatId) {
            telegramChatId.value = cfg.chatId || '';
        }
        if (document.activeElement !== telegramBotToken) {
            telegramBotToken.placeholder = cfg.botTokenSet ? ('Saved: ' + cfg.botTokenPreview + ' (enter to replace)') : 'From @BotFather';
        }
        telegramEnabled.checked = !!cfg.enabled;
    }

    // Informational only -- picking/running a model happens via the
    // model-select + Run row above. This just lists what's on disk, with a
    // checkmark next to whichever one the select currently points at.
    function updateLocalModels(models) {
        if (!localModelsList) return;
        if (!models || models.length === 0) {
            localModelsList.textContent = '(none)';
            return;
        }
        localModelsList.innerHTML = '';
        var selected = engineModelSelect ? engineModelSelect.value : '';
        models.forEach(function (m) {
            var div = document.createElement('div');
            var name = m.split('/').pop().split('\\').pop();
            div.style.cssText = 'padding:2px 0; font-size:11px; color:var(--vscode-sideBar-foreground);';
            div.textContent = (m === selected ? '✓ ' : '') + name;
            localModelsList.appendChild(div);
        });
    }

    function updateRecommendedModels(models) {
        if (!recommendedModelsList) return;
        if (!models || models.length === 0) return;
        recommendedModelsList.innerHTML = '';
        models.forEach(function (m) {
            var div = document.createElement('div');
            div.style.cssText = 'display:flex; justify-content:space-between; align-items:center; padding:4px 0; border-top:1px solid var(--vscode-panel-border);';
            var info = document.createElement('div');
            info.innerHTML = '<span style="font-size:12px;">' + m.name + '</span><br><span style="font-size:10px; color:var(--vscode-descriptionForeground);">' + (m.sizeHint || '') + '</span>';
            var dlBtn = document.createElement('button');
            dlBtn.className = 'action-btn';
            dlBtn.style.cssText = 'padding:3px 10px; font-size:11px; white-space:nowrap;';
            dlBtn.textContent = '\u2B07 Download';
            dlBtn.addEventListener('click', function () {
                ws.send(JSON.stringify({ type: 'downloadModel', url: m.url, filename: m.filename }));
            });
            div.appendChild(info);
            div.appendChild(dlBtn);
            recommendedModelsList.appendChild(div);
        });
    }

    function scrollToBottom() {
        chatMessages.scrollTop = chatMessages.scrollHeight;
    }
}());''';
