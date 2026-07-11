import 'dart:convert';
import 'dart:io';

class LastEngineConfig {
  LastEngineConfig({required this.modelPath, required this.contextSize});

  final String modelPath;
  final int contextSize;

  Map<String, dynamic> toJson() => {
        'modelPath': modelPath,
        'contextSize': contextSize,
      };

  factory LastEngineConfig.fromJson(Map<String, dynamic> j) => LastEngineConfig(
        modelPath: (j['modelPath'] as String?) ?? '',
        contextSize: (j['contextSize'] as num?)?.toInt() ?? 4096,
      );
}

/// Remembers the most recently started llama-server model + context size so
/// the app can offer to relaunch it automatically on the next startup.
class LastEngineService {
  LastEngineService({required this.workspaceRoot});

  final String workspaceRoot;

  String get _path => '$workspaceRoot/.noriter-ai/last-engine.json';

  void _ensureDir() {
    final dir = Directory('$workspaceRoot/.noriter-ai');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  Future<LastEngineConfig?> load() async {
    final file = File(_path);
    if (!file.existsSync()) return null;
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final config = LastEngineConfig.fromJson(decoded);
        if (config.modelPath.isEmpty) return null;
        return config;
      }
    } catch (_) {}
    return null;
  }

  Future<void> save(LastEngineConfig config) async {
    _ensureDir();
    await File(_path).writeAsString(jsonEncode(config.toJson()));
  }
}
