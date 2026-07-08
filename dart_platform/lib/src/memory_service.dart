import 'dart:io';

class MemoryService {
  MemoryService({required this.workspaceRoot});

  final String workspaceRoot;

  String get _memoryPath => '$workspaceRoot/.noriter-ai/agent-memory.md';

  void _ensureDir() {
    final dir = Directory('$workspaceRoot/.noriter-ai');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  String _defaultMarkdown([Map<String, String>? memory]) {
    final entries = (memory ?? <String, String>{}).entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final lines = [
      '# Noriter AI Memory',
      '',
      'Use this file to store persistent agent memory for this workspace.',
      'Format: - `key`: value',
      '',
      '## Entries',
    ];
    if (entries.isEmpty) {
      lines.add('- `example-key`: example value');
    } else {
      for (final e in entries) {
        lines.add('- `${e.key}`: ${e.value}');
      }
    }
    lines.add('');
    return lines.join('\n');
  }

  Map<String, String> _parse(String content) {
    final result = <String, String>{};
    for (final line in content.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      var match = RegExp(r'^-\s*`([^`]+)`\s*:\s*(.+)$').firstMatch(trimmed);
      match ??= RegExp(r'^-\s*([a-zA-Z0-9._-]+)\s*:\s*(.+)$').firstMatch(trimmed);
      if (match != null) {
        final key = match.group(1)!.trim();
        final value = match.group(2)!.trim();
        if (key.isNotEmpty && value.isNotEmpty) {
          result[key] = value;
        }
      }
    }
    return result;
  }

  String _ensureFile() {
    _ensureDir();
    final file = File(_memoryPath);
    if (!file.existsSync()) {
      file.writeAsStringSync(_defaultMarkdown());
    }
    return _memoryPath;
  }

  Map<String, String> _load() {
    _ensureFile();
    try {
      final raw = File(_memoryPath).readAsStringSync();
      return _parse(raw);
    } catch (_) {
      return {};
    }
  }

  void _save(Map<String, String> memory) {
    _ensureFile();
    File(_memoryPath).writeAsStringSync(_defaultMarkdown(memory));
  }

  String loadMemory() {
    return File(_ensureFile()).readAsStringSync();
  }

  String saveMemory(String key, String value) {
    final memory = _load();
    memory[key] = value;
    _save(memory);
    return 'Memory saved: $key';
  }

  String getMemory(String key) {
    final memory = _load();
    final value = memory[key];
    if (value == null) return 'Memory not found for key: $key';
    return '$key: $value';
  }

  String listKeys() {
    final memory = _load();
    final keys = memory.keys.toList()..sort();
    if (keys.isEmpty) return 'No memory keys found.';
    return keys.join('\n');
  }

  String deleteMemory(String key) {
    final memory = _load();
    if (!memory.containsKey(key)) return 'Memory not found for key: $key';
    memory.remove(key);
    _save(memory);
    return 'Memory deleted: $key';
  }

  String getSummary({int maxEntries = 20}) {
    final memory = _load();
    if (memory.isEmpty) return 'No saved memory entries.';
    final entries = memory.entries.toList();
    final shown = entries.take(maxEntries).toList();
    final lines = shown.map((e) => '- ${e.key}: ${e.value}').toList();
    final omitted = entries.length - shown.length;
    if (omitted > 0) lines.add('- ...and $omitted more entries');
    return lines.join('\n');
  }
}
