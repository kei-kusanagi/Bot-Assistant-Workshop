import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:whatsapp_web_puppeteer/ai/ai_provider.dart';

class OllamaProvider implements AIProvider {
  OllamaProvider({
    required this.model,
    Uri? baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
  }) : baseUrl = baseUrl ?? Uri.parse('http://localhost:11434'),
       _client = client ?? http.Client();

  final String model;
  final Uri baseUrl;
  final Duration timeout;
  final http.Client _client;

  @override
  Future<String> generateResponse(String prompt) async {
    final endpoint = baseUrl.resolve('/api/generate');
    final response = await _client
        .post(
          endpoint,
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'model': model, 'prompt': prompt, 'stream': false}),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AIProviderException(
        'Ollama returned HTTP ${response.statusCode}',
        details: response.body,
      );
    }

    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw const AIProviderException('Ollama returned an unexpected payload');
    }

    final text = json['response'];
    if (text is! String) {
      throw AIProviderException(
        'Ollama response did not contain a text response',
        details: response.body,
      );
    }

    return text.trim();
  }
}
