import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Drives a local Ollama installation instead of a bundled llama.cpp binary.
/// Ollama handles GGUF conversion, quantization and its own model registry
/// internally, so all this class does is: check it's installed, make sure
/// `ollama serve` is running, and talk to its HTTP API (default
/// `http://127.0.0.1:11434`) to list/pull/warm-up models. Actual chat
/// requests go straight to Ollama's OpenAI-compatible `/v1` route via the
/// existing LocalAgent/OpenAiCompatibleModelProvider -- no separate client
/// needed here.
class OllamaEngineManager {
  OllamaEngineManager();

  static const String baseUrl = 'http://127.0.0.1:11434';
  static const String downloadPageUrl = 'https://ollama.com/download';

  Process? _serveProcess;
  String? _activeModel;
  String? _cachedExePath;

  String get modelsDir => p.join(
        Platform.environment['USERPROFILE'] ?? '',
        '.ollama',
        'models',
      );

  /// There is no separate "engine directory" for Ollama the way there was
  /// for the llama.cpp binary -- it's a single installed application. Kept
  /// as an alias so callers that generically show "where files live" still
  /// have something sensible to point at.
  String get engineDir => modelsDir;

  String? get activeModel => _activeModel;
  String? get activeModelPath => _activeModel;

  bool get isInstalled => _findOllamaExe() != null;

  String? _findOllamaExe() {
    if (_cachedExePath != null) return _cachedExePath;

    final candidates = <String>[
      p.join(Platform.environment['LOCALAPPDATA'] ?? '', 'Programs', 'Ollama', 'ollama.exe'),
      p.join(Platform.environment['ProgramFiles'] ?? '', 'Ollama', 'ollama.exe'),
    ];
    for (final candidate in candidates) {
      if (candidate.isNotEmpty && File(candidate).existsSync()) {
        _cachedExePath = candidate;
        return candidate;
      }
    }

    try {
      final result = Process.runSync('where', ['ollama']);
      if (result.exitCode == 0) {
        final firstLine = (result.stdout as String).split(RegExp(r'\r?\n')).first.trim();
        if (firstLine.isNotEmpty) {
          _cachedExePath = firstLine;
          return firstLine;
        }
      }
    } catch (_) {}

    return null;
  }

