import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:noriter_ai_desktop/src/assets.dart';
import 'package:noriter_ai_desktop/src/config.dart';
import 'package:noriter_ai_desktop/src/history_service.dart';
import 'package:noriter_ai_desktop/src/local_agent.dart';
import 'package:noriter_ai_desktop/src/memory_service.dart';
import 'package:noriter_ai_desktop/src/goal_service.dart';
import 'package:noriter_ai_desktop/src/model_provider.dart';

class NoriterServer {
  NoriterServer({required this.config});

  final AppConfig config;
  late final HistoryService _history;
  late final MemoryService _memory;
  late final GoalService _goal;
  late final LocalAgent _agent;
  late final OpenAiCompatibleModelProvider _provider;

  // Active WebSocket sinks for broadcasting
  final Set<WebSocketChannel> _clients = {};

  // Cancellation: a completer that can be replaced each run
  bool _cancelled = false;

  Future<void> start() async {
    _history = HistoryService(workspaceRoot: config.workspacePath);
    _memory = MemoryService(workspaceRoot: config.workspacePath);
    _goal = GoalService(workspaceRoot: config.workspacePath);
    _provider = OpenAiCompatibleModelProvider(
      endpoint: config.modelEndpoint,
      apiKey: config.apiKey,
    );
    _agent = LocalAgent(
      endpoint: config.modelEndpoint,
      apiKey: config.apiKey,
      modelName: config.modelName,
      workspaceRoot: config.workspacePath,
      memoryService: _memory,
      goalService: _goal,
    );

    await _history.load();
    _goal.ensureGoalFile();

    final handler = const Pipeline()
        .addMiddleware(_corsMiddleware())
        .addHandler(_router);

    final server = await shelf_io.serve(handler, 'localhost', config.port);
    stdout.writeln('Noriter AI server running at http://localhost:${server.port}');
  }

  Middleware _corsMiddleware() {
    return (Handler inner) {
      return (Request request) async {
        final response = await inner(request);
        return response.change(headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
        });
      };
    };
  }

  Future<Response> _router(Request request) async {
    final path = request.url.path;

    if (path == 'ws') {
      final wsHandler = webSocketHandler((WebSocketChannel channel, String? subProtocol) {
        _handleWebSocket(channel);
      });
      return wsHandler(request);
    }

    if (path == '' || path == 'index.html') {
      return Response.ok(kChatHtml, headers: {'Content-Type': 'text/html; charset=utf-8'});
    }

    if (path == 'main.css') {
      return Response.ok(kMainCss, headers: {'Content-Type': 'text/css; charset=utf-8'});
    }

    if (path == 'main.js') {
      return Response.ok(kMainJs, headers: {'Content-Type': 'application/javascript; charset=utf-8'});
    }

    return Response.notFound('Not found');
  }

  void _handleWebSocket(WebSocketChannel channel) {
    _clients.add(channel);

    // Send current history on connect
    _sendTo(channel, {
      'type': 'loadHistory',
      'entries': _history.getEntries(),
    });

    channel.stream.listen(
      (data) async {
        try {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          await _handleMessage(channel, msg);
        } catch (e) {
          _sendTo(channel, {'type': 'error', 'value': 'Invalid message: $e'});
        }
      },
      onDone: () => _clients.remove(channel),
      onError: (_) => _clients.remove(channel),
    );
  }

  Future<void> _handleMessage(WebSocketChannel channel, Map<String, dynamic> msg) async {
    switch (msg['type'] as String?) {
      case 'webviewReady':
        _sendTo(channel, {
          'type': 'loadHistory',
          'entries': _history.getEntries(),
        });
        break;

      case 'sendMessage':
        final value = msg['value'] as String?;
        if (value != null && value.trim().isNotEmpty) {
          await _handleSendMessage(value.trim());
        }
        break;

      case 'clearHistory':
        await _history.clear();
        _broadcast({'type': 'historyCleared'});
        break;

      case 'stopAgent':
        _cancelled = true;
        break;

      case 'openMemory':
      case 'openGoal':
        // No-op: handled in JS with alert
        break;
    }
  }

  Future<void> _handleSendMessage(String message) async {
    if (message.toLowerCase() == '/models') {
      await _history.append('user', message);
      _broadcast({'type': 'sessionStart', 'userPrompt': message});
      try {
        final models = await _provider.listModels();
        final response = models.isEmpty
            ? '사용 가능한 모델을 찾지 못했습니다. 모델 엔진 상태(LM Studio 또는 OpenAI-compatible endpoint)를 확인하세요.'
            : ['사용 가능한 모델 목록:', ...models.map((m) => '- $m')].join('\n');
        await _history.append('assistant', response);
        _broadcast({'type': 'finalAnswer', 'value': response});
      } catch (e) {
        final err = '모델 목록 조회 실패: $e';
        await _history.append('error', err);
        _broadcast({'type': 'error', 'value': err});
      }
      return;
    }

    _cancelled = false;
    await _history.append('user', message);
    _broadcast({'type': 'sessionStart', 'userPrompt': message});

    final contextMessages = _history.buildContextMessages();

    try {
      await _agent.run(
        message,
        AgentProgress(
          onThought: (text) => _broadcast({'type': 'thought', 'value': text}),
          onToolStart: (name, args) => _broadcast({'type': 'toolStart', 'name': name, 'args': args}),
          onToolEnd: (name, output) => _broadcast({'type': 'toolEnd', 'name': name, 'output': output}),
          onFinalAnswer: (text) async {
            await _history.append('assistant', text);
            _broadcast({'type': 'finalAnswer', 'value': text});
          },
          onError: (err) async {
            await _history.append('error', err);
            _broadcast({'type': 'error', 'value': err});
          },
        ),
        () => _cancelled,
        contextMessages,
      );
    } catch (e) {
      final err = e.toString();
      await _history.append('error', err);
      _broadcast({'type': 'error', 'value': err});
    }
  }

  void _sendTo(WebSocketChannel channel, Map<String, dynamic> data) {
    try {
      channel.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  void _broadcast(Map<String, dynamic> data) {
    final encoded = jsonEncode(data);
    for (final client in List.of(_clients)) {
      try {
        client.sink.add(encoded);
      } catch (_) {
        _clients.remove(client);
      }
    }
  }
}
