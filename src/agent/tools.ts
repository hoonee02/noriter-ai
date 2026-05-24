import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';
import { exec, ExecException } from 'child_process';

export interface Tool {
    name: string;
    description: string;
    parameters: string;
}

interface MemoryStore {
    [key: string]: string;
}

export const MEMORY_RELATIVE_PATH = '.noriter-ai/agent-memory.md';
const LEGACY_MEMORY_JSON_PATH = '.noriter-ai/agent-memory.json';
export const GOAL_RELATIVE_PATH = '.noriter-ai/agent-goal.md';

function getLegacyMemoryJsonPath(workspaceRoot: string): string {
    return path.join(workspaceRoot, LEGACY_MEMORY_JSON_PATH);
}

function getMemoryFilePath(workspaceRoot: string): string {
    return path.join(workspaceRoot, MEMORY_RELATIVE_PATH);
}

function getGoalFilePath(workspaceRoot: string): string {
    return path.join(workspaceRoot, GOAL_RELATIVE_PATH);
}

function getDefaultGoalMarkdown(): string {
    return [
        '# Noriter AI Agent Goal',
        '',
        'Define the agent\'s objective for this workspace.',
        'Everything in this file is injected into the agent system prompt at runtime.',
        '',
        '## Goal',
        '- Prioritize safe, minimal, and verifiable code changes.',
        '- Prefer workspace conventions and preserve existing style.',
        '- When unsure, gather context first and avoid destructive actions.',
        ''
    ].join('\n');
}

function getDefaultMemoryMarkdown(memory: MemoryStore = {}): string {
    const entries = Object.entries(memory).sort(([a], [b]) => a.localeCompare(b));
    const lines: string[] = [
        '# Noriter AI Memory',
        '',
        'Use this file to store persistent agent memory for this workspace.',
        'Format: - `key`: value',
        '',
        '## Entries'
    ];

    if (entries.length === 0) {
        lines.push('- `example-key`: example value');
    } else {
        for (const [key, value] of entries) {
            lines.push(`- \`${key}\`: ${value}`);
        }
    }

    lines.push('');
    return lines.join('\n');
}

