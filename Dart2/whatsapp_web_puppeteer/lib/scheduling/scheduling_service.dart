import 'package:whatsapp_web_puppeteer/ai/ai_context.dart';
import 'package:whatsapp_web_puppeteer/scheduling/local_scheduling_store.dart';
import 'package:whatsapp_web_puppeteer/scheduling/scheduling_models.dart';

class SchedulingService {
  SchedulingService({required LocalSchedulingStore store}) : _store = store;

  final LocalSchedulingStore _store;

  Future<String?> handleMessage({
    required String jid,
    required String message,
    required BusinessProfile businessProfile,
    required ConversationContext conversationContext,
  }) async {
    final lower = _normalize(message);
    final draft = await _store.loadDraft(jid);
    final hasActiveDraft = _hasAnyDraftValue(draft);
    final isScheduling = hasActiveDraft || _isSchedulingMessage(lower);
    if (!isScheduling) return null;

    final updatedDraft = _mergeDraft(
      draft: draft,
      message: message,
      businessProfile: businessProfile,
      conversationContext: conversationContext,
    );

    if (_asksForAvailability(lower)) {
      await _store.saveDraft(updatedDraft);
      final date = _parsePreferredDate(message) ?? _dateFromDraft(updatedDraft);
      if (date == null) {
        return 'Claro. ¿Para que dia te gustaria revisar disponibilidad?';
      }
      final slots = await availableSlots(date, limit: 3);
      if (slots.isEmpty) {
        return 'No veo horarios libres para ${_formatDate(date)}. ¿Quieres que revise otro dia?';
      }
      return 'Tengo estos horarios libres para ${_formatDate(date)}:\n${_formatSlotList(slots)}\n¿Cuál prefieres?';
    }

    final missing = _missingFields(updatedDraft);
    if (missing.isNotEmpty) {
      await _store.saveDraft(updatedDraft);
      final date = _dateFromDraft(updatedDraft);
      if (missing.first == _MissingField.time && date != null) {
        final slots = await availableSlots(date, limit: 3);
        if (slots.isNotEmpty) {
          return 'Para ${_formatDate(date)} tengo estos horarios libres:\n${_formatSlotList(slots)}\n¿Cuál prefieres?';
        }
      }
      return _questionForMissingField(missing.first, businessProfile);
    }

    final start = _dateTimeFromDraft(updatedDraft);
    if (start == null) {
      await _store.saveDraft(updatedDraft);
      return 'Tengo casi todo. ¿Me confirmas el dia y horario que prefieres?';
    }
    final end = start.add(await _slotDuration());
    if (!await isSlotAvailable(start, end)) {
      await _store.saveDraft(updatedDraft);
      final alternatives = await availableSlots(start, limit: 3);
      if (alternatives.isEmpty) {
        return 'Ese horario ya no esta disponible. ¿Quieres que revise otro dia?';
      }
      return 'Ese horario ya esta ocupado. Tengo estas opciones cercanas:\n${_formatSlotList(alternatives)}\n¿Cuál prefieres?';
    }

    final appointment = await _store.createConfirmedAppointment(
      jid: jid,
      name: updatedDraft.name,
      service: updatedDraft.service,
      start: start,
      end: end,
    );

    return 'Listo, agende tu cita en el calendario simulado:\n'
        'Servicio: ${appointment.service}\n'
        'Nombre: ${appointment.name}\n'
        'Fecha: ${_formatDate(appointment.start)}\n'
        'Hora: ${_formatTime(appointment.start)}\n'
        'Estado: confirmada en esta prueba local.';
  }

