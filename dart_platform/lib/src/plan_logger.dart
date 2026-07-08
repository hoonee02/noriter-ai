import 'dart:io';

class PlanLogger {
  PlanLogger({required this.workspacePath});

  final String workspacePath;

  String get _logFilePath => '$workspacePath\\.noriter-ai\\project-plan-log.md';

  Future<void> appendEntry({
    required String task,
    required String location,
    required String summary,
  }) async {
    final logFile = File(_logFilePath);
    final logDir = logFile.parent;
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }

    if (!await logFile.exists()) {
      await logFile.writeAsString(
        '# Noriter AI Project Plan Log\n\n',
        mode: FileMode.write,
      );
    }

    final now = DateTime.now();
    final timestamp = _formatTimestamp(now);
    final block = StringBuffer()
      ..writeln('## $timestamp')
      ..writeln('- Task: $task')
      ..writeln('- Location: $location')
      ..writeln('- Summary: $summary')
      ..writeln();

    await logFile.writeAsString(
      block.toString(),
      mode: FileMode.append,
    );
  }

  String _formatTimestamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }
}
