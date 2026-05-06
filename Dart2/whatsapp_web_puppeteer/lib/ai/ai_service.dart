import 'package:whatsapp_web_puppeteer/ai/ai_context.dart';
import 'package:whatsapp_web_puppeteer/ai/ai_provider.dart';

class AIService {
  AIService({required AIProvider provider, String? systemPrompt})
    : _provider = provider,
      _systemPrompt = systemPrompt ?? _defaultSystemPrompt;

  final AIProvider _provider;
  final String _systemPrompt;

  Future<String> getResponse(
    String message, {
    BusinessProfile? businessProfile,
    ConversationContext? conversationContext,
  }) async {
    final cleanMessage = message.trim();
    if (cleanMessage.isEmpty) {
      return 'No recibi texto para responder.';
    }

    final profile = businessProfile ?? BusinessProfile.empty();
    final directAnswer = _directBusinessAnswer(cleanMessage, profile);
    if (directAnswer != null) return directAnswer;

    final prompt =
        '''
$_systemPrompt

Conocimiento oficial del negocio:
${profile.toPromptBlock()}

Memoria local de esta conversacion:
${conversationContext?.toPromptBlock() ?? 'Sin memoria previa.'}

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

String? _directBusinessAnswer(String message, BusinessProfile profile) {
  final lower = message.toLowerCase();
  if (_asksForPricing(lower)) {
    return _directPricingAnswer(lower, profile);
  }
  if (_asksForLocation(lower) && profile.location.isNotEmpty) {
    return _renderTemplate(profile.responseTemplates['location'], profile);
  }
  if (_asksForSchedule(lower) && profile.schedule.isNotEmpty) {
    return _renderTemplate(profile.responseTemplates['schedule'], profile);
  }
  if (_asksForServices(lower) && profile.services.isNotEmpty) {
    return _renderTemplate(profile.responseTemplates['services'], profile);
  }
  if (_asksForBusinessType(lower) && profile.businessName.isNotEmpty) {
    return _renderTemplate(profile.responseTemplates['businessType'], profile);
  }
  return null;
}

String? _directPricingAnswer(String lower, BusinessProfile profile) {
  final service = _findMentionedService(lower, profile);
  if (service != null) {
    final price = profile.servicePrices[service];
    if (price != null && price.trim().isNotEmpty) {
      return _renderTemplate(
        profile.responseTemplates['servicePricing'],
        profile,
        service: service,
        price: price,
      );
    }
    return _renderTemplate(
      profile.responseTemplates['pricingUnavailable'],
      profile,
      service: service,
    );
  }

  if (profile.servicePrices.isNotEmpty) {
    return _renderTemplate(profile.responseTemplates['pricingList'], profile);
  }
  return _renderTemplate(
    profile.responseTemplates['pricingUnavailable'],
    profile,
  );
}

String? _findMentionedService(String lower, BusinessProfile profile) {
  final normalizedMessage = _normalize(lower);
  for (final service in profile.services) {
    final normalizedService = _normalize(service);
    if (normalizedMessage.contains(normalizedService)) return service;
  }
  for (final service in profile.servicePrices.keys) {
    final normalizedService = _normalize(service);
    if (normalizedMessage.contains(normalizedService)) return service;
  }
  return null;
}

String? _renderTemplate(
  String? template,
  BusinessProfile profile, {
  String service = '',
  String price = '',
}) {
  if (template == null || template.trim().isEmpty) return null;
  return template
      .replaceAll('{businessName}', profile.businessName)
      .replaceAll('{businessType}', profile.businessType)
      .replaceAll('{website}', profile.website)
      .replaceAll('{services}', profile.services.join(', '))
      .replaceAll('{servicePrices}', _formatServicePrices(profile))
      .replaceAll('{service}', service)
      .replaceAll('{price}', price)
      .replaceAll('{schedule}', profile.schedule)
      .replaceAll('{location}', profile.location)
      .replaceAll('{contact}', profile.contact)
      .trim();
}

String _formatServicePrices(BusinessProfile profile) {
  return profile.servicePrices.entries
      .map((entry) => '${entry.key}: ${entry.value}')
      .join(', ');
}

bool _asksForLocation(String lower) {
  return lower.contains('ubic') ||
      lower.contains('hubic') ||
      lower.contains('direccion') ||
      lower.contains('dirección') ||
      lower.contains('donde estan') ||
      lower.contains('dónde están') ||
      lower.contains('por donde estan') ||
      lower.contains('por dónde están');
}

bool _asksForSchedule(String lower) {
  return lower.contains('horario') ||
      lower.contains('abren') ||
      lower.contains('cierran') ||
      lower.contains('que dias') ||
      lower.contains('qué días') ||
      lower.contains('disponibles');
}

bool _asksForServices(String lower) {
  return lower.contains('servicios') ||
      lower.contains('que ofrecen') ||
      lower.contains('qué ofrecen') ||
      lower.contains('que hacen') ||
      lower.contains('qué hacen');
}

bool _asksForPricing(String lower) {
  return lower.contains('precio') ||
      lower.contains('precios') ||
      lower.contains('costo') ||
      lower.contains('costos') ||
      lower.contains('cuanto cuesta') ||
      lower.contains('cuánto cuesta') ||
      lower.contains('aproximado');
}

bool _asksForBusinessType(String lower) {
  return lower.contains('dentista') ||
      lower.contains('dental') ||
      lower.contains('medicina familiar') ||
      lower.contains('medicina preventiva') ||
      lower.contains('consultorio de medicina');
}

String _normalize(String value) {
  return value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');
}

const _defaultSystemPrompt = '''
Eres un asistente de WhatsApp para un negocio que trabaja por citas.
Responde siempre en español.
Se breve, amable y claro.
No inventes disponibilidad, precios, ubicaciones ni datos medicos.
Usa solo el conocimiento oficial del negocio y la memoria local.
Si preguntan costos o precios y no estan configurados en el conocimiento oficial, no des rangos ni aproximados inventados.
Si el usuario pregunta algo fuera del negocio, responde breve y redirige a citas o informacion del negocio.
No uses placeholders como "servicio 1" o "servicio 2"; si hay servicios configurados, mencionalos por nombre.
No saludes de nuevo en cada mensaje de seguimiento; continua la conversacion de forma natural.
Antes de pedir un dato, revisa la memoria local. No preguntes otra vez por nombre, servicio, dia u horario si ya aparecen en memoria.
Si ya sabes el servicio deseado y el usuario pregunta por dias disponibles, explica que no tienes agenda real en tiempo real; usa el horario publicado y pide dia/horario preferido para solicitar la cita.
No pidas fecha de nacimiento, edad, diagnosticos ni datos medicos sensibles salvo que el perfil del negocio lo indique explicitamente.
Si el usuario solo agradece, se despide o dice que seria todo, responde con un cierre amable y no sigas preguntando.
Si el usuario quiere agendar, pide la informacion minima necesaria:
nombre, servicio deseado, dia y horario preferido.
Si no tienes informacion suficiente, ofrece pasar el caso a una persona del negocio.
''';
