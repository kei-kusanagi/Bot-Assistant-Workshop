class BusinessProfile {
  const BusinessProfile({
    required this.businessName,
    required this.businessType,
    required this.website,
    required this.services,
    required this.servicePrices,
    required this.schedule,
    required this.location,
    required this.contact,
    required this.assistantInstructions,
    required this.policies,
    required this.responseTemplates,
    required this.unknownAnswerPolicy,
  });

  factory BusinessProfile.fromJson(Map<String, dynamic> json) {
    return BusinessProfile(
      businessName: _string(json['businessName']),
      businessType: _string(json['businessType']),
      website: _string(json['website']),
      services: _stringList(json['services']),
      servicePrices: _stringMap(json['servicePrices']),
      schedule: _string(json['schedule']),
      location: _string(json['location']),
      contact: _string(json['contact']),
      assistantInstructions: _stringList(json['assistantInstructions']),
      policies: _stringList(json['policies']),
      responseTemplates: _stringMap(json['responseTemplates']),
      unknownAnswerPolicy: _string(json['unknownAnswerPolicy']),
    );
  }

  final String businessName;
  final String businessType;
  final String website;
  final List<String> services;
  final Map<String, String> servicePrices;
  final String schedule;
  final String location;
  final String contact;
  final List<String> assistantInstructions;
  final List<String> policies;
  final Map<String, String> responseTemplates;
  final String unknownAnswerPolicy;

  Map<String, dynamic> toJson() => {
    'businessName': businessName,
    'businessType': businessType,
    'website': website,
    'services': services,
    'servicePrices': servicePrices,
    'schedule': schedule,
    'location': location,
    'contact': contact,
    'assistantInstructions': assistantInstructions,
    'policies': policies,
    'responseTemplates': responseTemplates,
    'unknownAnswerPolicy': unknownAnswerPolicy,
  };

  String toPromptBlock() {
    final lines = <String>[
      'Nombre: ${businessName.isEmpty ? "No configurado" : businessName}',
      'Tipo de negocio: ${businessType.isEmpty ? "No configurado" : businessType}',
      if (website.isNotEmpty) 'Sitio web: $website',
      'Servicios:',
      if (services.isEmpty) '- No configurados',
      ...services.map((service) => '- $service'),
      'Precios configurados:',
      if (servicePrices.isEmpty) '- No configurados',
      ...servicePrices.entries.map((entry) => '- ${entry.key}: ${entry.value}'),
      'Horario: ${schedule.isEmpty ? "No configurado" : schedule}',
      'Ubicacion: ${location.isEmpty ? "No configurada" : location}',
      'Contacto: ${contact.isEmpty ? "No configurado" : contact}',
      'Instrucciones de estilo del asistente:',
      if (assistantInstructions.isEmpty) '- No configuradas',
      ...assistantInstructions.map((instruction) => '- $instruction'),
      'Politicas:',
      if (policies.isEmpty) '- No configuradas',
      ...policies.map((policy) => '- $policy'),
      'Regla si falta informacion: ${unknownAnswerPolicy.isEmpty ? "No inventar y ofrecer contacto humano." : unknownAnswerPolicy}',
    ];
    return lines.join('\n');
  }

  static BusinessProfile empty() {
    return const BusinessProfile(
      businessName: '',
      businessType: '',
      website: '',
      services: [],
      servicePrices: {},
      schedule: '',
      location: '',
      contact: '',
      assistantInstructions: [],
      policies: [],
      responseTemplates: {},
      unknownAnswerPolicy:
          'Si el dato no esta en este perfil, no inventes y ofrece pasar el caso a una persona.',
    );
  }
}

class ConversationMessage {
  const ConversationMessage({
    required this.role,
    required this.text,
    required this.createdAt,
  });

  factory ConversationMessage.fromJson(Map<String, dynamic> json) {
    return ConversationMessage(
      role: _string(json['role']),
      text: _string(json['text']),
      createdAt: _string(json['createdAt']),
    );
  }

  final String role;
  final String text;
  final String createdAt;

  Map<String, dynamic> toJson() => {
    'role': role,
    'text': text,
    'createdAt': createdAt,
  };
}

class ConversationContext {
  const ConversationContext({
    required this.jid,
    required this.summary,
    required this.facts,
    required this.recentMessages,
  });

  final String jid;
  final String summary;
  final Map<String, String> facts;
  final List<ConversationMessage> recentMessages;

  String toPromptBlock() {
    final lines = <String>[
      'Identificador WhatsApp: $jid',
      'Resumen previo: ${summary.isEmpty ? "Sin resumen aun." : summary}',
      'Datos estructurados detectados:',
      if (facts.isEmpty) '- Ninguno aun',
      ...facts.entries.map((entry) => '- ${entry.key}: ${entry.value}'),
      'Mensajes recientes:',
      if (recentMessages.isEmpty) '- Sin mensajes previos',
      ...recentMessages.map((message) => '- ${message.role}: ${message.text}'),
    ];
    return lines.join('\n');
  }
}

String _string(Object? value) => value is String ? value.trim() : '';

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return const {};
  final entries = value.entries
      .map((entry) => MapEntry(entry.key.toString(), _string(entry.value)))
      .where((entry) => entry.value.isNotEmpty);
  return Map<String, String>.fromEntries(entries);
}
