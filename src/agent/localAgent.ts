import { OpenAI } from 'openai';
import * as vscode from 'vscode';
import { TOOLS, executeTool, getMemorySummary, getGoalInstructions } from './tools';

export interface AgentProgress {
    onThought: (text: string) => void;
    onToolStart: (toolName: string, args: any) => void;
    onToolEnd: (toolName: string, output: string) => void;
    onFinalAnswer: (text: string) => void;
    onError: (error: string) => void;
}

interface AgentMessage {
    role: 'user' | 'assistant';
    content: string;
}

export class LocalAgent {
    private client: OpenAI | null = null;
    private modelName: string = 'local-model';
    private maxIterations = 8;

    constructor() {
        this.updateConfig();
    }

    public updateConfig() {
        const config = vscode.workspace.getConfiguration('noriter-ai');
        const baseUrl = config.get<string>('lmStudioEndpoint') || 'http://localhost:1234/v1';
        this.modelName = config.get<string>('modelName') || 'local-model';

        this.client = new OpenAI({
            baseURL: baseUrl,
            apiKey: 'lm-studio',
            dangerouslyAllowBrowser: true
        });
    }

    public async listAvailableModels(): Promise<string[]> {
        this.updateConfig();

        if (!this.client) {
            throw new Error('OpenAI client not initialized.');
        }

        const response = await this.client.models.list();
        const modelIds = response.data
            .map((model) => model.id)
            .filter((id): id is string => typeof id === 'string' && id.trim().length > 0);

        return Array.from(new Set(modelIds)).sort((a, b) => a.localeCompare(b));
    }

