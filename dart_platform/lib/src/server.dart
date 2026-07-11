import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:noriter_ai_desktop/src/assets.dart';
import 'package:noriter_ai_desktop/src/config.dart';
import 'package:noriter_ai_desktop/src/engine_state.dart';
import 'package:noriter_ai_desktop/src/history_service.dart';
import 'package:noriter_ai_desktop/src/llama_engine_manager.dart';
import 'package:noriter_ai_desktop/src/local_agent.dart';
import 'package:noriter_ai_desktop/src/memory_service.dart';
import 'package:noriter_ai_desktop/src/goal_service.dart';
import 'package:noriter_ai_desktop/src/model_download_service.dart';
import 'package:noriter_ai_desktop/src/model_provider.dart';
import 'package:noriter_ai_desktop/src/telegram_bridge.dart';
import 'package:noriter_ai_desktop/src/telegram_config_service.dart';
import 'package:noriter_ai_desktop/src/last_engine_service.dart';

class NoriterServer {
  NoriterServer({required this.config, required this.engineManager});

  final AppConfig config;
  final LlamaEngineManager engineManager;

  late final HistoryService _history;
  late final MemoryService _memory;
  late final GoalService _goal;
  late LocalAgent _agent;
  late OpenAiCompatibleModelProvider _provider;

  late final TelegramConfigService _telegramConfigService;
  late TelegramConfig _telegramConfig;
  late final TelegramBridge _telegramBridge;
  String _telegramStatusMessage = 'Not configured.';

  late final LastEngineService _lastEngineService;
  LastEngineConfig? _lastEngineConfig;
  bool _lastEngineOffered = false;

  final Set<WebSocketChannel> _clients = {};
  bool _cancelled = false;

  // Live endpoint (may change when embedded engine starts)
  late String _activeEndpoint;

  final EngineState _engineState = EngineState();

  Future<void> start() async {
    _history = HistoryService(workspaceRoot: config.workspacePath);
    _memory = MemoryService(workspaceRoot: config.workspacePath);
    _goal = GoalService(workspaceRoot: config.workspacePath);

    _activeEndpoint = config.engineMode == EngineMode.embedded
        ? 'http://127.0.0.1:8080/v1'
        : config.modelEndpoint;

    _engineState.mode = config.engineMode;

    _rebuildAgent();

    await _history.load();
    _goal.ensureGoalFile();

    _telegramConfigService = TelegramConfigService(workspaceRoot: config.workspacePath);
    _telegramConfig = await _telegramConfigService.load();
    _telegramBridge = TelegramBridge(
      onMessage: _runAgentForTelegram,
      onStatus: (status) {
        _telegramStatusMessage = status;
        _broadcastTelegramStatus();
      },
      onChatBound: (chatId) {
        _telegramConfig.chatId = chatId;
        unawaited(_telegramConfigService.save(_telegramConfig));
        _broadcastTelegramStatus();
      },
    );
    if (_telegramConfig.enabled) {
      _telegramBridge.start(_telegramConfig.botToken, _telegramConfig.chatId);
    }

    _lastEngineService = LastEngineService(workspaceRoot: config.workspacePath);
    _lastEngineConfig = await _lastEngineService.load();
    if (_lastEngineConfig != null && !File(_lastEngineConfig!.modelPath).existsSync()) {
      _lastEngineConfig = null;
    }

    final handler = const Pipeline()
        .addMiddleware(_corsMiddleware())
        .addHandler(_router);

    final server = await shelf_io.serve(handler, 'localhost', config.port);
    stdout.writeln('Noriter AI server running at http://localhost:${server.port}');
    if (_wsDebug) {
      stdout.writeln('[ws] WS_DEBUG=1 — logging all WebSocket traffic and agent turns to this console.');
    }
  }

