import 'dart:convert';
import 'dart:io';

class TelegramConfig {
  TelegramConfig({
    this.botToken = '',
    this.chatId = '',
    this.enabled = false,
  });

  String botToken;
  String chatId;
  bool enabled;

  Map<String, dynamic> toJson() => {
        'botToken': botToken,
        'chatId': chatId,
        'enabled': enabled,
      };

  factory TelegramConfig.fromJson(Map<String, dynamic> j) => TelegramConfig(
        botToken: (j['botToken'] as String?) ?? '',
        chatId: (j['chatId'] as String?) ?? '',
        enabled: (j['enabled'] as bool?) ?? false,
      );

  /// Redacted view safe to send to the web UI (never echoes the full token back).
  Map<String, dynamic> toPublicJson() => {
        'botTokenSet': botToken.isNotEmpty,
        'botTokenPreview': botToken.isEmpty
            ? ''
            : '${botToken.substring(0, botToken.length > 6 ? 6 : botToken.length)}...',
        'chatId': chatId,
        'enabled': enabled,
      };
}

/// Persists Telegram bridge settings under the workspace's .noriter-ai dir.
class TelegramConfigService {
  TelegramConfigService({required this.workspaceRoot});

  final String workspaceRoot;

  String get _path => '$workspaceRoot/.noriter-ai/telegram-config.json';

  void _ensureDir() {
    final dir = Directory('$workspaceRoot/.noriter-ai');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  Future<TelegramConfig> load() async {
    final file = File(_path);
    if (!file.existsSync()) {
      return TelegramConfig();
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return TelegramConfig.fromJson(decoded);
      }
    } catch (_) {}
    return TelegramConfig();
  }

  Future<void> save(TelegramConfig config) async {
    _ensureDir();
    await File(_path).writeAsString(jsonEncode(config.toJson()));
  }
}
