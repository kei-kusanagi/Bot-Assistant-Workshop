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
    final managementDraft = await _store.loadManagementDraft(jid);
    if (managementDraft.phase != ManagementPhase.idle) {
      final reply = await _continueManagement(
        jid: jid,
        message: message,
        lower: lower,
        mgmt: managementDraft,
      );
      return reply;
    }

    if (_asksListAppointments(lower)) {
      await _store.clearDraft(jid);
      return _respondListFutureAppointments(jid);
    }

    if (_asksCancelAppointment(lower)) {
      await _store.clearDraft(jid);
      return _beginCancelFlow(jid, message, lower);
    }

    if (_asksRescheduleAppointment(lower)) {
      await _store.clearDraft(jid);
      return _beginRescheduleFlow(jid, message, lower);
    }

    final draft = await _store.loadDraft(jid);
    final hasActiveDraft = _hasAnyDraftValue(draft);
    final isScheduling = hasActiveDraft || _isBookingMessage(lower);
    if (!isScheduling) return null;

    await _store.clearManagementDraft(jid);

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

  Future<String?> _continueManagement({
    required String jid,
    required String message,
    required String lower,
    required SchedulingManagementDraft mgmt,
  }) async {
    switch (mgmt.phase) {
      case ManagementPhase.cancelPick:
        return _mgmtFinishCancelPick(jid, message, lower, mgmt);
      case ManagementPhase.cancelConfirm:
        return _mgmtFinishCancelConfirm(jid, lower, mgmt);
      case ManagementPhase.reschedulePick:
        return _mgmtFinishReschedulePick(jid, message, lower, mgmt);
      case ManagementPhase.rescheduleSlot:
        return _mgmtFinishRescheduleSlot(jid, message, lower, mgmt);
      case ManagementPhase.idle:
        return null;
    }
  }

  Future<String?> _mgmtFinishCancelPick(
    String jid,
    String message,
    String lower,
    SchedulingManagementDraft mgmt,
  ) async {
    final picked =
        _parseListSelection(message.trim()) ??
        _parseInlineAppointmentIndexFromNormalized(lower);
    if (picked == null ||
        picked < 1 ||
        picked > mgmt.candidateAppointmentIds.length) {
      return 'No reconoci el numero. Responde con el numero de la lista que te mostre antes.';
    }
    final appointmentId = mgmt.candidateAppointmentIds[picked - 1];
    final appt = await _store.appointmentByIdForJid(appointmentId, jid);
    if (appt == null) {
      await _store.clearManagementDraft(jid);
      return 'Ya no encuentro esa cita. Escribe de nuevo cancelar si aun necesitas ayuda.';
    }
    await _store.saveManagementDraft(
      mgmt.copyWith(
        phase: ManagementPhase.cancelConfirm,
        selectedAppointmentId: appointmentId,
        candidateAppointmentIds: [appointmentId],
      ),
    );
    return _confirmCancelPhrase(appt);
  }

  Future<String?> _mgmtFinishCancelConfirm(
    String jid,
    String lower,
    SchedulingManagementDraft mgmt,
  ) async {
    if (_userDeclines(lower)) {
      await _store.clearManagementDraft(jid);
      return 'Perfecto, dejo la cita igual. ¿Necesitas algo mas?';
    }
    if (!_userConfirmsCancellation(lower)) {
      return _confirmCancelPhraseOrHint(
        mgmt.selectedAppointmentId == null
            ? null
            : await _store.appointmentByIdForJid(
                mgmt.selectedAppointmentId!,
                jid,
              ),
      );
    }
    final id = mgmt.selectedAppointmentId;
    if (id == null) {
      await _store.clearManagementDraft(jid);
      return 'No tengo cual cita cancelar. Escribe cancelar mi cita de nuevo.';
    }
    await _store.cancelAppointmentById(appointmentId: id, jid: jid);
    await _store.clearManagementDraft(jid);
    return 'Listo: cancele esa cita en el calendario simulado. Si quieres otra, escribe agendar cita.';
  }

  Future<String?> _mgmtFinishReschedulePick(
    String jid,
    String message,
    String lower,
    SchedulingManagementDraft mgmt,
  ) async {
    final picked =
        _parseListSelection(message.trim()) ??
        _parseInlineAppointmentIndexFromNormalized(lower);
    if (picked == null ||
        picked < 1 ||
        picked > mgmt.candidateAppointmentIds.length) {
      return 'No reconoci el numero. Responde con el numero de la cita que quieres mover.';
    }
    final appointmentId = mgmt.candidateAppointmentIds[picked - 1];
    final appt = await _store.appointmentByIdForJid(appointmentId, jid);
    if (appt == null) {
      await _store.clearManagementDraft(jid);
      return 'Ya no encuentro esa cita. Intenta de nuevo con reprogramar cita.';
    }
    await _store.saveManagementDraft(
      mgmt.copyWith(
        phase: ManagementPhase.rescheduleSlot,
        selectedAppointmentId: appointmentId,
        candidateAppointmentIds: [appointmentId],
        newPreferredDate: '',
        newPreferredTime: '',
      ),
    );
    return 'Moveremos: ${_formatAppointmentLine(1, appt)}\n'
        '¿Que **nuevo** dia y horario prefieres? (puedes decir por ejemplo *martes 4pm* o *2026-05-12 16:00*).';
  }

  Future<String?> _mgmtFinishRescheduleSlot(
    String jid,
    String message,
    String lower,
    SchedulingManagementDraft mgmt,
  ) async {
    if (_userDeclines(lower)) {
      await _store.clearManagementDraft(jid);
      return 'De acuerdo, dejo la cita en su horario original.';
    }
    final id = mgmt.selectedAppointmentId;
    if (id == null) {
      await _store.clearManagementDraft(jid);
      return 'Hubo confusion con la cita. Escribe reprogramar cita otra vez.';
    }

    var newDateStr = mgmt.newPreferredDate;
    var newTimeStr = mgmt.newPreferredTime;
    final parsedDate = _parsePreferredDate(message);
    final parsedTime = _parsePreferredTime(message);
    if (parsedDate != null) {
      newDateStr = _isoDate(parsedDate);
    }
    if (parsedTime != null) {
      newTimeStr = parsedTime;
    }

    await _store.saveManagementDraft(
      mgmt.copyWith(newPreferredDate: newDateStr, newPreferredTime: newTimeStr),
    );

    final merged = mgmt.copyWith(
      newPreferredDate: newDateStr,
      newPreferredTime: newTimeStr,
    );
    final start = _newDateTimeFromMgmt(merged);
    if (start == null) {
      return 'Necesito el **dia** nuevo y la **hora** (por ejemplo viernes a las 3 de la tarde).';
    }
    final end = start.add(await _slotDuration());
    if (!await isSlotAvailable(start, end, ignoreAppointmentId: id)) {
      final alts = await availableSlots(
        start,
        limit: 3,
        ignoreAppointmentId: id,
      );
      if (alts.isEmpty) {
        return 'Ese horario no esta libre. ¿Probamos otro dia?';
      }
      return 'Ese horario no esta disponible. Opciones libres:\n${_formatSlotList(alts)}\n¿Cuál te sirve?';
    }

    try {
      final appt = await _store.rescheduleAppointment(
        oldAppointmentId: id,
        jid: jid,
        newStart: start,
        newEnd: end,
      );
      await _store.clearManagementDraft(jid);
      return 'Cita reprogramada en el calendario simulado:\n'
          'Servicio: ${appt.service}\n'
          'Nombre: ${appt.name}\n'
          'Nueva fecha: ${_formatDate(appt.start)}\n'
          'Nueva hora: ${_formatTime(appt.start)}';
    } on StateError catch (e) {
      await _store.clearManagementDraft(jid);
      return 'No pude reprogramar: $e';
    }
  }

  String _confirmCancelPhrase(Appointment appt) {
    return 'Voy a cancelar esta cita:\n${_formatAppointmentLine(1, appt)}\n'
        'Para confirmar escribe *si cancelar*. Si prefieres conservarla, escribe *no*.';
  }

  String _confirmCancelPhraseOrHint(Appointment? appt) {
    if (appt != null) return _confirmCancelPhrase(appt);
    return 'Para confirmar la cancelacion escribe *si cancelar*. Para conservar la cita escribe *no*.';
  }

  /// Si el mensaje incluye nueva fecha y hora, reprograma de un solo paso.
  Future<String?> _attemptRescheduleOneShot({
    required String jid,
    required String appointmentId,
    required String message,
  }) async {
    final parsedDate = _parsePreferredDate(message);
    final parsedTime = _parsePreferredTime(message);
    if (parsedDate == null || parsedTime == null) return null;
    final clock = _parseClock(parsedTime);
    if (clock == null) return null;
    final start = DateTime(
      parsedDate.year,
      parsedDate.month,
      parsedDate.day,
      clock.hour,
      clock.minute,
    );
    final end = start.add(await _slotDuration());
    if (!await isSlotAvailable(
      start,
      end,
      ignoreAppointmentId: appointmentId,
    )) {
      final alts = await availableSlots(
        start,
        limit: 3,
        ignoreAppointmentId: appointmentId,
      );
      await _store.saveManagementDraft(
        SchedulingManagementDraft(
          jid: jid,
          phase: ManagementPhase.rescheduleSlot,
          candidateAppointmentIds: [appointmentId],
          selectedAppointmentId: appointmentId,
          newPreferredDate: '',
          newPreferredTime: '',
          updatedAt: DateTime.now(),
        ),
      );
      if (alts.isEmpty) {
        return 'Ese horario no esta libre para reprogramar.\n'
            '¿Me dices otro dia y hora? Te dejo en el paso de reprogramacion.';
      }
      return 'Ese horario no esta disponible. Opciones libres:\n'
          '${_formatSlotList(alts)}\n¿Cuál te sirve? (Con fecha y hora en tu respuesta.)';
    }
    try {
      final appt = await _store.rescheduleAppointment(
        oldAppointmentId: appointmentId,
        jid: jid,
        newStart: start,
        newEnd: end,
      );
      await _store.clearManagementDraft(jid);
      return 'Cita reprogramada en el calendario simulado:\n'
          'Servicio: ${appt.service}\n'
          'Nombre: ${appt.name}\n'
          'Nueva fecha: ${_formatDate(appt.start)}\n'
          'Nueva hora: ${_formatTime(appt.start)}';
    } on StateError catch (e) {
      await _store.clearManagementDraft(jid);
      return 'No pude reprogramar: $e';
    }
  }

  Future<String> _beginCancelFlow(
    String jid,
    String message,
    String normalizedLower,
  ) async {
    final list = await _store.futureAppointmentsForJid(jid);
    if (list.isEmpty) {
      return 'No tengo citas futuras activas registradas para este chat.';
    }
    if (list.length > 1) {
      final idx = _parseInlineAppointmentIndexFromNormalized(normalizedLower);
      if (idx != null && idx >= 1 && idx <= list.length) {
        final a = list[idx - 1];
        await _store.saveManagementDraft(
          SchedulingManagementDraft(
            jid: jid,
            phase: ManagementPhase.cancelConfirm,
            candidateAppointmentIds: [a.id],
            selectedAppointmentId: a.id,
            newPreferredDate: '',
            newPreferredTime: '',
            updatedAt: DateTime.now(),
          ),
        );
        return '${_confirmCancelPhrase(a)}\n'
            '(Veo que referiste la cita *$idx*.)';
      }
      await _store.saveManagementDraft(
        SchedulingManagementDraft(
          jid: jid,
          phase: ManagementPhase.cancelPick,
          candidateAppointmentIds: list.map((e) => e.id).toList(),
          selectedAppointmentId: null,
          newPreferredDate: '',
          newPreferredTime: '',
          updatedAt: DateTime.now(),
        ),
      );
      return '${_numberedAppointmentsHeading(list, 'Tienes varias citas. ¿Cuál quieres **cancelar**? Responde con el numero:\n')}\n'
          'Tip: también puedes decir por ejemplo *cancelar cita 2*.';
    }
    final a = list.first;
    await _store.saveManagementDraft(
      SchedulingManagementDraft(
        jid: jid,
        phase: ManagementPhase.cancelConfirm,
        candidateAppointmentIds: [a.id],
        selectedAppointmentId: a.id,
        newPreferredDate: '',
        newPreferredTime: '',
        updatedAt: DateTime.now(),
      ),
    );
    return _confirmCancelPhrase(a);
  }

  Future<String> _beginRescheduleFlow(
    String jid,
    String message,
    String normalizedLower,
  ) async {
    final list = await _store.futureAppointmentsForJid(jid);
    if (list.isEmpty) {
      return 'No hay citas futuras para mover. ¿Quieres agendar una nueva?';
    }
    if (list.length > 1) {
      final idx = _parseInlineAppointmentIndexFromNormalized(normalizedLower);
      if (idx != null && idx >= 1 && idx <= list.length) {
        final chosen = list[idx - 1];
        final oneShot = await _attemptRescheduleOneShot(
          jid: jid,
          appointmentId: chosen.id,
          message: message,
        );
        if (oneShot != null) return oneShot;

        await _store.saveManagementDraft(
          SchedulingManagementDraft(
            jid: jid,
            phase: ManagementPhase.rescheduleSlot,
            candidateAppointmentIds: [chosen.id],
            selectedAppointmentId: chosen.id,
            newPreferredDate: '',
            newPreferredTime: '',
            updatedAt: DateTime.now(),
          ),
        );
        return 'Muevo la **cita $idx**:\n${_formatAppointmentLine(1, chosen)}\n'
            '¿Que **nuevo** dia y horario prefieres?';
      }
      await _store.saveManagementDraft(
        SchedulingManagementDraft(
          jid: jid,
          phase: ManagementPhase.reschedulePick,
          candidateAppointmentIds: list.map((e) => e.id).toList(),
          selectedAppointmentId: null,
          newPreferredDate: '',
          newPreferredTime: '',
          updatedAt: DateTime.now(),
        ),
      );
      return '${_numberedAppointmentsHeading(list, 'Tienes varias citas. ¿Cuál quieres **reprogramar**? Responde con el numero:\n')}\n'
          'Tip: *reprogramar cita 2* o en un solo mensaje *reprogramar cita 2 martes 4pm*.';
    }
    final a = list.first;
    final oneShot = await _attemptRescheduleOneShot(
      jid: jid,
      appointmentId: a.id,
      message: message,
    );
    if (oneShot != null) return oneShot;

    await _store.saveManagementDraft(
      SchedulingManagementDraft(
        jid: jid,
        phase: ManagementPhase.rescheduleSlot,
        candidateAppointmentIds: [a.id],
        selectedAppointmentId: a.id,
        newPreferredDate: '',
        newPreferredTime: '',
        updatedAt: DateTime.now(),
      ),
    );
    return 'Moveremos: ${_formatAppointmentLine(1, a)}\n'
        '¿Que **nuevo** dia y horario prefieres?';
  }

  Future<String> _respondListFutureAppointments(String jid) async {
    final list = await _store.futureAppointmentsForJid(jid);
    if (list.isEmpty) {
      return 'No tengo citas futuras registradas para este chat.';
    }
    return _numberedAppointmentsHeading(list, 'Tus proximas citas:\n');
  }

  String _numberedAppointmentsHeading(List<Appointment> list, String header) {
    final buf = StringBuffer(header);
    for (var i = 0; i < list.length; i++) {
      buf.writeln(_formatAppointmentLine(i + 1, list[i]));
    }
    return buf.toString().trim();
  }

  String _formatAppointmentLine(int index, Appointment a) {
    return '$index. ${a.service} - ${_formatDate(a.start)} ${_formatTime(a.start)} (${a.name})';
  }

  Future<List<DateTime>> availableSlots(
    DateTime date, {
    int limit = 3,
    String? ignoreAppointmentId,
  }) async {
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
    final events = await _blockingEvents(
      ignoreAppointmentId: ignoreAppointmentId,
    );
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

  Future<bool> isSlotAvailable(
    DateTime start,
    DateTime end, {
    String? ignoreAppointmentId,
  }) async {
    final slots = await availableSlots(
      start,
      limit: 100,
      ignoreAppointmentId: ignoreAppointmentId,
    );
    return slots.any((slot) => slot.isAtSameMomentAs(start));
  }

  Future<Duration> _slotDuration() async {
    final availability = await _store.loadAvailability();
    return Duration(minutes: availability.slotMinutes);
  }

  Future<List<CalendarEvent>> _blockingEvents({
    String? ignoreAppointmentId,
  }) async {
    final events = await _store.loadCalendarEvents();
    return events
        .where((event) => event.status != 'cancelled')
        .where((event) => event.type == 'appointment' || event.type == 'block')
        .where(
          (event) =>
              ignoreAppointmentId == null ||
              event.appointmentId != ignoreAppointmentId,
        )
        .toList();
  }
}

