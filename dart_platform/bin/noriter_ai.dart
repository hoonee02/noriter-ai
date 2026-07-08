import 'dart:convert';
import 'dart:io';

import 'package:noriter_ai_desktop/src/agent_app.dart';
import 'package:noriter_ai_desktop/src/config.dart';
import 'package:noriter_ai_desktop/src/model_provider.dart';
import 'package:noriter_ai_desktop/src/plan_logger.dart';

Future<void> main(List<String> args) async {
  final workspacePath = _resolveWorkspace(args);
  final config = AppConfig.fromEnvironment(workspacePath: workspacePath);
  final logger = PlanLogger(workspacePath: workspacePath);
  final provider = OpenAiCompatibleModelProvider(
    endpoint: config.modelEndpoint,
    apiKey: config.apiKey,
  );

  await logger.appendEntry(
    task: 'Dart platform bootstrap run',
    location: workspacePath,
    summary: 'CLI app started. Provider endpoint: ${config.modelEndpoint}',
  );

  final app = AgentApp(
    config: config,
    provider: provider,
    logger: logger,
  );

  stdout.writeln('Noriter AI Dart Platform');
  stdout.writeln('Workspace: $workspacePath');
  stdout.writeln('Model endpoint: ${config.modelEndpoint}');
  stdout.writeln('Commands: /models, /log <text>, /help, /exit');

  await app.run();
}

String _resolveWorkspace(List<String> args) {
  if (args.isNotEmpty && args.first.trim().isNotEmpty) {
    return args.first.trim();
  }

  final cwd = Directory.current.path;
  final normalized = cwd.replaceAll('\\', '/');
  if (normalized.endsWith('/dart_platform')) {
    return Directory.current.parent.path;
  }
  return cwd;
}