  void _rebuildAgent() {
    _provider = OpenAiCompatibleModelProvider(
      endpoint: _activeEndpoint,
      apiKey: config.apiKey,
    );
    _agent = LocalAgent(
      endpoint: _activeEndpoint,
      apiKey: config.apiKey,
      modelName: config.modelName,
      workspaceRoot: config.workspacePath,
      memoryService: _memory,
      goalService: _goal,
    );
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

    _sendTo(channel, {
      'type': 'loadHistory',
      'entries': _history.getEntries(),
    });

    // Send engine state immediately on connect
    _sendTo(channel, {
      'type': 'engineStatus',
      'state': _engineState.toJson(),
      'isInstalled': engineManager.isInstalled,
      'localModels': engineManager.listLocalModels(),
      'recommendedModels': ModelDownloadService.recommendedModels,
      'activeModelPath': engineManager.activeModelPath,
    });

    _sendTo(channel, _telegramStatusPayload());

    if (!_lastEngineOffered &&
        _lastEngineConfig != null &&
        _engineState.status != EngineStatus.ready &&
        _engineState.status != EngineStatus.starting) {
      _lastEngineOffered = true;
      final cfg = _lastEngineConfig!;
      _sendTo(channel, {
        'type': 'lastEngineFound',
        'modelPath': cfg.modelPath,
        'contextSize': cfg.contextSize,
      });
    }

    channel.stream.listen(
      (data) async {
        try {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          _logWsEvent('RECV', msg);
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
        _sendTo(channel, {'type': 'loadHistory', 'entries': _history.getEntries()});
        _sendTo(channel, {
          'type': 'engineStatus',
          'state': _engineState.toJson(),
          'isInstalled': engineManager.isInstalled,
          'localModels': engineManager.listLocalModels(),
          'recommendedModels': ModelDownloadService.recommendedModels,
          'activeModelPath': engineManager.activeModelPath,
        });
        break;

      case 'sendMessage':
        final value = msg['value'] as String?;
        final attachment = msg['attachment'];
        String? finalValue = value;
        String? historyValue;
        if (attachment is Map<String, dynamic>) {
          final fileName = (attachment['name'] as String?) ?? 'file';
          final content = (attachment['content'] as String?) ?? '';
          finalValue = _composeMessageWithAttachment(value, fileName, content);
          historyValue = _composeAttachmentHistoryPlaceholder(value, fileName, content.length);
        }
        if (finalValue != null && finalValue.trim().isNotEmpty) {
          await _handleSendMessage(finalValue.trim(), historyMessage: historyValue?.trim());
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
        break;

      case 'getEngineStatus':
        _sendTo(channel, {
          'type': 'engineStatus',
          'state': _engineState.toJson(),
          'isInstalled': engineManager.isInstalled,
          'localModels': engineManager.listLocalModels(),
          'recommendedModels': ModelDownloadService.recommendedModels,
          'activeModelPath': engineManager.activeModelPath,
        });
        break;

      case 'downloadEngine':
        _engineState.status = EngineStatus.downloadingEngine;
        _broadcastEngineStatus();
        unawaited(_runDownloadEngine());
        break;

      case 'listLocalModels':
        _sendTo(channel, {
          'type': 'localModelsList',
          'models': engineManager.listLocalModels(),
        });
        break;

      case 'startEngine':
        final modelPath = msg['modelPath'] as String?;
        final requestedContextSize = msg['contextSize'];
        final contextSize = requestedContextSize is int
            ? requestedContextSize.clamp(512, 32768)
            : _engineState.contextSize;
        if (modelPath != null && modelPath.isNotEmpty) {
          unawaited(_runStartEngine(modelPath, contextSize));
        }
        break;

      case 'stopEngine':
        unawaited(_runStopEngine());
        break;

      case 'downloadModel':
        final url = msg['url'] as String?;
        final filename = msg['filename'] as String?;
        if (url != null && url.isNotEmpty) {
          unawaited(_runDownloadModel(url, filename));
        }
        break;

      case 'getTelegramStatus':
        _sendTo(channel, _telegramStatusPayload());
        break;

      case 'updateTelegramConfig':
        unawaited(_runUpdateTelegramConfig(msg));
        break;
    }
  }

  Map<String, dynamic> _telegramStatusPayload() => {
        'type': 'telegramStatus',
        'config': _telegramConfig.toPublicJson(),
        'running': _telegramBridge.isRunning,
        'statusMessage': _telegramStatusMessage,
      };

  void _broadcastTelegramStatus() {
    _broadcast(_telegramStatusPayload());
  }

  Future<void> _runUpdateTelegramConfig(Map<String, dynamic> msg) async {
    final botToken = msg['botToken'];
    final chatId = msg['chatId'];
    final enabled = msg['enabled'];

    if (botToken is String && botToken.trim().isNotEmpty) {
      _telegramConfig.botToken = botToken.trim();
    }
    if (chatId is String) {
      _telegramConfig.chatId = chatId.trim();
    }
    if (enabled is bool) {
      _telegramConfig.enabled = enabled;
    }
    await _telegramConfigService.save(_telegramConfig);

    _telegramBridge.stop();
    if (_telegramConfig.enabled) {
      _telegramBridge.start(_telegramConfig.botToken, _telegramConfig.chatId);
    } else {
      _telegramStatusMessage = 'Telegram bridge disabled.';
    }
    _broadcastTelegramStatus();
  }

  /// Runs the shared agent for a Telegram-originated message. Reuses the same
  /// history/agent as the web chat so both surfaces stay in sync, and returns
  /// the final answer text to send back to the Telegram chat.
  Future<String> _runAgentForTelegram(String message) async {
    if (_wsDebug) {
      stdout.writeln('[agent][telegram] incoming: ${_truncateForLog(message)}');
    }
    if (config.engineMode == EngineMode.embedded &&
        _engineState.status != EngineStatus.ready) {
      return engineManager.isInstalled
          ? 'Engine is installed but not running. Open the app and start the engine from the [Engine] panel.'
          : 'No LLM engine found. Open the app and download the engine from the [Engine] panel.';
    }

    _cancelled = false;
    await _history.append('user', message);
    _broadcast({'type': 'sessionStart', 'userPrompt': message});

    final contextMessages = _history.buildContextMessages();
    final completer = Completer<String>();

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
            if (!completer.isCompleted) completer.complete(text.isEmpty ? 'Done.' : text);
          },
          onError: (err) async {
            await _history.append('error', err);
            _broadcast({'type': 'error', 'value': err});
            if (!completer.isCompleted) completer.complete('Agent error: $err');
          },
        ),
        () => _cancelled,
        contextMessages,
      );
    } catch (e) {
      final err = e.toString();
      await _history.append('error', err);
      _broadcast({'type': 'error', 'value': err});
      if (!completer.isCompleted) completer.complete('Agent error: $err');
    }

