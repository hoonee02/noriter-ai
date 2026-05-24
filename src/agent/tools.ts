import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';
import { exec } from 'child_process';

export interface Tool {
    name: string;
    description: string;
    parameters: string;
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
                exec(command, { cwd: workspaceRoot }, (error, stdout, stderr) => {
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
        default:
            return `Error: Tool '${toolName}' not found.`;
    }
}
