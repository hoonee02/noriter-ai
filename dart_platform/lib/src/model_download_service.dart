import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Downloads GGUF model files from HuggingFace or any direct URL.
class ModelDownloadService {
  ModelDownloadService({String? modelsDir})
      : modelsDir = modelsDir ?? _defaultModelsDir();

  final String modelsDir;

  static String _defaultModelsDir() {
    final appData = Platform.environment['APPDATA'] ??
        p.join(
          Platform.environment['USERPROFILE'] ?? '',
          'AppData',
          'Roaming',
        );
    return p.join(appData, 'noriter-ai', 'models');
  }

  /// Downloads a model file from [url] to [modelsDir].
  /// Returns the saved file path.
  Future<String> downloadModel(
    String url, {
    String? saveName,
    void Function(int received, int total)? onProgress,
  }) async {
    await Directory(modelsDir).create(recursive: true);

    final filename = saveName ?? _filenameFromUrl(url);
    final savePath = p.join(modelsDir, filename);

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers['User-Agent'] = 'noriter-ai/1.0';
      final streamed = await client.send(request);

      if (streamed.statusCode >= 300) {
        throw Exception('HTTP ${streamed.statusCode}: $url');
      }

      final total = streamed.contentLength ?? 0;
      final sink = File(savePath).openWrite();
      int received = 0;

      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }

    return savePath;
  }

  String _filenameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      if (segments.isNotEmpty) {
        final last = segments.last;
        if (last.isNotEmpty) return last;
      }
    } catch (_) {}
    return 'model_${DateTime.now().millisecondsSinceEpoch}.gguf';
  }

  /// Recommended free models.
  static const List<Map<String, String>> recommendedModels = [
    {
      'name': 'Qwen2.5-0.5B-Instruct (500MB, ultra-light)',
      'url':
          'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
      'filename': 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
    },
    {
      'name': 'Llama-3.2-1B-Instruct (0.8GB)',
      'url':
          'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      'filename': 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
    },
    {
      'name': 'Phi-3-mini-4k-instruct (2.2GB)',
      'url':
          'https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q4_K_M.gguf',
      'filename': 'Phi-3-mini-4k-instruct-Q4_K_M.gguf',
    },
    {
      'name': 'Gemma-2-2B-Instruct (1.6GB)',
      'url':
          'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
      'filename': 'gemma-2-2b-it-Q4_K_M.gguf',
    },
  ];
}
