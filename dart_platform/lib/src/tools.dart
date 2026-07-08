import 'dart:convert';
import 'dart:io';

import 'package:noriter_ai_desktop/src/memory_service.dart';

class Tool {
  const Tool({required this.name, required this.description, required this.parameters});
  final String name;
  final String description;
  final String parameters;
}

const List<Tool> kTools = [
  Tool(
    name: 'getWorkspaceFiles',
    description: 'List all files in the current workspace. Returns a list of relative file paths.',
    parameters: 'None. Provide empty object {}',
  ),
  Tool(
    name: 'readFile',
    description: 'Read the content of a file in the workspace.',
    parameters: '{ "relativePath": "src/extension.ts" }',
  ),
  Tool(
    name: 'writeFile',
    description: 'Create or overwrite a file in the workspace with new content.',
    parameters: '{ "relativePath": "src/test.ts", "content": "console.log(\'hello\');" }',
  ),
  Tool(
    name: 'runTerminalCommand',
    description: 'Execute a command in the terminal at the workspace root directory and get the output.',
    parameters: '{ "command": "npm run build" }',
  ),
  Tool(
    name: 'saveMemory',
    description: 'Save or update a persistent memory entry for future tasks in this workspace.',
    parameters: '{ "key": "preferred-language", "value": "typescript" }',
  ),
  Tool(
    name: 'getMemory',
    description: 'Read one memory by key. Returns not found message when key does not exist.',
    parameters: '{ "key": "preferred-language" }',
  ),
  Tool(
    name: 'listMemoryKeys',
    description: 'List all stored memory keys.',
    parameters: 'None. Provide empty object {}',
  ),
  Tool(
    name: 'deleteMemory',
    description: 'Delete a memory entry by key.',
    parameters: '{ "key": "preferred-language" }',
  ),
  Tool(
    name: 'sendTelegramMessage',
    description: 'Send a message to a configured Telegram bot chat.',
    parameters: '{ "text": "Build completed successfully" }',
  ),
];

List<String> _listFilesRecursive(String root, Directory dir) {
  final results = <String>[];
  final skipDirs = {'node_modules', 'dist', '.git', '.dart_tool', 'build'};

  try {
    for (final entity in dir.listSync(recursive: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (entity is Directory) {
        if (skipDirs.contains(name)) continue;
        results.addAll(_listFilesRecursive(root, entity));
      } else if (entity is File) {
        final relative = entity.path.startsWith(root)
            ? entity.path.substring(root.length).replaceAll('\\', '/').replaceFirst('/', '')
            : entity.path;
        results.add(relative);
      }
    }
  } catch (_) {}

  return results;
}

Future<String> executeTool(
  String toolName,
  Map<String, dynamic> args,
  String workspaceRoot,
  MemoryService memoryService,
) async {
  switch (toolName) {
    case 'getWorkspaceFiles':
      try {
        final files = _listFilesRecursive(workspaceRoot, Directory(workspaceRoot));
        return jsonEncode(files);
      } catch (e) {
        return 'Error listing files: $e';
      }

    case 'readFile':
      {
        final relPath = args['relativePath'] as String?;
        if (relPath == null || relPath.isEmpty) {
          return "Error: Missing 'relativePath' parameter.";
        }
        final absPath = '$workspaceRoot${Platform.pathSeparator}${relPath.replaceAll('/', Platform.pathSeparator)}';
        final normalized = File(absPath).absolute.path;
        if (!normalized.startsWith(Directory(workspaceRoot).absolute.path)) {
          return 'Error: Access denied. Path is outside of workspace.';
        }
        final file = File(absPath);
        if (!file.existsSync()) {
          return 'Error: File not found at relative path: $relPath';
        }
        try {
          return file.readAsStringSync();
        } catch (e) {
          return 'Error reading file: $e';
        }
      }

    case 'writeFile':
      {
        final relPath = args['relativePath'] as String?;
        final content = args['content'] as String?;
        if (relPath == null || relPath.isEmpty || content == null) {
          return "Error: Missing 'relativePath' or 'content' parameters.";
        }
        final absPath = '$workspaceRoot${Platform.pathSeparator}${relPath.replaceAll('/', Platform.pathSeparator)}';
        final normalized = File(absPath).absolute.path;
        if (!normalized.startsWith(Directory(workspaceRoot).absolute.path)) {
          return 'Error: Access denied. Path is outside of workspace.';
        }
        try {
          final dir = File(absPath).parent;
          if (!dir.existsSync()) dir.createSync(recursive: true);
          File(absPath).writeAsStringSync(content);
          return 'File successfully written to $relPath';
        } catch (e) {
          return 'Error writing file: $e';
        }
      }

    case 'runTerminalCommand':
      {
        final command = args['command'] as String?;
        if (command == null || command.isEmpty) {
          return "Error: Missing 'command' parameter.";
        }
        try {
          final result = await Process.run(
            'cmd',
            ['/c', command],
            workingDirectory: workspaceRoot,
            runInShell: false,
          );
          final out = StringBuffer();
          if (result.stdout.toString().isNotEmpty) {
            out.write('Stdout:\n${result.stdout}\n');
          }
          if (result.stderr.toString().isNotEmpty) {
            out.write('Stderr:\n${result.stderr}\n');
          }
          if (result.exitCode != 0) {
            out.write('Exit code: ${result.exitCode}\n');
          }
          final output = out.toString();
          return output.isNotEmpty ? output : 'Command finished with no output.';
        } catch (e) {
          return 'Error running command: $e';
        }
      }

    case 'saveMemory':
      {
        final key = (args['key'] as String? ?? '').trim();
        final value = (args['value'] as String? ?? '').trim();
        if (key.isEmpty || value.isEmpty) {
          return "Error: Missing 'key' or 'value' parameter.";
        }
        return memoryService.saveMemory(key, value);
      }

    case 'getMemory':
      {
        final key = (args['key'] as String? ?? '').trim();
        if (key.isEmpty) return "Error: Missing 'key' parameter.";
        return memoryService.getMemory(key);
      }

    case 'listMemoryKeys':
      return memoryService.listKeys();

    case 'deleteMemory':
      {
        final key = (args['key'] as String? ?? '').trim();
        if (key.isEmpty) return "Error: Missing 'key' parameter.";
        return memoryService.deleteMemory(key);
      }

    case 'sendTelegramMessage':
      {
        final text = (args['text'] as String? ?? '').trim();
        if (text.isEmpty) return "Error: Missing 'text' parameter.";
        return await _sendTelegram(text);
      }

    default:
      return 'Error: Unknown tool "$toolName".';
  }
}

Future<String> _sendTelegram(String text) async {
  final botToken = Platform.environment['NORITER_TELEGRAM_TOKEN'] ?? '';
  final chatId = Platform.environment['NORITER_TELEGRAM_CHAT_ID'] ?? '';
  if (botToken.isEmpty || chatId.isEmpty) {
    return 'Telegram is not configured. Set NORITER_TELEGRAM_TOKEN and NORITER_TELEGRAM_CHAT_ID environment variables.';
  }

  final client = HttpClient();
  try {
    final uri = Uri.parse('https://api.telegram.org/bot$botToken/sendMessage');
    final request = await client.postUrl(uri);
    final body = jsonEncode({'chat_id': chatId, 'text': text});
    request.headers.set('Content-Type', 'application/json');
    request.write(body);
    final response = await request.close();
    final respBody = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      return 'Telegram API Error (${response.statusCode}): $respBody';
    }
    return 'Telegram message sent successfully.';
  } catch (e) {
    return 'Telegram request failed: $e';
  } finally {
    client.close();
  }
}
