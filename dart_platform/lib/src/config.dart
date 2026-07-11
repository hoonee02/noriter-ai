import 'dart:io';

import 'package:noriter_ai_desktop/src/engine_state.dart';

class AppConfig {
  AppConfig({
    required this.workspacePath,
    required this.modelEndpoint,
    required this.apiKey,
    required this.modelName,
    required this.engineMode,
    this.port = 3742,
  });

  final String workspacePath;
  final String modelEndpoint;
  final String apiKey;
  final String modelName;
  final int port;
  final EngineMode engineMode;

  factory AppConfig.fromEnvironment({required String workspacePath}) {
    final envEndpoint = Platform.environment['NORITER_MODEL_ENDPOINT'];
    // Treat absent or default LM Studio endpoint as embedded mode
    final isEmbedded = envEndpoint == null ||
        envEndpoint.isEmpty ||
        envEndpoint == 'http://localhost:1234/v1';
    final engineMode =
        isEmbedded ? EngineMode.embedded : EngineMode.external;
    final endpoint =
        isEmbedded ? 'http://127.0.0.1:11434/v1' : envEndpoint;

    final apiKey = Platform.environment['NORITER_MODEL_API_KEY'] ?? 'ollama';
    final modelName =
        Platform.environment['NORITER_MODEL_NAME'] ?? 'local-model';
    final portStr = Platform.environment['NORITER_PORT'] ?? '3742';
    final port = int.tryParse(portStr) ?? 3742;

    return AppConfig(
      workspacePath: workspacePath,
      modelEndpoint: endpoint,
      apiKey: apiKey,
      modelName: modelName,
      engineMode: engineMode,
      port: port,
    );
  }
}
