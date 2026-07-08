import 'dart:io';

class GoalService {
  GoalService({required this.workspaceRoot});

  final String workspaceRoot;

  String get _goalPath => '$workspaceRoot/.noriter-ai/agent-goal.md';

  void _ensureDir() {
    final dir = Directory('$workspaceRoot/.noriter-ai');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  String _defaultGoal() {
    return [
      '# Noriter AI Agent Goal',
      '',
      "Define the agent's objective for this workspace.",
      'Everything in this file is injected into the agent system prompt at runtime.',
      '',
      '## Goal',
      '- Prioritize safe, minimal, and verifiable code changes.',
      '- Prefer workspace conventions and preserve existing style.',
      '- When unsure, gather context first and avoid destructive actions.',
      '',
    ].join('\n');
  }

  String ensureGoalFile() {
    _ensureDir();
    final file = File(_goalPath);
    if (!file.existsSync()) {
      file.writeAsStringSync(_defaultGoal());
    }
    return _goalPath;
  }

  String getGoal() {
    ensureGoalFile();
    try {
      final content = File(_goalPath).readAsStringSync().trim();
      return content.isNotEmpty ? content : 'No custom goal defined.';
    } catch (_) {
      return 'No custom goal defined.';
    }
  }

  void updateGoal(String text) {
    ensureGoalFile();
    final normalized = text.trim();
    final body = normalized
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) => '- $l')
        .join('\n');

    final content = [
      '# Noriter AI Agent Goal',
      '',
      "Define the agent's objective for this workspace.",
      'Everything in this file is injected into the agent system prompt at runtime.',
      '',
      '## Goal',
      body.isEmpty ? '- No custom goal set.' : body,
      '',
    ].join('\n');

    File(_goalPath).writeAsStringSync(content);
  }
}
