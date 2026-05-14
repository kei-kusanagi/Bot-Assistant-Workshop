import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:whatsapp_web_puppeteer/ai/ai_context.dart';

class LocalConversationStore {
  LocalConversationStore({
    required Directory storeDirectory,
    required File businessProfileFile,
    this.maxStoredMessages = 20,
    this.maxStoredMessageChars = 1000,
    this.maxIncomingMessageChars = 2000,
  }) : _storeDirectory = storeDirectory,
       _businessProfileFile = businessProfileFile;

  final Directory _storeDirectory;
  final File _businessProfileFile;
  final int maxStoredMessages;
  final int maxStoredMessageChars;
  final int maxIncomingMessageChars;

  Directory get _conversationsDirectory =>
      Directory(p.join(_storeDirectory.path, 'conversations'));

  Future<void> ensureReady() async {
    if (!await _storeDirectory.exists()) {
      await _storeDirectory.create(recursive: true);
    }
    if (!await _conversationsDirectory.exists()) {
      await _conversationsDirectory.create(recursive: true);
    }
    if (!await _businessProfileFile.exists()) {
      await _businessProfileFile.create(recursive: true);
      await _writeJson(_businessProfileFile, BusinessProfile.empty().toJson());
    }
  }

  bool isIncomingMessageTooLong(String message) {
    return message.trim().length > maxIncomingMessageChars;
  }

  Future<BusinessProfile> loadBusinessProfile() async {
    await ensureReady();
    final json = await _readJsonObject(_businessProfileFile);
    return BusinessProfile.fromJson(json);
  }

  Future<ConversationContext> loadContext(String jid) async {
    await ensureReady();
    final record = await _loadConversationRecord(jid);
    final messages = _messageList(record['messages']);
    return ConversationContext(
      jid: jid,
      summary: _string(record['summary']),
      facts: _factsMap(record['facts']),
      recentMessages: messages,
    );
  }