DateTime? _newDateTimeFromMgmt(SchedulingManagementDraft m) {
  if (m.newPreferredDate.isEmpty || m.newPreferredTime.isEmpty) return null;
  final date = DateTime.tryParse(m.newPreferredDate);
  final clock = _parseClock(m.newPreferredTime);
  if (date == null || clock == null) return null;
  return DateTime(date.year, date.month, date.day, clock.hour, clock.minute);
}

int? _parseListSelection(String raw) => int.tryParse(raw);

/// Reconoce "cita 2", "la 2", "opcion 3", etc. Sobre texto ya normalizado [_normalize].
int? _parseInlineAppointmentIndexFromNormalized(String normalizedLower) {
  final n = normalizedLower.trim();
  if (n.isEmpty) return null;
  final patterns = <RegExp>[
    RegExp(r'\bcita\s+(?:numero\s+)?(\d{1,2})\b'),
    RegExp(r'\bopcion\s+(\d{1,2})\b'),
    RegExp(r'\bla\s+(\d{1,2})\b'),
    RegExp(r'\bel\s+(\d{1,2})\b'),
    RegExp(r'\bnumero\s+(\d{1,2})\b'),
  ];
  for (final re in patterns) {
    final m = re.firstMatch(n);
    if (m != null) {
      final v = int.tryParse(m.group(1)!);
      if (v != null && v >= 1 && v <= 50) return v;
    }
  }
  return null;
}