    public async run(
        userMessage: string,
        progress: AgentProgress,
        token: vscode.CancellationToken,
        conversationContext: AgentMessage[] = []
    ): Promise<void> {
        this.updateConfig(); // Refresh config values at launch

        if (!this.client) {
            progress.onError("OpenAI client not initialized.");
            return;
        }

        const workspaceFolders = vscode.workspace.workspaceFolders;
        if (!workspaceFolders || workspaceFolders.length === 0) {
            progress.onError('No workspace folder open.');
            return;
        }
        const workspaceRoot = workspaceFolders[0].uri.fsPath;

        const toolsDesc = TOOLS.map(t => `- ${t.name}: ${t.description}. Params: ${t.parameters}`).join('\n');
        const toolNames = TOOLS.map(t => t.name).join(', ');
        const memorySummary = getMemorySummary(workspaceRoot);
        const goalInstructions = getGoalInstructions(workspaceRoot);

        const systemPrompt = `You are an AI Agent operating inside a VSCode workspace.
You have access to the following tools to interact with the codebase:
${toolsDesc}

Persistent Memory Snapshot:
${memorySummary}

Custom Goal Instructions (from .noriter-ai/agent-goal.md):
${goalInstructions}

Use saveMemory for facts that should persist across tasks, and use getMemory/listMemoryKeys before asking for details that may already be known.

To complete the user's task, you must output step-by-step using this exact ReAct format:

Thought: Describe your reasoning for the current step.
Action: The name of the tool to execute. Must be one of: [${toolNames}]
Action Input: The arguments for the tool in JSON format. Ensure all quotes are valid.
Observation: [The system will provide the tool output here. DO NOT write this line yourself. Stop outputting after Action Input.]

Example format:
Thought: I need to check the files in the workspace.
Action: getWorkspaceFiles
Action Input: {}
Observation: [ "package.json", "src/extension.ts" ]
Thought: I need to read the contents of package.json.
Action: readFile
Action Input: { "relativePath": "package.json" }
Observation: ...
Thought: I now have the final answer.
Final Answer: The package.json lists ...

IMPORTANT: You can only call one tool at a time. Do not write "Observation:" yourself. You must write "Action:" and "Action Input:" and then STOP writing so the system can run the tool.
`;

        const messages: any[] = [{ role: 'system', content: systemPrompt }];

        for (const msg of conversationContext) {
            messages.push({ role: msg.role, content: msg.content });
        }

        messages.push({ role: 'user', content: userMessage });

        let iteration = 0;
        while (iteration < this.maxIterations) {
            if (token.isCancellationRequested) {
                progress.onFinalAnswer("Agent stopped by user.");
                return;
            }

            try {
                const response = await this.client.chat.completions.create({
                    model: this.modelName,
                    messages: messages,
                    temperature: 0.1,
                    stop: ["Observation:", "Observation\n"]
                });

                const content = response.choices[0]?.message?.content || "";
                if (!content.trim()) {
                    progress.onError("Received empty response from local model. Make sure the model is loaded and running in LM Studio.");
                    return;
                }

                // Append assistant message to history
                messages.push({ role: 'assistant', content: content });

                // Parse Thought, Action, Action Input, Final Answer
                const thoughtMatch = content.match(/Thought:\s*([\s\S]*?)(?=Action:|Final Answer:|$)/i);
                const actionMatch = content.match(/Action:\s*([a-zA-Z0-9_-]+)/i);
                const actionInputMatch = content.match(/Action Input:\s*([\s\S]*?)$/i);
                const finalAnswerMatch = content.match(/Final Answer:\s*([\s\S]*?)$/i);

                if (thoughtMatch && thoughtMatch[1].trim()) {
                    progress.onThought(thoughtMatch[1].trim());
                } else if (!actionMatch && !finalAnswerMatch) {
                    // Fallback thought if it didn't use the prefix but didn't trigger tools or final answer
                    progress.onThought(content.trim());
                }

                if (finalAnswerMatch && finalAnswerMatch[1].trim()) {
                    progress.onFinalAnswer(finalAnswerMatch[1].trim());
                    return;
                }

                if (actionMatch) {
                    const toolName = actionMatch[1].trim();
                    let toolArgsStr = actionInputMatch ? actionInputMatch[1].trim() : "{}";
                    
                    // Clean markdown blocks
                    toolArgsStr = toolArgsStr.replace(/^```json/i, '').replace(/```$/, '').trim();

                    let toolArgs: any = {};
                    try {
                        toolArgs = JSON.parse(toolArgsStr);
                    } catch (e) {
                        // Fallback parsing for common errors
                        if (toolName === 'runTerminalCommand' && !toolArgsStr.startsWith('{')) {
                            toolArgs = { command: toolArgsStr };
                        } else if (toolName === 'readFile' && !toolArgsStr.startsWith('{')) {
                            toolArgs = { relativePath: toolArgsStr };
                        } else {
                            // Try to extract JSON from surrounding characters
                            const jsonBlock = toolArgsStr.match(/{[\s\S]*}/);
                            if (jsonBlock) {
                                try {
                                    toolArgs = JSON.parse(jsonBlock[0]);
                                } catch {
                                    progress.onError(`Failed to parse tool arguments: "${toolArgsStr}".`);
                                    return;
                                }
                            } else {
                                progress.onError(`Failed to parse tool arguments: "${toolArgsStr}".`);
                                return;
                            }
                        }
                    }

                    progress.onToolStart(toolName, toolArgs);

                    // Execute the tool
                    const observation = await executeTool(toolName, toolArgs);

                    progress.onToolEnd(toolName, observation);

                    // Feed observation back to history
                    messages.push({ role: 'user', content: `Observation: ${observation}` });
                } else {
                    // If no action or final answer is matched, check if Final Answer is in content without prefix
                    if (content.toLowerCase().includes("final answer:")) {
                        const idx = content.toLowerCase().indexOf("final answer:");
                        progress.onFinalAnswer(content.substring(idx + 13).trim());
                        return;
                    }
                    
                    // Default to content if model just responds without tool calling
                    progress.onFinalAnswer(content.trim());
                    return;
                }

            } catch (err: any) {
                progress.onError(`API Error: ${err.message}`);
                return;
            }

            iteration++;
        }

        progress.onError("Maximum iterations reached without a final answer.");
    }
}
