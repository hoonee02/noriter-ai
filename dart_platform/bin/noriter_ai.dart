import 'dart:async';
import 'dart:io';

import 'package:noriter_ai_desktop/src/config.dart';
import 'package:noriter_ai_desktop/src/engine_state.dart';
import 'package:noriter_ai_desktop/src/llama_engine_manager.dart';
import 'package:noriter_ai_desktop/src/server.dart';

Future<void> main(List<String> args) async {
  final workspacePath = _resolveWorkspace(args);
  final config = AppConfig.fromEnvironment(workspacePath: workspacePath);
  final engineManager = LlamaEngineManager();

  stdout.writeln('Noriter AI Desktop');
  stdout.writeln('Workspace: $workspacePath');
  stdout.writeln('Mode: ${config.engineMode == EngineMode.embedded ? "embedded (llama.cpp)" : "external (${config.modelEndpoint})"}');
  stdout.writeln('Starting server on port ${config.port}...');

  final server = NoriterServer(config: config, engineManager: engineManager);
  await server.start();

  // Open browser automatically
  await Process.run('cmd', ['/c', 'start', 'http://localhost:${config.port}']);

  // Keep the server alive indefinitely
  await Completer<void>().future;
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

