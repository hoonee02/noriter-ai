import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:noriter_ai_desktop/src/memory_service.dart';
import 'package:noriter_ai_desktop/src/goal_service.dart';
import 'package:noriter_ai_desktop/src/tools.dart';

typedef OnThought = void Function(String text);
typedef OnToolStart = void Function(String name, Map<String, dynamic> args);
typedef OnToolEnd = void Function(String name, String output);
typedef OnFinalAnswer = void Function(String text);
typedef OnError = void Function(String error);

class AgentProgress {
  AgentProgress({
    required this.onThought,
    required this.onToolStart,
    required this.onToolEnd,
    required this.onFinalAnswer,
    required this.onError,
  });

  final OnThought onThought;
  final OnToolStart onToolStart;
  final OnToolEnd onToolEnd;
  final OnFinalAnswer onFinalAnswer;
  final OnError onError;
}

class LocalAgent {
  LocalAgent({
    required this.endpoint,
    required this.apiKey,
    required this.modelName,
    required this.workspaceRoot,
    required this.memoryService,
    required this.goalService,
    this.maxIterations = 8,
  });

  final String endpoint;
  final String apiKey;
  final String modelName;
  final String workspaceRoot;
  final MemoryService memoryService;
  final GoalService goalService;
  final int maxIterations;

  String get _normalizedEndpoint =>
      endpoint.endsWith('/') ? endpoint.substring(0, endpoint.length - 1) : endpoint;

