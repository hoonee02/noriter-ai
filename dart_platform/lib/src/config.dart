import 'dart:io';

class AppConfig {
  AppConfig({
    required this.workspacePath,
    required this.modelEndpoint,
    required this.apiKey,
    required this.modelName,
  });

  final String workspacePath;
  final String modelEndpoint;
  final String apiKey;
  final String modelName;

  factory AppConfig.fromEnvironment({required String workspacePath}) {
    final endpoint = Platform.environment['NORITER_MODEL_ENDPOINT'] ??
        'http://localhost:1234/v1';
    final apiKey = Platform.environment['NORITER_MODEL_API_KEY'] ?? 'local';
    final modelName =
        Platform.environment['NORITER_MODEL_NAME'] ?? 'local-model';

    return AppConfig(
      workspacePath: workspacePath,
      modelEndpoint: endpoint,
      apiKey: apiKey,
      modelName: modelName,
    );
  }
}
