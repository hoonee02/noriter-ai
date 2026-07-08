import 'dart:convert';

import 'package:http/http.dart' as http;

abstract class ModelProvider {
  Future<List<String>> listModels();
}

class OpenAiCompatibleModelProvider implements ModelProvider {
  OpenAiCompatibleModelProvider({
    required this.endpoint,
    required this.apiKey,
  });

  final String endpoint;
  final String apiKey;

  @override
  Future<List<String>> listModels() async {
    final normalizedBase = endpoint.endsWith('/')
        ? endpoint.substring(0, endpoint.length - 1)
        : endpoint;
    final url = Uri.parse('$normalizedBase/models');

    final response = await http.get(
      url,
      headers: <String, String>{
        'Authorization': 'Bearer $apiKey',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ModelProviderException(
        'Failed to fetch model list. HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ModelProviderException('Unexpected model list response.');
    }

    final data = decoded['data'];
    if (data is! List) {
      throw const ModelProviderException('Response does not contain data list.');
    }

    final models = <String>{};
    for (final item in data) {
      if (item is Map<String, dynamic>) {
        final id = item['id'];
        if (id is String && id.trim().isNotEmpty) {
          models.add(id.trim());
        }
      }
    }

    final sorted = models.toList()..sort();
    return sorted;
  }
}

class ModelProviderException implements Exception {
  const ModelProviderException(this.message);
  final String message;

  @override
  String toString() => message;
}
