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
            <button id="clear-history-btn" class="clear-btn" title="Clear History">Clear</button>
        </header>

        <!-- Engine Panel -->
        <div id="engine-panel" style="display:none; padding:10px 14px; background:rgba(0,0,0,0.2); border-bottom:1px solid var(--vscode-panel-border); font-size:12px; max-height:300px; overflow-y:auto;">
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                <strong>&#9881;&#65039; LLM Engine Manager</strong>
                <button id="engine-panel-close" style="background:transparent;border:none;color:var(--vscode-descriptionForeground);cursor:pointer;font-size:14px;">&#10005;</button>
            </div>
            <div id="engine-status-text" style="margin-bottom:8px; color:var(--vscode-descriptionForeground);">Loading status...</div>
            <div id="engine-actions" style="display:flex; gap:6px; flex-wrap:wrap; margin-bottom:10px;"></div>
            <div id="local-models-section" style="margin-bottom:10px;">
                <div style="font-weight:600; margin-bottom:4px;">Local Models</div>
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

        <div class="chat-input-area">
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
    const engineActions = document.getElementById('engine-actions');
    const localModelsList = document.getElementById('local-models-list');
    const recommendedModelsList = document.getElementById('recommended-models-list');

    let currentLogBlock = null;
    let ws = null;
    let reconnectTimer = null;
    let engineReady = false;  // tracks whether embedded engine is running
    let engineMode = 'embedded';

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
                    var isReady = message.state && message.state.status === 'ready';
                    setEngineReady(isReady);
                    // Update engine panel UI
                    if (engineStatusText) {
                        var statusMsg = message.state ? (message.state.statusMessage || message.state.status) : 'Unknown';
                        engineStatusText.textContent = statusMsg;
                    }
                    updateEngineActions(message);
                    updateLocalModels(message.localModels || []);
                    updateRecommendedModels(message.recommendedModels || []);
                    break;
                case 'localModelsList':
                    updateLocalModels(message.models || []);
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

    function sendMessage() {
        var text = chatInput.value.trim();
        if (text && ws && ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({ type: 'sendMessage', value: text }));
            chatInput.value = '';
        }
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

    function addMessage(text, sender) {
        var msgDiv = document.createElement('div');
        msgDiv.className = 'message ' + sender;
        msgDiv.textContent = text;
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
                addMessage(entry.text, 'user');
                return;
            }

            if (entry.type === 'assistant') {
                addMessage(entry.text, 'assistant');
                return;
            }

            if (entry.type === 'error') {
                var errDiv = document.createElement('div');
                errDiv.className = 'error-message';
                errDiv.textContent = '\u26A0\uFE0F Error: ' + entry.text;
                chatMessages.appendChild(errDiv);
            }
        });

        scrollToBottom();
    }

    function createLogBlock(title, initialContent) {
        var block = document.createElement('div');
        block.className = 'log-block collapsed';

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

    function updateEngineActions(msg) {
        if (!engineActions) return;
        engineActions.innerHTML = '';
        var isInstalled = msg.isInstalled;
        var status = msg.state ? msg.state.status : 'idle';
        var models = msg.localModels || [];
        var isBusy = status === 'starting' || status === 'downloadingEngine' || status === 'downloadingModel';

        if (!isInstalled) {
            var btn = document.createElement('button');
            btn.className = 'action-btn';
            btn.textContent = '\u2B07\uFE0F Download Engine';
            btn.disabled = isBusy;
            btn.addEventListener('click', function () {
                ws.send(JSON.stringify({ type: 'downloadEngine' }));
            });
            engineActions.appendChild(btn);
        } else if (status === 'ready') {
            var stopBtn = document.createElement('button');
            stopBtn.className = 'action-btn danger-btn';
            stopBtn.textContent = '\u23F9\uFE0F Stop Engine';
            stopBtn.addEventListener('click', function () {
                ws.send(JSON.stringify({ type: 'stopEngine' }));
            });
            engineActions.appendChild(stopBtn);
        } else if (models.length > 0) {
            var runBtn = document.createElement('button');
            runBtn.className = 'action-btn run-btn';
            runBtn.textContent = '\u25B6\uFE0F Run: ' + models[0].split('/').pop().split('\\').pop();
            runBtn.disabled = isBusy;
            runBtn.addEventListener('click', function () {
                ws.send(JSON.stringify({ type: 'startEngine', modelPath: models[0] }));
            });
            engineActions.appendChild(runBtn);
        }
    }

    function updateLocalModels(models) {
        if (!localModelsList) return;
        if (!models || models.length === 0) {
            localModelsList.textContent = '(none)';
            return;
        }
        localModelsList.innerHTML = '';
        models.forEach(function (m) {
            var div = document.createElement('div');
            var name = m.split('/').pop().split('\\').pop();
            div.style.cssText = 'display:flex; justify-content:space-between; align-items:center; padding:3px 0;';
            div.innerHTML = '<span style="font-size:11px; color:var(--vscode-sideBar-foreground);">' + name + '</span>';
            var runBtn = document.createElement('button');
            runBtn.className = 'action-btn';
            runBtn.style.cssText = 'padding:2px 8px; font-size:11px;';
            runBtn.textContent = 'Run';
            runBtn.addEventListener('click', function () {
                ws.send(JSON.stringify({ type: 'startEngine', modelPath: m }));
                enginePanel.style.display = 'none';
            });
            div.appendChild(runBtn);
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