  Future<bool> isRunning() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/tags')).timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Starts `ollama serve` if it isn't already running, and waits for its
  /// API to answer (up to 30s).
  Future<void> ensureRunning() async {
    if (await isRunning()) return;

    final exe = _findOllamaExe();
    if (exe == null) {
      throw Exception(
          'Ollama executable not found. Click [Install Ollama] to download it from $downloadPageUrl, '
          'then restart this app.');
    }

    _serveProcess = await Process.start(exe, ['serve']);
    _serveProcess!.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen((s) => stdout.write('[ollama] $s'));
    _serveProcess!.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((s) => stderr.write('[ollama] $s'));

    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (await isRunning()) return;
    }
    throw Exception('Ollama server did not respond within 30 seconds.');
  }

  /// Opens the Ollama download page in the default browser. We deliberately
  /// don't silently download/run a third-party installer ourselves --
  /// installing software is something the user should see and approve.
  Future<void> openDownloadPage() async {
    await Process.start('cmd', ['/c', 'start', downloadPageUrl]);
  }

  List<String> listLocalModels() {
    // Kept synchronous-looking for API parity with the old manager, but the
    // real data comes from Ollama's HTTP API, which is inherently async.
    // Callers that need this synchronously (engineStatusPayload) get the
    // last cached list instead; see [refreshLocalModels].
    return _cachedModels;
  }

  List<String> _cachedModels = [];

  Future<List<String>> refreshLocalModels() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/tags')).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return _cachedModels;
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final models = decoded['models'] as List<dynamic>? ?? [];
      _cachedModels = models
          .whereType<Map<String, dynamic>>()
          .map((m) => m['name'] as String? ?? m['model'] as String? ?? '')
          .where((name) => name.isNotEmpty)
          .toList()
        ..sort();
      return _cachedModels;
    } catch (_) {
      return _cachedModels;
    }
  }

  /// Pulls (downloads) a model by its Ollama tag (e.g. "gemma3:4b"),
  /// reporting streamed NDJSON progress lines from Ollama's /api/pull.
  Future<void> pullModel(
    String tag, {
    void Function(String status, int? completed, int? total)? onProgress,
  }) async {
    await ensureRunning();

    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse('$baseUrl/api/pull'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({'name': tag});
      final streamed = await client.send(request);

      if (streamed.statusCode != 200) {
        final body = await streamed.stream.bytesToString();
        throw Exception('HTTP ${streamed.statusCode}: $body');
      }

      await for (final line in streamed.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        try {
          final obj = jsonDecode(line) as Map<String, dynamic>;
          if (obj['error'] != null) {
            throw Exception(obj['error']);
          }
          onProgress?.call(
            obj['status'] as String? ?? '',
            obj['completed'] as int?,
            obj['total'] as int?,
          );
        } catch (e) {
          if (e is FormatException) continue;
          rethrow;
        }
      }
    } finally {
      client.close();
    }

    await refreshLocalModels();
  }

  /// Ollama loads models into memory on demand rather than needing an
  /// explicit "start" step, so this just makes sure the server is up and
  /// warms the model with an empty generate call -- the same `options`
  /// (context size) used here are what subsequent /v1/chat/completions
  /// calls for this model will keep using while it stays loaded.
  Future<void> runModel(String tag, {int? contextSize}) async {
    await ensureRunning();

    final body = <String, dynamic>{
      'model': tag,
      'prompt': '',
      'stream': false,
      if (contextSize != null) 'options': {'num_ctx': contextSize},
    };

    final response = await http
        .post(
          Uri.parse('$baseUrl/api/generate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      throw Exception('Failed to load model "$tag": HTTP ${response.statusCode} ${response.body}');
    }

    _activeModel = tag;
  }

  /// Asks Ollama to unload the active model immediately (keep_alive: 0)
  /// instead of killing a subprocess, since Ollama itself keeps running.
  Future<void> stopModel() async {
    if (_activeModel == null) return;
    try {
      await http
          .post(
            Uri.parse('$baseUrl/api/generate'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'model': _activeModel, 'prompt': '', 'keep_alive': 0}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
    _activeModel = null;
  }

  /// Recommended Ollama model tags, reworked around the Gemma 3 generation
  /// (see model_download_service.dart's prior GGUF equivalents -- same
  /// lineup, just referenced by Ollama registry tag instead of a GGUF URL).
  ///
  /// The two EXAONE entries were sized for a GTX 1660 (6GB VRAM) + 32GB
  /// system RAM machine: 2.4b comfortably fits fully in VRAM, and 7.8b's
  /// ~4.8GB Q4 quant fits within 6GB VRAM with headroom (any overflow layers
  /// offload to the 32GB of system RAM without issue).
  static const List<Map<String, String>> recommendedModels = [
    {'name': 'Gemma-3-1B-Instruct (fastest, low RAM)', 'tag': 'gemma3:1b'},
    {'name': 'Llama-3.2-1B-Instruct (alternative to Gemma-3-1B)', 'tag': 'llama3.2:1b'},
    {'name': 'Gemma-3-4B-Instruct (best overall quality/speed, image-capable)', 'tag': 'gemma3:4b'},
    {'name': 'Phi-3-mini (quality alternative)', 'tag': 'phi3:mini'},
    {'name': 'EXAONE-3.5-2.4B-Instruct (LG, Korean+English, light)', 'tag': 'exaone3.5:2.4b'},
    {'name': 'EXAONE-3.5-7.8B-Instruct (LG, fits GTX 1660 6GB VRAM comfortably)', 'tag': 'exaone3.5:7.8b'},
  ];
}
