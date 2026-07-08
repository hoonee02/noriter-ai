import 'dart:io';

class AppConfig {
  AppConfig({
    required this.workspacePath,
    required this.modelEndpoint,
    required this.apiKey,
    required this.modelName,
    this.port = 3742,
  });

  final String workspacePath;
  final String modelEndpoint;
  final String apiKey;
  final String modelName;
  final int port;

  factory AppConfig.fromEnvironment({required String workspacePath}) {
    final endpoint = Platform.environment['NORITER_MODEL_ENDPOINT'] ??
        'http://localhost:1234/v1';
    final apiKey = Platform.environment['NORITER_MODEL_API_KEY'] ?? 'local';
    final modelName =
        Platform.environment['NORITER_MODEL_NAME'] ?? 'local-model';
    final portStr = Platform.environment['NORITER_PORT'] ?? '3742';
    final port = int.tryParse(portStr) ?? 3742;

    return AppConfig(
      workspacePath: workspacePath,
      modelEndpoint: endpoint,
      apiKey: apiKey,
      modelName: modelName,
      port: port,
    );
  }
}
