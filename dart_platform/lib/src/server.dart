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
import 'package:noriter_ai_desktop/src/ollama_engine_manager.dart';
import 'package:noriter_ai_desktop/src/local_agent.dart';
import 'package:noriter_ai_desktop/src/memory_service.dart';
import 'package:noriter_ai_desktop/src/goal_service.dart';
import 'package:noriter_ai_desktop/src/model_provider.dart';
import 'package:noriter_ai_desktop/src/telegram_bridge.dart';
import 'package:noriter_ai_desktop/src/telegram_config_service.dart';
import 'package:noriter_ai_desktop/src/last_engine_service.dart';

class NoriterServer {
  NoriterServer({required this.config, required this.engineManager});

  final AppConfig config;
  final OllamaEngineManager engineManager;

  late final HistoryService _history;
  late final MemoryService _memory;
  late final GoalService _goal;
  late LocalAgent _agent;
  late OpenAiCompatibleModelProvider _provider;

  /// The exact Ollama model tag currently loaded, used as the `model` field
  /// in chat requests -- Ollama requires an exact match, unlike llama-server
  /// which mostly ignored the `model` field in the request body.
  String? _activeModelTag;

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
        ? '${OllamaEngineManager.baseUrl}/v1'
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
    if (_lastEngineConfig != null) {
      // The remembered value is an Ollama tag (e.g. "gemma3:4b"), not a file
      // path -- validate it's still actually pulled rather than checking
      // the filesystem.
      final localModels = await engineManager.refreshLocalModels();
      if (!localModels.contains(_lastEngineConfig!.modelPath)) {
        _lastEngineConfig = null;
      }
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
      modelName: _activeModelTag ?? config.modelName,
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
    _sendTo(channel, _engineStatusPayload());

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
        _sendTo(channel, _engineStatusPayload());
        break;

      case 'sendMessage':
        final value = msg['value'] as String?;
        final attachment = msg['attachment'];
        String? finalValue = value;
        String? historyValue;
        List<String> imageDataUrls = const [];
        if (attachment is Map<String, dynamic>) {
          final fileName = (attachment['name'] as String?) ?? 'file';
          final content = (attachment['content'] as String?) ?? '';
          final isImage = attachment['isImage'] == true;
          if (isImage) {
            final activeTag = _activeModelTag ?? '';
            final supportsVision = activeTag.isNotEmpty && await engineManager.modelSupportsVision(activeTag);
            if (!supportsVision) {
              _broadcast({
                'type': 'error',
                'value': activeTag.isEmpty
                    ? 'No model is loaded, so the image could not be sent. Load a vision-capable model first (e.g. gemma3:4b).'
                    : 'The current model ("$activeTag") does not support images. Switch to a vision-capable model '
                        '(e.g. gemma3:4b) from the [Engine] panel and try again.',
              });
              break;
            }
            finalValue = (value != null && value.trim().isNotEmpty) ? value.trim() : 'Please analyze the attached image.';
            historyValue = '$finalValue\n\n[Attached image: $fileName]';
            imageDataUrls = [content];
          } else {
            finalValue = _composeMessageWithAttachment(value, fileName, content);
            historyValue = _composeAttachmentHistoryPlaceholder(value, fileName, content.length);
          }
        }
        if (finalValue != null && finalValue.trim().isNotEmpty) {
          await _handleSendMessage(
            finalValue.trim(),
            historyMessage: historyValue?.trim(),
            imageDataUrls: imageDataUrls,
          );
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
        _sendTo(channel, _engineStatusPayload());
        break;

      case 'downloadEngine':
        _engineState.status = EngineStatus.downloadingEngine;
        _broadcastEngineStatus();
        unawaited(_runDownloadEngine());
        break;

      case 'listLocalModels':
        unawaited(_refreshAndSendLocalModels(channel));
        break;

      case 'startEngine':
        final modelTag = msg['modelPath'] as String?;
        final requestedContextSize = msg['contextSize'];
        final contextSize = requestedContextSize is int
            ? requestedContextSize.clamp(512, 32768)
            : _engineState.contextSize;
        if (modelTag != null && modelTag.isNotEmpty) {
          unawaited(_runStartEngine(modelTag, contextSize));
        }
        break;

      case 'stopEngine':
        unawaited(_runStopEngine());
        break;

      case 'downloadModel':
        final tag = (msg['tag'] as String?) ?? (msg['url'] as String?);
        if (tag != null && tag.isNotEmpty) {
          unawaited(_runDownloadModel(tag));
        }
        break;

      case 'openModelsFolder':
        unawaited(_openInFileExplorer(engineManager.modelsDir));
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
  Future<String> _runAgentForTelegram(String message, {List<String> imageDataUrls = const []}) async {
    if (_wsDebug) {
      stdout.writeln('[agent][telegram] incoming: ${_truncateForLog(message)}${imageDataUrls.isNotEmpty ? ' (+${imageDataUrls.length} image)' : ''}');
    }
    if (config.engineMode == EngineMode.embedded &&
        _engineState.status != EngineStatus.ready) {
      return engineManager.isInstalled
          ? 'Ollama is installed but no model is loaded. Open the app and start a model from the [Engine] panel.'
          : 'Ollama is not installed. Open the app and install it from the [Engine] panel.';
    }

    if (imageDataUrls.isNotEmpty) {
      final activeTag = _activeModelTag ?? '';
      final supportsVision = activeTag.isNotEmpty && await engineManager.modelSupportsVision(activeTag);
      if (!supportsVision) {
        return activeTag.isEmpty
            ? 'No model is loaded, so the image could not be analyzed. Load a vision-capable model first (e.g. gemma3:4b or moondream:1.8b).'
            : 'The current model ("$activeTag") does not support images. Switch to a vision-capable model '
                '(e.g. gemma3:4b or moondream:1.8b) from the [Engine] panel and try again.';
      }
    }

    _cancelled = false;
    final storedMessage = imageDataUrls.isNotEmpty ? '$message\n\n[Attached image via Telegram]' : message;
    await _history.append('user', storedMessage);
    _broadcast({'type': 'sessionStart', 'userPrompt': storedMessage});

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
        imageDataUrls: imageDataUrls,
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

  Future<void> _refreshAndSendLocalModels(WebSocketChannel channel) async {
    final models = await engineManager.refreshLocalModels();
    _sendTo(channel, {'type': 'localModelsList', 'models': models});
  }

  /// "Downloading the engine" now means opening Ollama's download page --
  /// we don't silently fetch and run a third-party installer ourselves.
  /// Once the user installs it and comes back, [ensureRunning] picks it up.
  Future<void> _runDownloadEngine() async {
    try {
      if (!engineManager.isInstalled) {
        await engineManager.openDownloadPage();
        _engineState.status = EngineStatus.error;
        _engineState.statusMessage =
            'Opened the Ollama download page in your browser. Install it, then reopen this app.';
        _broadcastEngineStatus();
        return;
      }
      await engineManager.ensureRunning();
      await engineManager.refreshLocalModels();
      _engineState.status = EngineStatus.idle;
      _engineState.statusMessage = 'Ollama is running! Pull a model and click Run.';
    } catch (e) {
      _engineState.status = EngineStatus.error;
      _engineState.statusMessage = 'Failed to start Ollama: $e';
    }
    _broadcastEngineStatus();
  }

  Future<void> _runStartEngine(String modelTag, int contextSize) async {
    _engineState.status = EngineStatus.starting;
    _engineState.statusMessage = 'Loading $modelTag...';
    _engineState.activeModelPath = modelTag;
    _engineState.contextSize = contextSize;
    _broadcastEngineStatus();
    try {
      await engineManager.runModel(modelTag, contextSize: contextSize);
      _activeModelTag = modelTag;
      _activeEndpoint = '${OllamaEngineManager.baseUrl}/v1';
      _rebuildAgent();
      _engineState.status = EngineStatus.ready;
      _engineState.statusMessage = 'Engine ready! Start chatting.';
      _lastEngineConfig = LastEngineConfig(modelPath: modelTag, contextSize: contextSize);
      unawaited(_lastEngineService.save(_lastEngineConfig!));
    } catch (e) {
      _engineState.status = EngineStatus.error;
      _engineState.statusMessage = 'Engine start failed: $e';
    }
    _broadcastEngineStatus();
  }

  Future<void> _runDownloadModel(String tag) async {
    _engineState.status = EngineStatus.downloadingModel;
    _engineState.statusMessage = 'Pulling $tag...';
    _broadcastEngineStatus();
    try {
      await engineManager.pullModel(
        tag,
        onProgress: (status, completed, total) {
          final pct = (total != null && total > 0 && completed != null) ? ' (${completed * 100 ~/ total}%)' : '';
          _engineState.statusMessage = '$status$pct';
          _broadcastEngineStatus();
        },
      );
      _engineState.status = EngineStatus.idle;
      _engineState.statusMessage = '$tag pulled!';
    } catch (e) {
      _engineState.status = EngineStatus.error;
      _engineState.statusMessage = 'Model pull failed: $e';
    }

    _broadcastEngineStatus();
    // Refresh model list after pulling
    _broadcast({
      'type': 'localModelsList',
      'models': await engineManager.refreshLocalModels(),
    });
  }

  Future<void> _runStopEngine() async {
    await engineManager.stopModel();
    _activeModelTag = null;
    _engineState.status = EngineStatus.idle;
    _engineState.serverPort = null;
    _engineState.activeModelPath = null;
    _engineState.statusMessage = engineManager.isInstalled
        ? 'Model unloaded.'
        : 'Ollama is not installed.';
    _broadcastEngineStatus();
  }

  void _broadcastEngineStatus() {
    _broadcast(_engineStatusPayload());
  }

  /// The engine that actually runs the LLM: a local Ollama server (embedded
  /// mode) or an external OpenAI-compatible server the user pointed the app
  /// at via NORITER_MODEL_ENDPOINT. Surfaced to the UI so "what's running
  /// this?" and "where are the model files?" are visible instead of implicit.
  String get _engineBackendLabel => config.engineMode == EngineMode.embedded
      ? 'Ollama (${OllamaEngineManager.baseUrl}, embedded)'
      : 'External OpenAI-compatible server (${config.modelEndpoint})';

  Map<String, dynamic> _engineStatusPayload() => {
        'type': 'engineStatus',
        'state': _engineState.toJson(),
        'isInstalled': engineManager.isInstalled,
        'localModels': engineManager.listLocalModels(),
        'recommendedModels': OllamaEngineManager.recommendedModels,
        'activeModelPath': engineManager.activeModelPath,
        'engineBackend': _engineBackendLabel,
        'modelsDir': engineManager.modelsDir,
        'engineDir': engineManager.engineDir,
      };

  /// Opens a local folder in the OS file explorer (Windows Explorer). Purely
  /// a UI convenience for "폴더에서 보기" -- failures are non-fatal, just
  /// surfaced as an engine status message.
  Future<void> _openInFileExplorer(String path) async {
    try {
      await Directory(path).create(recursive: true);
      await Process.start('explorer', [path]);
    } catch (e) {
      _engineState.statusMessage = 'Failed to open folder: $e';
      _broadcastEngineStatus();
    }
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

  Future<void> _handleSendMessage(
    String message, {
    String? historyMessage,
    List<String> imageDataUrls = const [],
  }) async {
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
        '- Ollama: $installed',
        '- Status: $status',
        '- Active model: $activeModel',
        '- Local models:',
        ...modelLines,
        '',
        'Use the [Engine] button in the header to pull and run a model.',
      ].join('\n');
      await _history.append('assistant', response);
      _broadcast({'type': 'finalAnswer', 'value': response});
      return;
    }

    // Guard: in embedded mode, refuse chat until engine is ready
    if (config.engineMode == EngineMode.embedded &&
        _engineState.status != EngineStatus.ready) {
      final hint = engineManager.isInstalled
          ? 'Ollama is installed but no model is loaded.\nOpen the [Engine] panel, select a model, and click Run.'
          : 'Ollama is not installed.\nOpen the [Engine] panel to install Ollama and pull a model.';
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
        imageDataUrls: imageDataUrls,
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