  Future<List<DateTime>> availableSlots(DateTime date, {int limit = 3}) async {
    final availability = await _store.loadAvailability();
    final dayKey = _weekdayKey(date);
    final ranges = availability.workingHours[dayKey] ?? const <TimeRange>[];
    if (ranges.isEmpty) return const [];
    final dateText = _isoDate(date);
    if (availability.blockedDates.any((blocked) => blocked.date == dateText)) {
      return const [];
    }

    final now = DateTime.now();
    final minStart = now.add(Duration(hours: availability.minNoticeHours));
    final events = await _blockingEvents();
    final slots = <DateTime>[];
    for (final range in ranges) {
      final startParts = _parseClock(range.start);
      final endParts = _parseClock(range.end);
      if (startParts == null || endParts == null) continue;
      var cursor = DateTime(
        date.year,
        date.month,
        date.day,
        startParts.hour,
        startParts.minute,
      );
      final rangeEnd = DateTime(
        date.year,
        date.month,
        date.day,
        endParts.hour,
        endParts.minute,
      );
      while (cursor
              .add(Duration(minutes: availability.slotMinutes))
              .compareTo(rangeEnd) <=
          0) {
        final slotEnd = cursor.add(Duration(minutes: availability.slotMinutes));
        if (cursor.isAfter(minStart) && _isFree(cursor, slotEnd, events)) {
          slots.add(cursor);
          if (slots.length >= limit) return slots;
        }
        cursor = cursor.add(Duration(minutes: availability.slotMinutes));
      }
    }
    return slots;
  }

  Future<bool> isSlotAvailable(DateTime start, DateTime end) async {
    final slots = await availableSlots(start, limit: 100);
    return slots.any((slot) => slot.isAtSameMomentAs(start));
  }

  Future<Duration> _slotDuration() async {
    final availability = await _store.loadAvailability();
    return Duration(minutes: availability.slotMinutes);
  }

  Future<List<CalendarEvent>> _blockingEvents() async {
    final events = await _store.loadCalendarEvents();
    return events
        .where((event) => event.status != 'cancelled')
        .where((event) => event.type == 'appointment' || event.type == 'block')
        .toList();
  }
}

enum _MissingField { name, service, date, time }

SchedulingDraft _mergeDraft({
  required SchedulingDraft draft,
  required String message,
  required BusinessProfile businessProfile,
  required ConversationContext conversationContext,
}) {
  final facts = conversationContext.facts;
  final name = _firstNonEmpty([
    _extractName(message),
    draft.name,
    facts['nombre'],
  ]);
  final service = _firstNonEmpty([
    _extractService(message, businessProfile),
    draft.service,
    facts['servicio_deseado'],
  ]);
  final date = _parsePreferredDate(message);
  final time = _parsePreferredTime(message);
  return draft.copyWith(
    name: name,
    service: service,
    preferredDate: date == null ? null : _isoDate(date),
    preferredTime:
        time ?? (draft.preferredTime.isEmpty ? null : draft.preferredTime),
  );
}

List<_MissingField> _missingFields(SchedulingDraft draft) {
  return [
    if (draft.name.isEmpty) _MissingField.name,
    if (draft.service.isEmpty) _MissingField.service,
    if (draft.preferredDate.isEmpty) _MissingField.date,
    if (draft.preferredTime.isEmpty) _MissingField.time,
  ];
}

String _questionForMissingField(
  _MissingField field,
  BusinessProfile businessProfile,
) {
  switch (field) {
    case _MissingField.name:
      return 'Claro, puedo ayudarte a agendar. ¿A nombre de quien registro la cita?';
    case _MissingField.service:
      final services = businessProfile.services.isEmpty
          ? 'el servicio que necesitas'
          : businessProfile.services.join(', ');
      return '¿Que servicio necesitas? Tenemos: $services.';
    case _MissingField.date:
      return '¿Que dia prefieres para la cita?';
    case _MissingField.time:
      return '¿Que horario prefieres?';
  }
}

bool _hasAnyDraftValue(SchedulingDraft draft) {
  return draft.name.isNotEmpty ||
      draft.service.isNotEmpty ||
      draft.preferredDate.isNotEmpty ||
      draft.preferredTime.isNotEmpty;
}

bool _isSchedulingMessage(String lower) {
  return lower.contains('cita') ||
      lower.contains('agendar') ||
      lower.contains('agenda') ||
      lower.contains('reservar') ||
      lower.contains('disponibilidad') ||
      lower.contains('disponible') ||
      lower.contains('horario libre') ||
      lower.contains('espacio');
}

bool _asksForAvailability(String lower) {
  return lower.contains('disponibilidad') ||
      lower.contains('disponible') ||
      lower.contains('que dias') ||
      lower.contains('que horarios') ||
      lower.contains('horarios libres') ||
      lower.contains('espacio');
}