function parseMemoryMarkdown(content: string): MemoryStore {
    const memory: MemoryStore = {};
    const lines = content.split(/\r?\n/);

    for (const line of lines) {
        const trimmed = line.trim();
        let match = trimmed.match(/^-\s*`([^`]+)`\s*:\s*(.+)$/);
        if (!match) {
            match = trimmed.match(/^-\s*([a-zA-Z0-9._-]+)\s*:\s*(.+)$/);
        }

        if (!match) {
            continue;
        }

        const key = match[1].trim();
        const value = match[2].trim();
        if (key && value) {
            memory[key] = value;
        }
    }

    return memory;
}

function parseLegacyMemoryJson(legacyPath: string): MemoryStore {
    try {
        const raw = fs.readFileSync(legacyPath, 'utf8');
        if (!raw.trim()) {
            return {};
        }

        const parsed = JSON.parse(raw) as unknown;
        if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
            return {};
        }

        const normalized: MemoryStore = {};
        for (const [key, value] of Object.entries(parsed as Record<string, unknown>)) {
            if (typeof value === 'string') {
                normalized[key] = value;
            }
        }
        return normalized;
    } catch {
        return {};
    }
}

export function ensureMemoryFile(workspaceRoot: string): string {
    const memoryPath = getMemoryFilePath(workspaceRoot);
    const memoryDir = path.dirname(memoryPath);
    if (!fs.existsSync(memoryDir)) {
        fs.mkdirSync(memoryDir, { recursive: true });
    }

    if (fs.existsSync(memoryPath)) {
        return memoryPath;
    }

    const legacyPath = getLegacyMemoryJsonPath(workspaceRoot);
    if (fs.existsSync(legacyPath)) {
        const legacyMemory = parseLegacyMemoryJson(legacyPath);
        fs.writeFileSync(memoryPath, getDefaultMemoryMarkdown(legacyMemory), 'utf8');
        return memoryPath;
    }

    fs.writeFileSync(memoryPath, getDefaultMemoryMarkdown(), 'utf8');
    return memoryPath;
}

export function ensureGoalFile(workspaceRoot: string): string {
    const goalPath = getGoalFilePath(workspaceRoot);
    const goalDir = path.dirname(goalPath);
    if (!fs.existsSync(goalDir)) {
        fs.mkdirSync(goalDir, { recursive: true });
    }

    if (!fs.existsSync(goalPath)) {
        fs.writeFileSync(goalPath, getDefaultGoalMarkdown(), 'utf8');
    }

    return goalPath;
}

export function getGoalInstructions(workspaceRoot: string): string {
    const goalPath = ensureGoalFile(workspaceRoot);

    try {
        const content = fs.readFileSync(goalPath, 'utf8').trim();
        return content || 'No custom goal defined.';
    } catch {
        return 'No custom goal defined.';
    }
}

function loadMemoryStore(workspaceRoot: string): MemoryStore {
    const memoryPath = ensureMemoryFile(workspaceRoot);

    try {
        const raw = fs.readFileSync(memoryPath, 'utf8');
        if (!raw.trim()) {
            return {};
        }

        return parseMemoryMarkdown(raw);
    } catch {
        return {};
    }
}

function saveMemoryStore(workspaceRoot: string, memory: MemoryStore): void {
    const memoryPath = ensureMemoryFile(workspaceRoot);
    fs.writeFileSync(memoryPath, getDefaultMemoryMarkdown(memory), 'utf8');
}

export function getMemorySummary(workspaceRoot: string, maxEntries = 20): string {
    const memory = loadMemoryStore(workspaceRoot);
    const entries = Object.entries(memory);

    if (entries.length === 0) {
        return 'No saved memory entries.';
    }

    const shown = entries.slice(0, Math.max(1, maxEntries));
    const lines = shown.map(([key, value]) => `- ${key}: ${value}`);
    const omitted = entries.length - shown.length;

    if (omitted > 0) {
        lines.push(`- ...and ${omitted} more entries`);
    }

    return lines.join('\n');
}

export const TOOLS: Tool[] = [
    {
        name: "getWorkspaceFiles",
        description: "List all files in the current workspace. Returns a list of relative file paths.",
        parameters: "None. Provide empty object {}"
    },
    {
        name: "readFile",
        description: "Read the content of a file in the workspace.",
        parameters: "{ \"relativePath\": \"src/extension.ts\" }"
    },
    {
        name: "writeFile",
        description: "Create or overwrite a file in the workspace with new content.",
        parameters: "{ \"relativePath\": \"src/test.ts\", \"content\": \"console.log('hello');\" }"
    },
    {
        name: "runTerminalCommand",
        description: "Execute a command in the terminal at the workspace root directory and get the output.",
        parameters: "{ \"command\": \"npm run build\" }"
    },
    {
        name: "saveMemory",
        description: "Save or update a persistent memory entry for future tasks in this workspace.",
        parameters: "{ \"key\": \"preferred-language\", \"value\": \"typescript\" }"
    },
    {
        name: "getMemory",
        description: "Read one memory by key. Returns not found message when key does not exist.",
        parameters: "{ \"key\": \"preferred-language\" }"
    },
    {
        name: "listMemoryKeys",
        description: "List all stored memory keys.",
        parameters: "None. Provide empty object {}"
    },
    {
        name: "deleteMemory",
        description: "Delete a memory entry by key.",
        parameters: "{ \"key\": \"preferred-language\" }"
    }
];

export async function executeTool(toolName: string, args: any): Promise<string> {
    const workspaceFolders = vscode.workspace.workspaceFolders;
    if (!workspaceFolders || workspaceFolders.length === 0) {
        return "Error: No workspace folder open.";
    }
    const workspaceRoot = workspaceFolders[0].uri.fsPath;

    switch (toolName) {
        case "getWorkspaceFiles": {
            try {
                const files = await vscode.workspace.findFiles('**/*', '**/node_modules/**,**/dist/**,**/.git/**');
                const relativePaths = files.map(file => path.relative(workspaceRoot, file.fsPath));
                return JSON.stringify(relativePaths, null, 2);
            } catch (err: any) {
                return `Error listing files: ${err.message}`;
            }
        }
        case "readFile": {
            const relPath = args.relativePath;
            if (!relPath) {
                return "Error: Missing 'relativePath' parameter.";
            }
            const absPath = path.resolve(workspaceRoot, relPath);
            if (!absPath.startsWith(workspaceRoot)) {
                return "Error: Access denied. Path is outside of workspace.";
            }
            try {
                if (!fs.existsSync(absPath)) {
                    return `Error: File not found at relative path: ${relPath}`;
                }
                const content = fs.readFileSync(absPath, 'utf8');
                return content;
            } catch (err: any) {
                return `Error reading file: ${err.message}`;
            }
        }
        case "writeFile": {
            const relPath = args.relativePath;
            const content = args.content;
            if (!relPath || content === undefined) {
                return "Error: Missing 'relativePath' or 'content' parameters.";
            }
            const absPath = path.resolve(workspaceRoot, relPath);
            if (!absPath.startsWith(workspaceRoot)) {
                return "Error: Access denied. Path is outside of workspace.";
            }
            try {
                const dir = path.dirname(absPath);
                if (!fs.existsSync(dir)) {
                    fs.mkdirSync(dir, { recursive: true });
                }
                fs.writeFileSync(absPath, content, 'utf8');
                return `File successfully written to ${relPath}`;
            } catch (err: any) {
                return `Error writing file: ${err.message}`;
            }
        }
        case "runTerminalCommand": {
            const command = args.command;
            if (!command) {
                return "Error: Missing 'command' parameter.";
            }
            return new Promise((resolve) => {
                exec(command, { cwd: workspaceRoot }, (error: ExecException | null, stdout: string, stderr: string) => {
                    let output = "";
                    if (stdout) {
                        output += `Stdout:\n${stdout}\n`;
                    }
                    if (stderr) {
                        output += `Stderr:\n${stderr}\n`;
                    }
                    if (error) {
                        output += `Error (Exit Code ${error.code}):\n${error.message}\n`;
                    }
                    if (!output) {
                        output = "Command finished with no output.";
                    }
                    resolve(output);
                });
            });
        }
        case "saveMemory": {
            const key = typeof args.key === 'string' ? args.key.trim() : '';
            const value = typeof args.value === 'string' ? args.value.trim() : '';

            if (!key || !value) {
                return "Error: Missing 'key' or 'value' parameter.";
            }

            const memory = loadMemoryStore(workspaceRoot);
            memory[key] = value;
            saveMemoryStore(workspaceRoot, memory);
            return `Memory saved: ${key}`;
        }
        case "getMemory": {
            const key = typeof args.key === 'string' ? args.key.trim() : '';
            if (!key) {
                return "Error: Missing 'key' parameter.";
            }

            const memory = loadMemoryStore(workspaceRoot);
            const value = memory[key];
            if (value === undefined) {
                return `Memory not found for key: ${key}`;
            }

            return `${key}: ${value}`;
        }
        case "listMemoryKeys": {
            const memory = loadMemoryStore(workspaceRoot);
            const keys = Object.keys(memory).sort();
            if (keys.length === 0) {
                return 'No memory keys found.';
            }
            return JSON.stringify(keys, null, 2);
        }
        case "deleteMemory": {
            const key = typeof args.key === 'string' ? args.key.trim() : '';
            if (!key) {
                return "Error: Missing 'key' parameter.";
            }

            const memory = loadMemoryStore(workspaceRoot);
            if (!(key in memory)) {
                return `Memory not found for key: ${key}`;
            }

            delete memory[key];
            saveMemoryStore(workspaceRoot, memory);
            return `Memory deleted: ${key}`;
        }
        default:
            return `Error: Tool '${toolName}' not found.`;
    }
}
