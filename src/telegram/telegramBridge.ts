import * as vscode from 'vscode';
import * as https from 'https';
import { LocalAgent } from '../agent/localAgent';
import { getGoalInstructions, updateGoalInstructions } from '../agent/tools';

interface TelegramUpdate {
    update_id: number;
    message?: {
        message_id?: number;
        text?: string;
        from?: {
            is_bot?: boolean;
        };
        chat?: {
            id?: number | string;
        };
    };
}

interface ChatTurn {
    role: 'user' | 'assistant';
    content: string;
}

export class TelegramBridge {
    private readonly agent: LocalAgent;
    private polling = false;
    private chatContext = new Map<string, ChatTurn[]>();

    constructor(private readonly context: vscode.ExtensionContext) {
        this.agent = new LocalAgent();
    }

    public async refresh(): Promise<void> {
        const config = this.getConfig();
        if (!config.enabled || !config.botToken || !config.chatId) {
            return;
        }

        if (this.polling) {
            return;
        }

        this.polling = true;
        while (this.polling) {
            try {
                await this.pollOnce(config.botToken, config.chatId, config.maxContextMessages);
            } catch {
                // Keep loop alive even if Telegram API intermittently fails.
            }
        }
    }

    public stop() {
        this.polling = false;
    }

    private getConfig() {
        const config = vscode.workspace.getConfiguration('noriter-ai');
        return {
            enabled: config.get<boolean>('telegramEnableChatBridge', false),
            botToken: (config.get<string>('telegramBotToken') || '').trim(),
            chatId: this.normalizeChatId(config.get<string>('telegramChatId') || ''),
            maxContextMessages: config.get<number>('maxContextMessages', 20)
        };
    }

    private normalizeChatId(rawChatId: string): string {
        const trimmed = rawChatId.trim();
        const numericMatch = trimmed.match(/-?\d{5,}/);
        return numericMatch ? numericMatch[0] : trimmed;
    }

    private async pollOnce(botToken: string, allowedChatId: string, maxContextMessages: number): Promise<void> {
        const offset = this.context.globalState.get<number>('noriter-ai.telegramOffset', 0);
        const path = `/bot${botToken}/getUpdates?timeout=25&offset=${offset}`;
        const body = await this.telegramRequest(path, 'GET');

        let parsed: { ok?: boolean; result?: TelegramUpdate[] };
        try {
            parsed = JSON.parse(body) as { ok?: boolean; result?: TelegramUpdate[] };
        } catch {
            return;
        }

        if (!parsed.ok || !Array.isArray(parsed.result) || parsed.result.length === 0) {
            return;
        }

        let nextOffset = offset;
        for (const update of parsed.result) {
            if (update.update_id >= nextOffset) {
                nextOffset = update.update_id + 1;
            }

            const message = update.message;
            if (!message || !message.text || message.from?.is_bot) {
                continue;
            }

            const incomingChatId = this.normalizeChatId(String(message.chat?.id || ''));
            if (!incomingChatId || incomingChatId !== allowedChatId) {
                continue;
            }

            const userMessage = message.text.trim();
            if (!userMessage) {
                continue;
            }

            const commandResult = await this.handleCommand(incomingChatId, userMessage, maxContextMessages);
            if (commandResult !== null) {
                await this.sendMessage(botToken, incomingChatId, commandResult);
                continue;
            }

            const context = this.getChatContext(incomingChatId, maxContextMessages);
            const agentAnswer = await this.runAgent(userMessage, context);
            this.pushChatContext(incomingChatId, userMessage, agentAnswer, maxContextMessages);
            await this.sendMessage(botToken, incomingChatId, agentAnswer);
        }

        if (nextOffset > offset) {
            await this.context.globalState.update('noriter-ai.telegramOffset', nextOffset);
        }
    }

    private getChatContext(chatId: string, maxMessages: number): ChatTurn[] {
        const turns = this.chatContext.get(chatId) || [];
        return turns.slice(Math.max(0, turns.length - maxMessages));
    }

    private pushChatContext(chatId: string, user: string, assistant: string, maxMessages: number) {
        const turns = this.chatContext.get(chatId) || [];
        turns.push({ role: 'user', content: user });
        turns.push({ role: 'assistant', content: assistant });
        this.chatContext.set(chatId, turns.slice(Math.max(0, turns.length - maxMessages)));
    }