String? _extractName(String message) {
  final match = RegExp(
    r'\b(?:me llamo|soy|a nombre de)\s+([a-záéíóúñü]{2,30})(?:\s+[a-záéíóúñü]{2,30})?',
    caseSensitive: false,
  ).firstMatch(message);
  return match?.group(1)?.trim();
}

String? _extractService(String message, BusinessProfile profile) {
  final lower = _normalize(message);
  for (final service in profile.services) {
    if (lower.contains(_normalize(service))) return service;
  }
  if (lower.contains('chequeo') ||
      lower.contains('revision') ||
      lower.contains('valoracion')) {
    return 'Valoracion dental';
  }
  return null;
}

DateTime? _parsePreferredDate(String message) {
  final lower = _normalize(message);
  final now = DateTime.now();
  if (lower.contains('hoy')) return _dateOnly(now);
  if (lower.contains('pasado manana')) {
    return _dateOnly(now.add(const Duration(days: 2)));
  }
  if (lower.contains('manana')) {
    return _dateOnly(now.add(const Duration(days: 1)));
  }

  final isoMatch = RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b').firstMatch(lower);
  if (isoMatch != null) {
    return DateTime(
      int.parse(isoMatch.group(1)!),
      int.parse(isoMatch.group(2)!),
      int.parse(isoMatch.group(3)!),
    );
  }

  for (final entry in _weekdays.entries) {
    if (lower.contains(entry.key)) {
      return _nextWeekday(now, entry.value);
    }
  }
  return null;
}

String? _parsePreferredTime(String message) {
  final lower = _normalize(message);
  final matches = RegExp(
    r'\b(?:a las\s*)?(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?\b',
  ).allMatches(lower);
  for (final match in matches) {
    var hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '0') ?? 0;
    final suffix = match.group(3);
    if (hour == null || hour > 23 || minute > 59) continue;
    if (suffix != null && suffix.contains('p') && hour < 12) hour += 12;
    if (suffix != null && suffix.contains('a') && hour == 12) hour = 0;
    if (suffix == null && hour >= 1 && hour <= 7) hour += 12;
    if (hour < 8 || hour > 21) continue;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }
  return null;
}

DateTime? _dateFromDraft(SchedulingDraft draft) {
  if (draft.preferredDate.isEmpty) return null;
  return DateTime.tryParse(draft.preferredDate);
}

DateTime? _dateTimeFromDraft(SchedulingDraft draft) {
  final date = _dateFromDraft(draft);
  final clock = _parseClock(draft.preferredTime);
  if (date == null || clock == null) return null;
  return DateTime(date.year, date.month, date.day, clock.hour, clock.minute);
}

bool _isFree(DateTime start, DateTime end, List<CalendarEvent> events) {
  return !events.any(
    (event) => start.isBefore(event.end) && end.isAfter(event.start),
  );
}

_Clock? _parseClock(String value) {
  final parts = value.split(':');
  if (parts.length != 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return _Clock(hour, minute);
}

DateTime _nextWeekday(DateTime from, int targetWeekday) {
  var diff = targetWeekday - from.weekday;
  if (diff <= 0) diff += 7;
  return _dateOnly(from.add(Duration(days: diff)));
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _weekdayKey(DateTime date) {
  return const {
    DateTime.monday: 'monday',
    DateTime.tuesday: 'tuesday',
    DateTime.wednesday: 'wednesday',
    DateTime.thursday: 'thursday',
    DateTime.friday: 'friday',
    DateTime.saturday: 'saturday',
    DateTime.sunday: 'sunday',
  }[date.weekday]!;
}

String _formatSlotList(List<DateTime> slots) {
  return slots
      .map((slot) => '- ${_formatDate(slot)} a las ${_formatTime(slot)}')
      .join('\n');
}

String _formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

String _formatTime(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _isoDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String _firstNonEmpty(List<String?> values) {
  for (final value in values) {
    if (value != null && value.trim().isNotEmpty) return value.trim();
  }
  return '';
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

const _weekdays = {
  'lunes': DateTime.monday,
  'martes': DateTime.tuesday,
  'miercoles': DateTime.wednesday,
  'jueves': DateTime.thursday,
  'viernes': DateTime.friday,
  'sabado': DateTime.saturday,
  'domingo': DateTime.sunday,
};

class _Clock {
  const _Clock(this.hour, this.minute);

  final int hour;
  final int minute;
}
