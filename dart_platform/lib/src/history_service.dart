import 'dart:convert';
import 'dart:io';

class ChatEntry {
  ChatEntry({required this.type, required this.text, required this.timestamp});

  final String type;
  final String text;
  final int timestamp;

  Map<String, dynamic> toJson() => {
        'type': type,
        'text': text,
        'timestamp': timestamp,
      };

  factory ChatEntry.fromJson(Map<String, dynamic> j) => ChatEntry(
        type: j['type'] as String,
        text: j['text'] as String,
        timestamp: (j['timestamp'] as num).toInt(),
      );
}

class HistoryService {
  HistoryService({required this.workspaceRoot, this.maxEntries = 300, this.maxContextMessages = 20});

  final String workspaceRoot;
  final int maxEntries;
  final int maxContextMessages;

  String get _historyPath => '$workspaceRoot/.noriter-ai/chat-history.json';

  List<ChatEntry> _history = [];

  void _ensureDir() {
    final dir = Directory('$workspaceRoot/.noriter-ai');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  Future<void> load() async {
    _ensureDir();
    final file = File(_historyPath);
    if (!file.existsSync()) {
      _history = [];
      return;
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _history = decoded
            .whereType<Map<String, dynamic>>()
            .where((e) => e['type'] is String && e['text'] is String)
            .map(ChatEntry.fromJson)
            .toList();
      }
    } catch (_) {
      _history = [];
    }
    _trim();
  }

  Future<void> _persist() async {
    _ensureDir();
    await File(_historyPath)
        .writeAsString(jsonEncode(_history.map((e) => e.toJson()).toList()));
  }

  void _trim() {
    if (_history.length > maxEntries) {
      _history = _history.sublist(_history.length - maxEntries);
    }
  }

  Future<void> append(String type, String text) async {
    _history.add(ChatEntry(type: type, text: text, timestamp: DateTime.now().millisecondsSinceEpoch));
    _trim();
    await _persist();
  }

  Future<void> clear() async {
    _history = [];
    await _persist();
  }

  List<Map<String, dynamic>> getEntries() =>
      _history.map((e) => e.toJson()).toList();

  List<Map<String, String>> buildContextMessages() {
    final conversational = _history.where((e) => e.type == 'user' || e.type == 'assistant').toList();
    final sliced = conversational.length > maxContextMessages
        ? conversational.sublist(conversational.length - maxContextMessages)
        : conversational;
    return sliced.map((e) => {'role': e.type, 'content': e.text}).toList();
  }
}
