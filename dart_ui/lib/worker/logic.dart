/// Pure business-logic functions that run inside the Web Worker, off the
/// main/UI thread -- no DOM, no Tauri IPC (neither is available inside a
/// worker). The worker only transforms JSON in and JSON out; the main
/// thread (lib/main.dart) owns rendering and all `window.__TAURI__` calls.
library;

Map<String, dynamic> handle(String type, Map<String, dynamic> payload) {
  switch (type) {
    case 'formatMessage':
      return _formatMessage(payload);
    case 'buildOllamaRequest':
      return _buildOllamaRequest(payload);
    default:
      return {'error': 'unknown message type: $type'};
  }
}

/// Telegram/chat message formatting: generation timestamp + token/time
/// stats line, and HTML-escaping of the message text.
Map<String, dynamic> _formatMessage(Map<String, dynamic> p) {
  final text = p['text'] as String? ?? '';
  final tokensUsed = (p['tokensUsed'] as num?)?.toInt();
  final elapsedMs = (p['elapsedMs'] as num?)?.toInt();

  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final time =
      '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}:${two(now.second)}';

  final statsParts = <String>[
    if (tokensUsed != null) '$tokensUsed tokens',
    if (elapsedMs != null) '${(elapsedMs / 1000).toStringAsFixed(1)}s',
  ];
  final meta = statsParts.isEmpty ? time : '$time · ${statsParts.join(' · ')}';

  final escapedText =
      text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  return {'escapedText': escapedText, 'time': time, 'meta': meta};
}

/// Ollama request preprocessing: trims the prompt, falls back to a default
/// model if none was picked, and clamps context size to Ollama's valid
/// range -- the same validation the old Dart server used to do before
/// forwarding a request to the engine.
Map<String, dynamic> _buildOllamaRequest(Map<String, dynamic> p) {
  final model = (p['model'] as String?)?.trim();
  final prompt = (p['prompt'] as String?)?.trim() ?? '';
  final numCtx = (p['numCtx'] as num?)?.toInt() ?? 4096;

  return {
    'model': (model == null || model.isEmpty) ? 'gemma3:4b' : model,
    'prompt': prompt,
    'numCtx': numCtx.clamp(512, 32768),
  };
}
