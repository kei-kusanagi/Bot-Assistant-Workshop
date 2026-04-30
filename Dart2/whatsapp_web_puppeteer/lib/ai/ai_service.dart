import 'package:whatsapp_web_puppeteer/ai/ai_provider.dart';

class AIService {
  AIService({required AIProvider provider, String? systemPrompt})
    : _provider = provider,
      _systemPrompt = systemPrompt ?? _defaultSystemPrompt;

  final AIProvider _provider;
  final String _systemPrompt;

  Future<String> getResponse(String message) async {
    final cleanMessage = message.trim();
    if (cleanMessage.isEmpty) {
      return 'No recibi texto para responder.';
    }

    final prompt =
        '''
$_systemPrompt

Mensaje del usuario:
$cleanMessage

Respuesta:
''';

    final response = await _provider.generateResponse(prompt);
    if (response.trim().isEmpty) {
      return 'Por ahora no tengo una respuesta clara. Puedes intentar de nuevo?';
    }
    return response.trim();
  }
}

const _defaultSystemPrompt = '''
Eres un asistente de WhatsApp para un negocio que trabaja por citas.
Responde siempre en español.
Se breve, amable y claro.
No inventes disponibilidad, precios, ubicaciones ni datos medicos.
Si el usuario quiere agendar, pide la informacion minima necesaria:
nombre, servicio deseado, dia y horario preferido.
Si no tienes informacion suficiente, ofrece pasar el caso a una persona del negocio.
''';
