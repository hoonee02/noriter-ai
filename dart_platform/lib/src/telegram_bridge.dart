import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

typedef TelegramMessageHandler = Future<String> Function(String text);
typedef TelegramStatusCallback = void Function(String status);
typedef TelegramChatBoundCallback = void Function(String chatId);

/// Long-polls the Telegram Bot API and forwards incoming messages from the
/// configured chat to [onMessage], sending the returned text back as a reply.
///
/// If no chat ID is configured, the bridge auto-binds to whichever chat
/// sends the first message (typical for a single-user personal bot), and
/// reports the discovered ID via [onChatBound] so it can be persisted.
class TelegramBridge {
  TelegramBridge({
    required this.onMessage,
    this.onStatus,
    this.onChatBound,
  });

  final TelegramMessageHandler onMessage;
  final TelegramStatusCallback? onStatus;
  final TelegramChatBoundCallback? onChatBound;

  String _botToken = '';
  String _allowedChatId = '';
  bool _running = false;
  int _updateOffset = 0;

  bool get isRunning => _running;

  void start(String botToken, String chatId) {
    _botToken = botToken.trim();
    _allowedChatId = _normalizeChatId(chatId);
    if (_botToken.isEmpty) {
      onStatus?.call('Telegram bridge not started: bot token missing.');
      return;
    }
    if (_running) return;
    _running = true;
    onStatus?.call(_allowedChatId.isEmpty
        ? 'Telegram bridge started — waiting for the first message to auto-bind a chat.'
        : 'Telegram bridge started.');
    unawaited(_pollLoop());
  }

  void stop() {
    _running = false;
    onStatus?.call('Telegram bridge stopped.');
  }

  String _normalizeChatId(String raw) {
    final trimmed = raw.trim();
    final match = RegExp(r'-?\d{5,}').firstMatch(trimmed);
    return match != null ? match.group(0)! : trimmed;
  }

  Future<void> _pollLoop() async {
    while (_running) {
      try {
        await _pollOnce();
      } catch (e) {
        onStatus?.call('Telegram poll error: $e');
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
  }

  Future<void> _pollOnce() async {
    final uri = Uri.https('api.telegram.org', '/bot$_botToken/getUpdates', {
      'timeout': '25',
      'offset': '$_updateOffset',
    });

    final response = await http.get(uri).timeout(const Duration(seconds: 35));
    if (response.statusCode != 200) {
      onStatus?.call('Telegram API error ${response.statusCode}: ${response.body}');
      await Future<void>.delayed(const Duration(seconds: 3));
      return;
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      onStatus?.call('Telegram API rejected request: ${response.body}');
      await Future<void>.delayed(const Duration(seconds: 3));
      return;
    }

    final results = decoded['result'];
    if (results is! List || results.isEmpty) return;

    for (final update in results) {
      if (update is! Map<String, dynamic>) continue;
      final updateId = update['update_id'];
      if (updateId is int && updateId >= _updateOffset) {
        _updateOffset = updateId + 1;
      }

      final message = update['message'];
      if (message is! Map<String, dynamic>) continue;
      final text = message['text'];
      final from = message['from'];
      final isBot = from is Map<String, dynamic> && from['is_bot'] == true;
      if (text is! String || text.trim().isEmpty || isBot) continue;

      final chat = message['chat'];
      final chatId = chat is Map<String, dynamic> ? _normalizeChatId('${chat['id']}') : '';
      if (chatId.isEmpty) continue;

      if (_allowedChatId.isEmpty) {
        _allowedChatId = chatId;
        onStatus?.call('Bound to chat $chatId.');
        onChatBound?.call(chatId);
      } else if (chatId != _allowedChatId) {
        onStatus?.call(
            'Ignored message from chat $chatId — bridge is bound to chat $_allowedChatId. '
            'Update the Chat ID in the Telegram panel if this should be allowed.');
        continue;
      }

      if (!_running) return;

      String reply;
      try {
        reply = await onMessage(text.trim());
      } catch (e) {
        reply = 'Agent error: $e';
      }
      await _sendMessage(chatId, reply);
    }
  }

  Future<void> _sendMessage(String chatId, String text) async {
    final safeText = text.length > 3900 ? '${text.substring(0, 3900)}\n\n(Truncated)' : text;
    final uri = Uri.https('api.telegram.org', '/bot$_botToken/sendMessage');
    try {
      await http.post(
        uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'chat_id': chatId, 'text': safeText},
      );
    } catch (e) {
      onStatus?.call('Failed to send Telegram reply: $e');
    }
  }
}
