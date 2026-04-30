/// Contract for any AI provider used by the WhatsApp bot.
///
/// Keep this interface intentionally small: the bot only needs to send a prompt
/// and receive a text response. Providers can hide their own HTTP/API details.
abstract interface class AIProvider {
  Future<String> generateResponse(String prompt);
}

class AIProviderException implements Exception {
  const AIProviderException(this.message, {this.details});

  final String message;
  final Object? details;

  @override
  String toString() {
    if (details == null) return message;
    return '$message ($details)';
  }
}
