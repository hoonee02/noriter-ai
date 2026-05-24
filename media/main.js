(function () {
    const vscode = acquireVsCodeApi();
    const chatMessages = document.getElementById('chat-messages');
    const chatInput = document.getElementById('chat-input');
    const sendButton = document.getElementById('send-btn');
    const stopButton = document.getElementById('stop-btn');
    const agentActivity = document.getElementById('agent-activity');
    const agentStatusText = document.getElementById('agent-status-text');

    let currentLogBlock = null;

    sendButton.addEventListener('click', () => {
        sendMessage();
    });

    chatInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            sendMessage();
        }
    });

    stopButton.addEventListener('click', () => {
        vscode.postMessage({ type: 'stopAgent' });
        showActivity(false);
    });

    function sendMessage() {
        const text = chatInput.value.trim();
        if (text) {
            vscode.postMessage({ type: 'sendMessage', value: text });
            chatInput.value = '';
        }
    }

    function showActivity(show, text = 'Thinking...') {
        if (show) {
            agentActivity.style.display = 'flex';
            agentStatusText.textContent = text;
            sendButton.disabled = true;
            chatInput.disabled = true;
        } else {
            agentActivity.style.display = 'none';
            sendButton.disabled = false;
            chatInput.disabled = false;
        }
    }

    function addMessage(text, sender) {
        const msgDiv = document.createElement('div');
        msgDiv.className = `message ${sender}`;
        msgDiv.textContent = text;
        chatMessages.appendChild(msgDiv);
        scrollToBottom();
    }

    function createLogBlock(title, initialContent = "") {
        const block = document.createElement('div');
        block.className = 'log-block collapsed';

        const header = document.createElement('div');
        header.className = 'log-header';
        header.textContent = title;

        const content = document.createElement('div');
        content.className = 'log-content';
        content.textContent = initialContent;

        header.addEventListener('click', () => {
            block.classList.toggle('collapsed');
        });

        block.appendChild(header);
        block.appendChild(content);
        chatMessages.appendChild(block);
        scrollToBottom();
        
        return {
            element: block,
            contentElement: content,
            append: (text) => {
                content.textContent += text;
            },
            setContent: (text) => {
                content.textContent = text;
            },
            expand: () => {
                block.classList.remove('collapsed');
            }
        };
    }

    function scrollToBottom() {
        chatMessages.scrollTop = chatMessages.scrollHeight;
    }

    window.addEventListener('message', event => {
        const message = event.data;
        switch (message.type) {
            case 'sessionStart':
                chatMessages.innerHTML = '';
                addMessage(message.userPrompt, 'user');
                showActivity(true, '에이전트가 생각하는 중...');
                currentLogBlock = null;
                break;
            case 'thought':
                currentLogBlock = createLogBlock('🤔 에이전트 생각 (Thought)', message.value);
                break;
            case 'toolStart':
                const argsStr = JSON.stringify(message.args, null, 2);
                currentLogBlock = createLogBlock(`⚙️ 도구 실행: ${message.name}`, `Arguments:\n${argsStr}\n\nRunning tool...`);
                currentLogBlock.expand();
                showActivity(true, `도구 실행 중: ${message.name}`);
                break;
            case 'toolEnd':
                if (currentLogBlock) {
                    currentLogBlock.setContent(currentLogBlock.contentElement.textContent.replace('Running tool...', '') + `Output:\n${message.output}`);
                } else {
                    createLogBlock(`⚙️ 도구 완료: ${message.name}`, `Output:\n${message.output}`);
                }
                showActivity(true, '에이전트가 결과 해석 중...');
                break;
            case 'finalAnswer':
                addMessage(message.value, 'assistant');
                showActivity(false);
                currentLogBlock = null;
                break;
            case 'error':
                const errDiv = document.createElement('div');
                errDiv.className = 'error-message';
                errDiv.textContent = `⚠️ 오류: ${message.value}`;
                chatMessages.appendChild(errDiv);
                showActivity(false);
                currentLogBlock = null;
                scrollToBottom();
                break;
        }
    });
}());
