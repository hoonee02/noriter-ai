import 'dart:io';

import 'package:noriter_ai_desktop/src/config.dart';
import 'package:noriter_ai_desktop/src/model_provider.dart';
import 'package:noriter_ai_desktop/src/plan_logger.dart';

class AgentApp {
  AgentApp({
    required this.config,
    required this.provider,
    required this.logger,
  });

  final AppConfig config;
  final ModelProvider provider;
  final PlanLogger logger;

  Future<void> run() async {
    while (true) {
      stdout.write('> ');
      final input = stdin.readLineSync();
      if (input == null) {
        break;
      }

      final trimmed = input.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      if (trimmed == '/exit') {
        stdout.writeln('Bye.');
        break;
      }

      if (trimmed == '/help') {
        stdout.writeln('Available commands:');
        stdout.writeln('- /models : list available models from endpoint');
        stdout.writeln('- /log <text> : append manual project log entry');
        stdout.writeln('- /exit : terminate app');
        continue;
      }

      if (trimmed == '/models') {
        await _handleModels();
        continue;
      }

      if (trimmed.startsWith('/log ')) {
        await _handleLog(trimmed.substring(5).trim());
        continue;
      }

      stdout.writeln(
        'Message mode is not implemented yet. Use /models, /log <text>, or /help.',
      );
    }
  }

  Future<void> _handleModels() async {
    try {
      final models = await provider.listModels();
      if (models.isEmpty) {
        stdout.writeln('No models reported by endpoint.');
      } else {
        stdout.writeln('Available models:');
        for (final model in models) {
          stdout.writeln('- $model');
        }
      }
      await logger.appendEntry(
        task: 'List models',
        location: config.workspacePath,
        summary: models.isEmpty
            ? 'No models reported by endpoint.'
            : 'Model count: ${models.length}',
      );
    } catch (error) {
      stdout.writeln('Model listing failed: $error');
      await logger.appendEntry(
        task: 'List models',
        location: config.workspacePath,
        summary: 'Model listing failed: $error',
      );
    }
  }

  Future<void> _handleLog(String text) async {
    if (text.isEmpty) {
      stdout.writeln('Usage: /log <text>');
      return;
    }

    await logger.appendEntry(
      task: 'Manual note',
      location: config.workspacePath,
      summary: text,
    );
    stdout.writeln('Log entry appended.');
  }
}
