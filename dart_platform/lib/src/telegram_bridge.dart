import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:noriter_ai_desktop/src/excel_service.dart';

typedef TelegramMessageHandler = Future<String> Function(String text, {List<String> imageDataUrls});
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
      final from = message['from'];
      final isBot = from is Map<String, dynamic> && from['is_bot'] == true;
      if (isBot) continue;

      // Photos arrive as an array of the same image at increasing
      // resolutions ("PhotoSize"); the last entry is the largest. A photo
      // may come with or without a caption -- either is a valid message.
      final photosRaw = message['photo'];
      final photos = photosRaw is List ? photosRaw : const [];
      final hasPhoto = photos.isNotEmpty;
      // Files sent as attachments (not photos) arrive as "document" --
      // this is how Telegram sends .xlsx/.csv/.txt/etc.
      final document = message['document'];
      final hasDocument = document is Map<String, dynamic>;
      final rawText = (message['text'] as String?) ?? (message['caption'] as String?) ?? '';
      if (!hasPhoto && !hasDocument && rawText.trim().isEmpty) continue;

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

      var imageDataUrls = <String>[];
      if (hasPhoto) {
        final largest = photos.last;
        final fileId = largest is Map<String, dynamic> ? largest['file_id'] as String? : null;
        if (fileId != null) {
          try {
            final file = await _downloadFile(fileId);
            if (file != null) imageDataUrls = [_bytesToImageDataUrl(file.bytes, file.filePath)];
          } catch (e) {
            onStatus?.call('Failed to download Telegram photo: $e');
          }
        }
      }

      String? fileAttachmentText;
      if (hasDocument) {
        final fileId = document['file_id'] as String?;
        final fileName = (document['file_name'] as String?) ?? 'file';
        if (fileId != null) {
          try {
            final file = await _downloadFile(fileId);
            if (file != null) {
              fileAttachmentText = _composeFileAttachmentText(fileName, file.bytes);
            }
          } catch (e) {
            onStatus?.call('Failed to download Telegram document: $e');
          }
        }
      }

      var text = rawText.trim();
      if (fileAttachmentText != null) {
        text = text.isEmpty ? 'Please review the attached file.\n\n$fileAttachmentText' : '$text\n\n$fileAttachmentText';
      } else if (text.isEmpty && imageDataUrls.isNotEmpty) {
        text = 'Please analyze the attached image.';
      }
      if (text.isEmpty) continue;

      String reply;
      try {
        reply = await onMessage(text, imageDataUrls: imageDataUrls);
      } catch (e) {
        reply = 'Agent error: $e';
      }
      await _sendMessage(chatId, reply);
    }
  }

  /// Downloads a Telegram file (photo or document) by its file_id via
  /// getFile + the file download endpoint, returning the raw bytes plus
  /// the Telegram-side file_path (its extension is used to pick a MIME
  /// type / parsing strategy by callers).
  Future<_TelegramFile?> _downloadFile(String fileId) async {
    final getFileUri = Uri.https('api.telegram.org', '/bot$_botToken/getFile', {'file_id': fileId});
    final getFileResponse = await http.get(getFileUri).timeout(const Duration(seconds: 15));
    if (getFileResponse.statusCode != 200) return null;

    final decoded = jsonDecode(getFileResponse.body) as Map<String, dynamic>;
    if (decoded['ok'] != true) return null;
    final result = decoded['result'];
    if (result is! Map<String, dynamic>) return null;
    final filePath = result['file_path'] as String?;
    if (filePath == null || filePath.isEmpty) return null;

    final fileUri = Uri.https('api.telegram.org', '/file/bot$_botToken/$filePath');
    final fileResponse = await http.get(fileUri).timeout(const Duration(seconds: 30));
    if (fileResponse.statusCode != 200) return null;

    return _TelegramFile(bytes: fileResponse.bodyBytes, filePath: filePath);
  }

  String _bytesToImageDataUrl(List<int> bytes, String filePath) {
    final ext = filePath.contains('.') ? filePath.split('.').last.toLowerCase() : 'jpg';
    final mimeType = switch (ext) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  /// Converts a downloaded document into the same "[Attached file: ...]"
  /// text block the web chat uses for non-image attachments -- .xlsx is
  /// parsed into a plain-text table via excelBytesToText(), everything
  /// else is treated as UTF-8 text. Truncated the same way (8000 chars) to
  /// avoid the context-bloat issue fixed for the web attachment path.
  String _composeFileAttachmentText(String fileName, List<int> bytes) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    String content;
    try {
      content = ext == 'xlsx' ? excelBytesToText(bytes) : utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      content = '(failed to read file: $e)';
    }

    const maxChars = 8000;
    final truncated = content.length > maxChars;
    final body = truncated ? content.substring(0, maxChars) : content;
    final notice = truncated ? '\n\n(File truncated to $maxChars characters)' : '';
    return '[Attached file: $fileName]\n```\n$body\n```$notice';
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

class _TelegramFile {
  _TelegramFile({required this.bytes, required this.filePath});
  final List<int> bytes;
  final String filePath;
}