bool _userDeclines(String lower) {
  final t = lower.trim();
  return t == 'no' ||
      t.startsWith('no ') ||
      t.contains('mejor no') ||
      t.contains('dejala') ||
      t.contains('déjala') ||
      t.contains('olvida') ||
      t.contains('cancela eso no');
}

bool _userConfirmsCancellation(String lower) {
  return lower.contains('si cancelar') ||
      lower.contains('sí cancelar') ||
      lower.contains('si, cancelar') ||
      lower.contains('sí, cancelar') ||
      lower.contains('confirmo cancelar') ||
      lower.contains('confirmo la cancelacion') ||
      lower.contains('confirmo la cancelación') ||
      lower.contains('adelante cancela') ||
      lower.contains('si por favor cancela') ||
      lower.contains('sí por favor cancela');
}

bool _asksListAppointments(String lower) {
  return lower.contains('mis citas') ||
      lower.contains('mi cita') ||
      lower.contains('proxima cita') ||
      lower.contains('próxima cita') ||
      lower.contains('que citas tengo') ||
      lower.contains('qué citas tengo') ||
      lower.contains('citas activas');
}

bool _asksCancelAppointment(String lower) {
  final mentionsAppointment = lower.contains('cita') || lower.contains('visit');
  if (mentionsAppointment &&
      (lower.contains('cancel') ||
          lower.contains('anular') ||
          lower.contains('baja'))) {
    return true;
  }
  return lower.contains('dar de baja mi cita') ||
      lower.contains('baja la cita');
}

bool _asksRescheduleAppointment(String lower) {
  return lower.contains('reprogram') ||
      lower.contains('reagendar') ||
      lower.contains('cambiar la cita') ||
      lower.contains('cambiar mi cita') ||
      lower.contains('cambiar el horario') ||
      lower.contains('cambiar horario') ||
      lower.contains('cambiar la fecha') ||
      lower.contains('mover mi cita') ||
      lower.contains('mover la cita');
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

bool _isBookingMessage(String lower) {
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
      lower.contains('qué dias') ||
      lower.contains('que horarios') ||
      lower.contains('qué horarios') ||
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