  /// Borra el historial y hechos guardados de un chat (memoria local).
  Future<void> resetConversation(String jid) async {
    await ensureReady();
    final file = _conversationFile(jid);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> saveUserMessage(String jid, String text) async {
    await _appendMessage(jid, 'user', text);
  }

  Future<void> saveAssistantMessage(String jid, String text) async {
    await _appendMessage(jid, 'assistant', text);
  }

  Future<void> saveRejectedLongMessage(String jid, String text) async {
    final length = text.trim().length;
    await _appendMessage(
      jid,
      'user',
      '[Mensaje demasiado largo omitido: $length caracteres]',
    );
  }

  /// Fusiona datos en `facts` del JSON de la conversacion sin repetir `_appendMessage`.
  Future<void> mergeConversationFacts(
    String jid,
    Map<String, String> extraFacts,
  ) async {
    await ensureReady();
    final record = await _loadConversationRecord(jid);
    final messages = _messageList(record['messages']);
    final facts = _factsMap(record['facts']);
    for (final entry in extraFacts.entries) {
      final val = entry.value.trim();
      if (val.isEmpty) {
        facts.remove(entry.key);
      } else {
        facts[entry.key] = val;
      }
    }
    final now = DateTime.now().toUtc().toIso8601String();
    record['jid'] = jid;
    record['updatedAt'] = now;
    record['facts'] = facts;
    record['summary'] = _buildSimpleSummary(facts, messages);

    await _writeJson(_conversationFile(jid), record);
  }

  Future<void> _appendMessage(String jid, String role, String text) async {
    await ensureReady();
    final record = await _loadConversationRecord(jid);
    final now = DateTime.now().toUtc().toIso8601String();
    final priorForFacts = role == 'user'
        ? _messageList(record['messages'])
        : <ConversationMessage>[];
    final messages = List<ConversationMessage>.of(priorForFacts)
      ..add(
        ConversationMessage(
          role: role,
          text: _truncate(text.trim(), maxStoredMessageChars),
          createdAt: now,
        ),
      );

    final trimmed = messages.length <= maxStoredMessages
        ? messages
        : messages.sublist(messages.length - maxStoredMessages);

    record['jid'] = jid;
    record['updatedAt'] = now;
    record['messages'] = trimmed.map((message) => message.toJson()).toList();
    record['facts'] = _updatedFacts(
      _factsMap(record['facts']),
      role,
      text,
      priorMessagesForUserTurn: priorForFacts,
    );
    record['summary'] = _buildSimpleSummary(
      _factsMap(record['facts']),
      trimmed,
    );

    await _writeJson(_conversationFile(jid), record);
  }

  Future<Map<String, dynamic>> _loadConversationRecord(String jid) async {
    final file = _conversationFile(jid);
    if (!await file.exists()) {
      final now = DateTime.now().toUtc().toIso8601String();
      return {
        'jid': jid,
        'createdAt': now,
        'updatedAt': now,
        'summary': '',
        'facts': <String, String>{},
        'messages': <Map<String, dynamic>>[],
      };
    }
    return _readJsonObject(file);
  }

  File _conversationFile(String jid) {
    return File(
      p.join(_conversationsDirectory.path, '${_safeFileName(jid)}.json'),
    );
  }
}

Future<Map<String, dynamic>> _readJsonObject(File file) async {
  try {
    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {
    // If local JSON becomes corrupt during prototyping, start fresh instead of
    // crashing the bot.
  }
  return <String, dynamic>{};
}

Future<void> _writeJson(File file, Map<String, dynamic> json) async {
  if (!await file.parent.exists()) {
    await file.parent.create(recursive: true);
  }
  const encoder = JsonEncoder.withIndent('  ');
  await file.writeAsString('${encoder.convert(json)}\n');
}

List<ConversationMessage> _messageList(Object? value) {
  if (value is! List) return <ConversationMessage>[];
  return value
      .whereType<Map>()
      .map(
        (item) => ConversationMessage.fromJson(Map<String, dynamic>.from(item)),
      )
      .toList();
}

Map<String, String> _factsMap(Object? value) {
  if (value is! Map) return <String, String>{};
  final facts = value.map(
    (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
  );
  facts.removeWhere((_, value) => value.trim().isEmpty);
  return facts;
}

Map<String, String> _updatedFacts(
  Map<String, String> facts,
  String role,
  String text, {
  List<ConversationMessage> priorMessagesForUserTurn = const [],
}) {
  if (role != 'user') return facts;
  final clean = text.trim();
  if (clean.length > 300) return facts;

  var extracted = _extractFullNameFromUserText(clean);
  final nombreEmpty = facts['nombre']?.trim().isEmpty ?? true;
  final bookingNombreContext = _priorAssistantAskedBookingName(
    priorMessagesForUserTurn,
  );
  if (extracted == null &&
      nombreEmpty &&
      (facts['nombre_pedido'] == '1' || bookingNombreContext)) {
    extracted = _extractBareNameReply(clean);
  }
  if (extracted != null) {
    facts['nombre'] = extracted;
    facts.remove('nombre_pedido');
  }

  final lower = clean.toLowerCase();
  if (lower.contains('cita') || lower.contains('agendar')) {
    facts['intencion'] = 'agendar cita';
  }
  if (lower.contains('cancelar')) {
    facts['intencion'] = 'cancelar o cambiar cita';
  }
  final service = _detectService(lower);
  if (service != null) {
    facts['servicio_deseado'] = service;
  }

  return facts;
}

/// Igual que en agendamiento: varias palabras tras introducción de nombre.
String? _extractFullNameFromUserText(String message) {
  final trimmed = message.trim();
  if (trimmed.isEmpty) return null;
  const word = r'[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ]{2,}';
  final tail = r'(?:\s+' + word + r'){0,4}';
  final patterns = <RegExp>[
    RegExp(
      '\\bmi\\s+nombre\\s+es\\s*,?\\s*($word$tail)\\b',
      caseSensitive: false,
    ),
    RegExp('\\bme\\s+llamo\\s*,?\\s*($word$tail)\\b', caseSensitive: false),
    RegExp('\\bsoy\\s*,?\\s*($word$tail)\\b', caseSensitive: false),
    RegExp(
      '\\ba\\s+nombre\\s+de\\s*,?\\s*($word$tail)\\b',
      caseSensitive: false,
    ),
    RegExp(
      '\\bla\\s+cita\\s+a\\s+nombre\\s+de\\s*,?\\s*($word$tail)\\b',
      caseSensitive: false,
    ),
  ];
  for (final re in patterns) {
    final m = re.firstMatch(trimmed);
    if (m != null) {
      var name = m.group(1)!.trim();
      name = name.replaceAll(RegExp(r'\s+'), ' ');
      if (name.length > 80) {
        name = name.substring(0, 80).trim();
      }
      if (name.length >= 2) return name;
    }
  }
  return null;
}

/// Tras pedir nombre con [nombre_pedido], el usuario suele responder "Kei Kusanagi"
/// o "ok, soy Kei Kusanagi" sin formula fija.
String? _extractBareNameReply(String message) {
  var s = message.trim();
  if (s.isEmpty || s.length > 160) return null;
  s = _stripLeadingNameReplyFillers(s);
  if (s.isEmpty) return null;

  final fromStop = RegExp(
    r'^([A-Za-záéíóúÁÉÍÓÚñÑüÜ]{2,}(?:\s+[A-Za-záéíóúÁÉÍÓÚñÑüÜ]{2,}){0,3})\s+'
    r'(?=(?:gracias|disculpa|perd[oó]n|perdon|por\s+favor|buen|buenas|'
    r'buenos|hola|que\s+|qué\s+|un\s+|una\s+|me\s+))',
    caseSensitive: false,
  ).firstMatch(s);
  if (fromStop != null) {
    final candidate = fromStop.group(1)!.trim();
    if (_looksLikePersonalNameTokens(candidate)) return candidate;
  }

  final noComma = s.split(',').first.trim();
  if (noComma != s && _looksLikePersonalNameTokens(noComma)) return noComma;

  if (_looksLikePersonalNameTokens(s)) return s;
  return null;
}

String _stripLeadingNameReplyFillers(String input) {
  var s = input.trim();
  for (var i = 0; i < 8; i++) {
    final next = s.replaceFirst(
      RegExp(
        r'^(?:ok+|vale+|listo+|bueno+|buen+|aja+|oye+|mira+|'
        r'a\s*ver+|es\s+que+|o\s+sea+|disculpa+|perd[oó]n+|perdon+)\s*[,:.-]?\s*',
        caseSensitive: false,
      ),
      '',
    );
    if (next == s) break;
    s = next.trim();
  }
  return s;
}

const _nonPersonalNameTokens = <String>{
  'que',
  'qué',
  'los',
  'las',
  'unos',
  'unas',
  'por',
  'para',
  'con',
  'sin',
  'pero',
  'como',
  'cómo',
  'tengo',
  'tiene',
  'tienes',
  'quiero',
  'necesito',
  'gracias',
  'disculpa',
  'hola',
  'buen',
  'bueno',
  'buena',
  'dia',
  'día',
  'cita',
  'agendar',
};

bool _looksLikePersonalNameTokens(String raw) {
  final t = raw.trim();
  if (t.isEmpty || t.length > 80) return false;
  final parts = t.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty || parts.length > 5) return false;
  final word = RegExp(r'^[A-Za-záéíóúÁÉÍÓÚñÑüÜ]{2,}$');
  for (final p in parts) {
    if (!word.hasMatch(p)) return false;
    final pl = p.toLowerCase().replaceAll('á', 'a').replaceAll('é', 'e');
    if (_nonPersonalNameTokens.contains(pl)) return false;
  }
  if (parts.length >= 2) return true;
  return parts.first.length >= 3;
}

bool _priorAssistantAskedBookingName(List<ConversationMessage> prior) {
  for (var i = prior.length - 1; i >= 0; i--) {
    if (prior[i].role != 'assistant') continue;
    final t = prior[i].text.toLowerCase();
    return t.contains('a nombre') &&
        (t.contains('registr') ||
            t.contains('quien registro') ||
            t.contains('cita'));
  }
  return false;
}

String? _detectService(String lowerMessage) {
  if (lowerMessage.contains('chequeo') ||
      lowerMessage.contains('revision') ||
      lowerMessage.contains('revisión') ||
      lowerMessage.contains('valoracion') ||
      lowerMessage.contains('valoración')) {
    return 'Valoracion dental';
  }
  if (lowerMessage.contains('limpieza')) return 'Limpieza dental';
  if (lowerMessage.contains('resina')) return 'Resinas';
  if (lowerMessage.contains('extraccion') ||
      lowerMessage.contains('extracción') ||
      lowerMessage.contains('sacar una muela')) {
    return 'Extracciones';
  }
  if (lowerMessage.contains('blanqueamiento')) return 'Blanqueamiento dental';
  if (lowerMessage.contains('endodoncia')) return 'Endodoncia';
  if (lowerMessage.contains('ortodoncia') ||
      lowerMessage.contains('brackets')) {
    return 'Ortodoncia';
  }
  if (lowerMessage.contains('protesis') || lowerMessage.contains('prótesis')) {
    return 'Protesis dentales';
  }
  return null;
}

String _buildSimpleSummary(
  Map<String, String> facts,
  List<ConversationMessage> messages,
) {
  final parts = <String>[];
  if (facts.isNotEmpty) {
    parts.add(
      facts.entries.map((entry) => '${entry.key}: ${entry.value}').join('; '),
    );
  }
  String? lastUserMessage;
  for (final message in messages.reversed) {
    if (message.role == 'user') {
      lastUserMessage = message.text;
      break;
    }
  }
  if (lastUserMessage != null) {
    parts.add('ultimo mensaje del usuario: $lastUserMessage');
  }
  return _truncate(parts.join('. '), 700);
}

String _truncate(String value, int maxChars) {
  if (value.length <= maxChars) return value;
  return '${value.substring(0, maxChars)}... [truncado]';
}

String _string(Object? value) => value is String ? value.trim() : '';

String _safeFileName(String jid) {
  return jid.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
}