    private async handleCommand(chatId: string, text: string, maxContextMessages: number): Promise<string | null> {
        if (!text.startsWith('/')) {
            return null;
        }

        const workspaceRoot = this.getWorkspaceRoot();
        const [rawCommand, ...rest] = text.split(' ');
        const command = rawCommand.split('@')[0];
        const payload = rest.join(' ').trim();

        switch (command.toLowerCase()) {
            case '/start': {
                return [
                    'Noriter AI Telegram bridge is ready.',
                    '',
                    'How to use:',
                    '- Send any normal message to chat with the AI agent.',
                    '- /status: show bridge and context status',
                    '- /reset: clear Telegram-side conversation context',
                    '- /goal: show current goal',
                    '- /models: list models available from current model endpoint',
                    '- /goal <text>: update goal remotely',
                    '',
                    'Tip: If no response arrives, verify bridge settings in VS Code Telegram integration window.'
                ].join('\n');
            }
            case '/reset': {
                this.chatContext.set(chatId, []);
                return 'Context reset complete for this Telegram chat.';
            }
            case '/status': {
                const contextSize = (this.chatContext.get(chatId) || []).length;
                const goalSummary = workspaceRoot
                    ? this.truncateText(getGoalInstructions(workspaceRoot), 500)
                    : 'No workspace folder open.';
                return [
                    'Bridge status: active',
                    `Chat ID: ${chatId}`,
                    `Context turns stored: ${contextSize}`,
                    `Context limit: ${maxContextMessages}`,
                    '',
                    'Current goal summary:',
                    goalSummary,
                    '',
                    'Commands: /start, /reset, /status, /goal, /models, /goal <new goal text>'
                ].join('\n');
            }
            case '/models': {
                try {
                    const models = await this.agent.listAvailableModels();
                    if (models.length === 0) {
                        return 'No models reported by the configured model endpoint.';
                    }
                    return ['Available models:', ...models.map((model) => `- ${model}`)].join('\n');
                } catch (error: any) {
                    return `Failed to list models: ${error.message}`;
                }
            }
            case '/goal': {
                if (!workspaceRoot) {
                    return 'No workspace folder open. Goal file is unavailable.';
                }

                if (!payload) {
                    return [
                        'Current goal:',
                        this.truncateText(getGoalInstructions(workspaceRoot), 3000),
                        '',
                        'To update: /goal your new objective text'
                    ].join('\n');
                }

                updateGoalInstructions(workspaceRoot, payload);
                return `Goal updated. New goal:\n${payload}`;
            }
            default:
                return 'Unknown command. Available: /start, /reset, /status, /goal, /models, /goal <new goal text>';
        }
    }

    private getWorkspaceRoot(): string | null {
        const workspaceFolders = vscode.workspace.workspaceFolders;
        if (!workspaceFolders || workspaceFolders.length === 0) {
            return null;
        }
        return workspaceFolders[0].uri.fsPath;
    }

    private truncateText(value: string, maxLength: number): string {
        if (value.length <= maxLength) {
            return value;
        }
        return `${value.slice(0, maxLength)}\n\n(Truncated)`;
    }

    private async runAgent(userMessage: string, context: ChatTurn[]): Promise<string> {
        const tokenSource = new vscode.CancellationTokenSource();

        return new Promise<string>((resolve) => {
            let finalAnswer = '';
            this.agent.run(
                userMessage,
                {
                    onThought: () => {},
                    onToolStart: () => {},
                    onToolEnd: () => {},
                    onFinalAnswer: (text) => {
                        finalAnswer = text || 'Done.';
                        resolve(finalAnswer);
                    },
                    onError: (error) => {
                        resolve(`Agent error: ${error}`);
                    }
                },
                tokenSource.token,
                context
            ).catch((error: Error) => {
                resolve(`Agent error: ${error.message}`);
            });
        });
    }

    private async sendMessage(botToken: string, chatId: string, text: string): Promise<void> {
        const safeText = text.length > 3900 ? `${text.slice(0, 3900)}\n\n(Truncated)` : text;
        const payload = new URLSearchParams({
            chat_id: chatId,
            text: safeText
        }).toString();

        await this.telegramRequest(`/bot${botToken}/sendMessage`, 'POST', payload);
    }

    private async telegramRequest(path: string, method: 'GET' | 'POST', payload?: string): Promise<string> {
        return new Promise((resolve, reject) => {
            const req = https.request(
                {
                    hostname: 'api.telegram.org',
                    path,
                    method,
                    headers: payload
                        ? {
                              'Content-Type': 'application/x-www-form-urlencoded',
                              'Content-Length': Buffer.byteLength(payload)
                          }
                        : undefined
                },
                (res) => {
                    let body = '';
                    res.on('data', (chunk) => {
                        body += chunk.toString();
                    });
                    res.on('end', () => {
                        resolve(body);
                    });
                }
            );

            req.on('error', reject);
            if (payload) {
                req.write(payload);
            }
            req.end();
        });
    }
}
