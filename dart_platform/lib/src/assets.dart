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
            <button id="open-goal-btn" class="goal-btn" title="?먯씠?꾪듃 紐⑺몴 ?뚯씪 ?닿린">紐⑺몴</button>
            <button id="open-memory-btn" class="memory-btn" title="硫붾え由??뚯씪 ?닿린">硫붾え由?/button>
            <button id="engine-btn" class="engine-btn" title="LLM ?붿쭊 愿由?>?붿쭊</button>
            <button id="clear-history-btn" class="clear-btn" title="??λ맂 ?????젣">湲곕줉 ??젣</button>
        </header>

        <!-- Engine Panel -->
        <div id="engine-panel" style="display:none; padding:10px 14px; background:rgba(0,0,0,0.2); border-bottom:1px solid var(--vscode-panel-border); font-size:12px; max-height:300px; overflow-y:auto;">
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
                <strong>?뵩 LLM ?붿쭊 愿由?/strong>
                <button id="engine-panel-close" style="background:transparent;border:none;color:var(--vscode-descriptionForeground);cursor:pointer;font-size:14px;">??/button>
            </div>
            <div id="engine-status-text" style="margin-bottom:8px; color:var(--vscode-descriptionForeground);">?곹깭 議고쉶 以?..</div>
            <div id="engine-actions" style="display:flex; gap:6px; flex-wrap:wrap; margin-bottom:10px;"></div>
            <div id="local-models-section" style="margin-bottom:10px;">
                <div style="font-weight:600; margin-bottom:4px;">濡쒖뺄 紐⑤뜽</div>
                <div id="local-models-list" style="color:var(--vscode-descriptionForeground);">?놁쓬</div>
            </div>
            <div id="recommended-section">
                <div style="font-weight:600; margin-bottom:4px;">異붿쿇 紐⑤뜽 ?ㅼ슫濡쒕뱶</div>
                <div id="recommended-models-list"></div>
            </div>
        </div>

        <div id="chat-messages" class="chat-messages"></div>

        <div class="agent-activity-container" id="agent-activity" style="display: none;">
            <div class="spinner-container">
                <div class="spinner"></div>
                <span id="agent-status-text">?먯씠?꾪듃媛 ?앷컖?섎뒗 以?..</span>
            </div>
            <button id="stop-btn" class="stop-btn">以묐떒</button>
        </div>

        <div class="chat-input-area">
            <textarea id="chat-input" placeholder="濡쒖뺄 ?먯씠?꾪듃?먭쾶 ?대┫ 紐낅졊???낅젰?섏꽭??.." rows="2"></textarea>
            <button id="send-btn">?꾩넚</button>
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

    function connect() {
        ws = new WebSocket('ws://localhost:3742/ws');

        ws.onopen = function () {
            ws.send(JSON.stringify({ type: 'webviewReady' }));
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
                    showActivity(true, '?먯씠?꾪듃媛 ?앷컖?섎뒗 以?..');
                    currentLogBlock = null;
                    break;
                case 'thought':
                    currentLogBlock = createLogBlock('\uD83E\uDD14 ?먯씠?꾪듃 ?앷컖 (Thought)', message.value);
                    break;
                case 'toolStart':
                    var argsStr = JSON.stringify(message.args, null, 2);
                    currentLogBlock = createLogBlock('\u2699\uFE0F ?꾧뎄 ?ㅽ뻾: ' + message.name, 'Arguments:\n' + argsStr + '\n\nRunning tool...');
                    currentLogBlock.expand();
                    showActivity(true, '?꾧뎄 ?ㅽ뻾 以? ' + message.name);
                    break;
                case 'toolEnd':
                    if (currentLogBlock) {
                        currentLogBlock.setContent(currentLogBlock.contentElement.textContent.replace('Running tool...', '') + 'Output:\n' + message.output);
                    } else {
                        createLogBlock('\u2699\uFE0F ?꾧뎄 ?꾨즺: ' + message.name, 'Output:\n' + message.output);
                    }
                    showActivity(true, '?먯씠?꾪듃媛 寃곌낵 ?댁꽍 以?..');
                    break;
                case 'finalAnswer':
                    addMessage(message.value, 'assistant');
                    showActivity(false);
                    currentLogBlock = null;
                    break;
                case 'error':
                    var errDiv = document.createElement('div');
                    errDiv.className = 'error-message';
                    errDiv.textContent = '\u26A0\uFE0F ?ㅻ쪟: ' + message.value;
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
        alert('硫붾え由??뚯씪??吏곸젒 ?몄쭛?섏꽭?? .noriter-ai/agent-memory.md');
    });

    openGoalButton.addEventListener('click', function () {
        alert('紐⑺몴 ?뚯씪??吏곸젒 ?몄쭛?섏꽭?? .noriter-ai/agent-goal.md');
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
        systemDiv.textContent = '?덈뀞?섏꽭?? 濡쒖뺄 AI ?먯씠?꾪듃 Noriter AI?낅땲?? LM Studio ?쒕쾭瑜?耳쒕몢?쒕㈃ ?뚰겕?ㅽ럹?댁뒪 ???뚯씪 ?쎄린/?곌린 諛??곕???紐낅졊???ㅽ뻾???듯빐 媛쒕컻???먮룞?뷀븷 ???덉뒿?덈떎. /models 瑜??낅젰?섎㈃ ?꾩옱 ?붿쭊?먯꽌 ?ъ슜 媛?ν븳 紐⑤뜽 紐⑸줉???뺤씤?????덉뒿?덈떎.';
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
                errDiv.textContent = '\u26A0\uFE0F ?ㅻ쪟: ' + entry.text;
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

    function scrollToBottom() {
        chatMessages.scrollTop = chatMessages.scrollHeight;
    }
}());''';