  Future<void> run(
    String userMessage,
    AgentProgress progress,
    bool Function() isCancelled,
    List<Map<String, String>> contextMessages,
  ) async {
    final toolsDesc = kTools.map((t) => '- ${t.name}: ${t.description}. Params: ${t.parameters}').join('\n');
    final toolNames = kTools.map((t) => t.name).join(', ');
    final memorySummary = memoryService.getSummary();
    final goalInstructions = goalService.getGoal();

    final systemPrompt = '''You are an AI Agent operating inside a VSCode workspace.
You have access to the following tools to interact with the codebase:
$toolsDesc

Persistent Memory Snapshot:
$memorySummary

Custom Goal Instructions (from .noriter-ai/agent-goal.md):
$goalInstructions

Use saveMemory for facts that should persist across tasks, and use getMemory/listMemoryKeys before asking for details that may already be known.

To complete the user's task, you must output step-by-step using this exact ReAct format:

Thought: Describe your reasoning for the current step.
Action: The name of the tool to execute. Must be one of: [$toolNames]
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
''';

    final normalizedContext = _normalizeAlternatingMessages(contextMessages);
    final messages = <Map<String, String>>[
      ...normalizedContext,
    ];
    final enrichedUserMessage = _composeUserTurn(systemPrompt, userMessage);

    final shouldAppendCurrentUser = normalizedContext.isEmpty ||
        normalizedContext.last['role'] != 'user' ||
        normalizedContext.last['content'] != userMessage;
    if (shouldAppendCurrentUser) {
      messages.add({'role': 'user', 'content': enrichedUserMessage});
    } else if (messages.isNotEmpty && messages.last['role'] == 'user') {
      messages[messages.length - 1] = {
        'role': 'user',
        'content': enrichedUserMessage,
      };
    }

    for (var iteration = 0; iteration < maxIterations; iteration++) {
      if (isCancelled()) {
        progress.onFinalAnswer('Agent stopped by user.');
        return;
      }

      try {
        final requestMessages = _normalizeAlternatingMessages(messages);
        if (requestMessages.isEmpty) {
          progress.onError('No valid conversation messages to send.');
          return;
        }

        messages
          ..clear()
          ..addAll(requestMessages);

        final response = await http.post(
          Uri.parse('$_normalizedEndpoint/chat/completions'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': modelName,
            'messages': requestMessages,
            'temperature': 0.1,
            'stop': ['Observation:', 'Observation\n'],
          }),
        );

        if (response.statusCode < 200 || response.statusCode >= 300) {
          progress.onError('API Error ${response.statusCode}: ${response.body}');
          return;
        }

        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = decoded['choices'];
        String content = '';
        if (choices is List && choices.isNotEmpty) {
          final first = choices.first;
          if (first is Map<String, dynamic>) {
            final messageObj = first['message'];
            if (messageObj is Map<String, dynamic>) {
              final text = messageObj['content'];
              if (text is String) {
                content = text;
              }
            }
          }
        }

        if (content.trim().isEmpty) {
          progress.onError(
            'Received empty response from local model. Make sure the model is loaded and running in LM Studio.',
          );
          return;
        }

        messages.add({'role': 'assistant', 'content': content});

        final thoughtMatch = RegExp(r'Thought:\s*([\s\S]*?)(?=Action:|Final Answer:|$)', caseSensitive: false)
            .firstMatch(content);
        final actionMatch = RegExp(r'Action:\s*([a-zA-Z0-9_-]+)', caseSensitive: false).firstMatch(content);
        final actionInputMatch =
            RegExp(r'Action Input:\s*([\s\S]*?)$', caseSensitive: false).firstMatch(content);
        final finalAnswerMatch =
            RegExp(r'Final Answer:\s*([\s\S]*?)$', caseSensitive: false).firstMatch(content);

        final thoughtText = thoughtMatch?.group(1)?.trim() ?? '';
        if (thoughtText.isNotEmpty) {
          progress.onThought(thoughtText);
        } else if (actionMatch == null && finalAnswerMatch == null) {
          progress.onThought(content.trim());
        }

        if (finalAnswerMatch != null) {
          final answer = finalAnswerMatch.group(1)?.trim() ?? '';
          if (answer.isNotEmpty) {
            progress.onFinalAnswer(answer);
            return;
          }
        }

        if (actionMatch != null) {
          final toolName = actionMatch.group(1)!.trim();
          var toolArgsStr = actionInputMatch?.group(1)?.trim() ?? '{}';

          // Clean markdown code blocks
          toolArgsStr = toolArgsStr.replaceAll(RegExp(r'^```json', caseSensitive: false), '').replaceAll(RegExp(r'```$'), '').trim();

          Map<String, dynamic> toolArgs;
          try {
            toolArgs = jsonDecode(toolArgsStr) as Map<String, dynamic>;
          } catch (_) {
            if (toolName == 'runTerminalCommand' && !toolArgsStr.startsWith('{')) {
              toolArgs = {'command': toolArgsStr};
            } else if (toolName == 'readFile' && !toolArgsStr.startsWith('{')) {
              toolArgs = {'relativePath': toolArgsStr};
            } else {
              final jsonBlock = RegExp(r'\{[\s\S]*\}').firstMatch(toolArgsStr);
              if (jsonBlock != null) {
                try {
                  toolArgs = jsonDecode(jsonBlock.group(0)!) as Map<String, dynamic>;
                } catch (_) {
                  progress.onError('Failed to parse tool arguments: "$toolArgsStr".');
                  return;
                }
              } else {
                progress.onError('Failed to parse tool arguments: "$toolArgsStr".');
                return;
              }
            }
          }

          progress.onToolStart(toolName, toolArgs);
          final observation = await executeTool(toolName, toolArgs, workspaceRoot, memoryService);
          progress.onToolEnd(toolName, observation);

          messages.add({'role': 'user', 'content': 'Observation: $observation'});
        } else {
          // No action and no explicit Final Answer prefix
          final lc = content.toLowerCase();
          if (lc.contains('final answer:')) {
            final idx = lc.indexOf('final answer:');
            progress.onFinalAnswer(content.substring(idx + 13).trim());
            return;
          }
          progress.onFinalAnswer(content.trim());
          return;
        }
      } catch (e) {
        progress.onError('API Error: $e');
        return;
      }
    }

    progress.onError('Maximum iterations reached without a final answer.');
  }
}

List<Map<String, String>> _normalizeAlternatingMessages(
  List<Map<String, String>> source,
) {
  final result = <Map<String, String>>[];
  for (final item in source) {
    final role = item['role'];
    final content = item['content'];
    if ((role != 'user' && role != 'assistant') ||
        content == null ||
        content.trim().isEmpty) {
      continue;
    }

    if (result.isNotEmpty && result.last['role'] == role) {
      final merged = '${result.last['content']}\n\n$content';
      result[result.length - 1] = {'role': role!, 'content': merged};
      continue;
    }

    result.add({'role': role!, 'content': content});
  }

  if (result.isNotEmpty && result.first['role'] == 'assistant') {
    result.removeAt(0);
  }

  return result;
}

String _composeUserTurn(String systemPrompt, String userMessage) {
  return '''
[Agent Instructions]
$systemPrompt

[User Message]
$userMessage
''';
}