    // onFinalAnswer/onError are fire-and-forget callbacks: agent.run() returns
    // as soon as they're invoked, not once their async body (history append,
    // broadcast) finishes. Wait for the completer itself rather than assuming
    // it's already done, otherwise this always races to the 'Done.' fallback.
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => 'Done.',
    );
  }

  Future<void> _runDownloadEngine() async {
    try {
      await engineManager.downloadEngine(onStatus: (status) {
        _engineState.statusMessage = status;
        _broadcastEngineStatus();
      });
      _engineState.status = EngineStatus.idle;
      _engineState.statusMessage = 'Engine installed! Download a model and click Run.';
    } catch (e) {
      _engineState.status = EngineStatus.error;
      _engineState.statusMessage = 'Engine download failed: $e';
    }
    _broadcastEngineStatus();
  }

  Future<void> _runStartEngine(String modelPath, int contextSize) async {
    _engineState.status = EngineStatus.starting;
    _engineState.statusMessage = 'Starting engine...';
    _engineState.activeModelPath = modelPath;
    _engineState.contextSize = contextSize;
    _broadcastEngineStatus();
    try {
      await engineManager.startServer(modelPath, contextSize: contextSize);
      _activeEndpoint = 'http://127.0.0.1:${engineManager.activePort}/v1';
      _rebuildAgent();
      _engineState.status = EngineStatus.ready;
      _engineState.serverPort = engineManager.activePort;
      _engineState.contextSize = engineManager.activeContextSize ?? contextSize;
      _engineState.statusMessage = 'Engine ready! Start chatting.';
      _lastEngineConfig = LastEngineConfig(modelPath: modelPath, contextSize: _engineState.contextSize);
      unawaited(_lastEngineService.save(_lastEngineConfig!));
    } catch (e) {
      _engineState.status = EngineStatus.error;
      _engineState.statusMessage = 'Engine start failed: $e';
    }
    _broadcastEngineStatus();
  }

  Future<void> _runDownloadModel(String url, String? filename) async {
    _engineState.status = EngineStatus.downloadingModel;
    _engineState.statusMessage = 'Model download starting...';
    _broadcastEngineStatus();
    try {
      final svc = ModelDownloadService(modelsDir: engineManager.modelsDir);
      await svc.downloadModel(
        url,
        saveName: filename,
        onProgress: (received, total) {
          final mb = (received / 1024 / 1024).toStringAsFixed(1);
          final totalMb = total > 0 ? (total / 1024 / 1024).toStringAsFixed(1) : '?';
          final pct = total > 0 ? '${received * 100 ~/ total}%' : '';
          _engineState.statusMessage = 'Downloading... $mb MB / $totalMb MB $pct';
          _broadcastEngineStatus();
        },
      );
      _engineState.status = EngineStatus.idle;
      _engineState.statusMessage = 'Model download complete!';
    } catch (e) {
      _engineState.status = EngineStatus.error;
      _engineState.statusMessage = 'Model download failed: $e';
    }

    _broadcastEngineStatus();
    // Refresh model list after download
    _broadcast({
      'type': 'localModelsList',
      'models': engineManager.listLocalModels(),
    });
  }

  Future<void> _runStopEngine() async {
    await engineManager.stopServer();
    _engineState.status = EngineStatus.idle;
    _engineState.serverPort = null;
    _engineState.activeModelPath = null;
    _engineState.statusMessage = engineManager.isInstalled
        ? 'Engine stopped.'
        : 'Engine is not installed.';
    _broadcastEngineStatus();
  }

  void _broadcastEngineStatus() {
    _broadcast({
      'type': 'engineStatus',
      'state': _engineState.toJson(),
      'isInstalled': engineManager.isInstalled,
      'localModels': engineManager.listLocalModels(),
      'recommendedModels': ModelDownloadService.recommendedModels,
      'activeModelPath': engineManager.activeModelPath,
    });
  }

  /// Builds a single user-turn message that embeds a locally attached file's
  /// text content alongside whatever the user typed, so the agent can process
  /// it like any other conversation turn.
  String _composeMessageWithAttachment(String? userText, String fileName, String content) {
    const maxChars = 8000;
    final truncated = content.length > maxChars;
    final body = truncated ? content.substring(0, maxChars) : content;
    final notice = truncated ? '\n\n(File truncated to $maxChars characters)' : '';
    final prompt = (userText != null && userText.trim().isNotEmpty)
        ? userText.trim()
        : 'Please review the attached file.';
    // This file was uploaded from the user's local machine, not saved to the
    // workspace -- readFile/writeFile can't see it. Its full content is
    // already inlined below, so the model must work with it directly instead
    // of trying (and failing) to look it up as a workspace file.
    return '$prompt\n\n'
        '[Attached file: $fileName -- its full content is inlined below. '
        'This file is NOT in the workspace, so do NOT call readFile, writeFile, '
        'or any other tool to access it -- just read the content directly from this message.]\n'
        '```\n$body\n```$notice';
  }

  /// Short stand-in stored to persistent history instead of the full
  /// attachment body. Every future turn resends the whole conversation
  /// history as LLM context, so keeping the full file content there would
  /// make context balloon (and get silently trimmed / overwhelm small
  /// models) on every later message, not just the turn where it was sent.
  String _composeAttachmentHistoryPlaceholder(String? userText, String fileName, int contentLength) {
    final prompt = (userText != null && userText.trim().isNotEmpty)
        ? userText.trim()
        : 'Please review the attached file.';
    return '$prompt\n\n[Attached file: $fileName ($contentLength chars) '
        '-- content was provided for this turn only and is not kept in later context]';
  }

  Future<void> _handleSendMessage(String message, {String? historyMessage}) async {
    if (_wsDebug) {
      stdout.writeln('[agent][web] incoming: ${_truncateForLog(message)}');
    }
    if (message.toLowerCase() == '/models') {
      await _history.append('user', message);
      _broadcast({'type': 'sessionStart', 'userPrompt': message});
      try {
        final models = await _provider.listModels();
        final response = models.isEmpty
            ? 'No models found. Install a model from the Engine panel.'
            : ['Available models:', ...models.map((m) => '- $m')].join('\n');
        await _history.append('assistant', response);
        _broadcast({'type': 'finalAnswer', 'value': response});
      } catch (e) {
        final err = 'Model list query failed: $e';
        await _history.append('error', err);
        _broadcast({'type': 'error', 'value': err});
      }
      return;
    }

    if (message.toLowerCase() == '/engine') {
      await _history.append('user', message);
      _broadcast({'type': 'sessionStart', 'userPrompt': message});
      final installed = engineManager.isInstalled ? '[installed]' : '[not installed]';
      final activeModel = engineManager.activeModelPath ?? 'none';
      final status = _engineState.status.name;
      final models = engineManager.listLocalModels();
      final modelLines = models.isEmpty ? ['  (none)'] : models.map((m) => '  - $m').toList();
      final response = [
        '[Engine Status]',
        '- llama-server: $installed',
        '- Status: $status',
        '- Active model: $activeModel',
        '- Local models:',
        ...modelLines,
        '',
        'Use the [Engine] button in the header to download and start a model.',
      ].join('\n');
      await _history.append('assistant', response);
      _broadcast({'type': 'finalAnswer', 'value': response});
      return;
    }

    // Guard: in embedded mode, refuse chat until engine is ready
    if (config.engineMode == EngineMode.embedded &&
        _engineState.status != EngineStatus.ready) {
      final hint = engineManager.isInstalled
          ? 'Engine is installed but not running.\nOpen the [Engine] panel, select a model, and click Run.'
          : 'No LLM engine found.\nOpen the [Engine] panel to download llama-server and a model.';
      _broadcast({'type': 'engineNotReady', 'value': hint});
      return;
    }

    _cancelled = false;
    final storedMessage = historyMessage ?? message;
    await _history.append('user', storedMessage);
    _broadcast({'type': 'sessionStart', 'userPrompt': storedMessage});

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
    _logWsEvent('SEND', data);
    try {
      channel.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  void _broadcast(Map<String, dynamic> data) {
    _logWsEvent('BROADCAST', data);
    final encoded = jsonEncode(data);
    for (final client in List.of(_clients)) {
      try {
        client.sink.add(encoded);
      } catch (_) {
        _clients.remove(client);
      }
    }
  }

  /// Debug logging (WS_DEBUG=1) that prints every outgoing/incoming WebSocket
  /// event to stdout, so agent activity that's hidden or collapsed in the UI
  /// can be traced from the terminal instead.
  static final bool _wsDebug = Platform.environment['WS_DEBUG'] == '1';

  void _logWsEvent(String direction, Map<String, dynamic> data) {
    if (!_wsDebug) return;
    final type = data['type'] ?? '?';
    final preview = _previewJson(data);
    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    stdout.writeln('[ws][$timestamp][$direction][$type] $preview');
  }

  String _truncateForLog(String text, {int maxLength = 200}) {
    final oneLine = text.replaceAll('\n', ' \\n ');
    return oneLine.length > maxLength ? '${oneLine.substring(0, maxLength)}...(${oneLine.length} chars)' : oneLine;
  }

  String _previewJson(Map<String, dynamic> data, {int maxLength = 300}) {
    String encoded;
    try {
      encoded = jsonEncode(data);
    } catch (e) {
      encoded = '<unencodable: $e>';
    }
    return encoded.length > maxLength ? '${encoded.substring(0, maxLength)}...(${encoded.length} chars)' : encoded;
  }
}

void unawaited(Future<void> future) {
  future.catchError((Object e) {
    stderr.writeln('Unhandled background error: $e');
  });
}
