import 'package:whatsapp_web_puppeteer/ai/ai_context.dart';
import 'package:whatsapp_web_puppeteer/scheduling/local_scheduling_store.dart';
import 'package:whatsapp_web_puppeteer/scheduling/scheduling_models.dart';

/// Ancla la agenda cargada desde seed (mayo demo) incluso si el reloj del PC no coincide.
const _kDemoCalendarYear = 2026;

enum _AvailScope { thisWeek, nextWeek, restOfMay }

enum _DayPeriod { morning, afternoon, evening }

class _AvailWindow {
  const _AvailWindow({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

class SchedulingService {
  SchedulingService({required LocalSchedulingStore store}) : _store = store;

  final LocalSchedulingStore _store;

  /// Borra borrador de cita y gestiones a medias (cancelar / reprogramar).
  Future<void> resetLocalSchedulingState(String jid) async {
    await _store.clearDraft(jid);
    await _store.clearManagementDraft(jid);
  }

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

    if (_asksListAppointments(lower) || _asksWhenIsMyAppointment(lower)) {
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

    final listFollowUp = await _maybeAppointmentListFollowUp(
      jid: jid,
      message: message,
      lower: lower,
      businessProfile: businessProfile,
      conversationContext: conversationContext,
    );
    if (listFollowUp != null) {
      await _store.clearDraft(jid);
      return listFollowUp;
    }

    if (_schedulingYieldsToSmalltalk(lower)) {
      final d = await _store.loadDraft(jid);
      if (_hasAnyDraftValue(d)) {
        await _store.clearDraft(jid);
      }
      return null;
    }

    final draft = await _store.loadDraft(jid);
    final hasActiveDraft = _hasAnyDraftValue(draft);
    final availFollowUp =
        !_asksForAvailability(lower) &&
        _looksLikePeriodRefinement(lower, conversationContext) &&
        _lastAssistantAvailScope(conversationContext) != null;
    final isScheduling =
        hasActiveDraft ||
        _isBookingMessage(lower) ||
        availFollowUp ||
        _asksForAvailability(lower);
    if (!isScheduling) return null;

    await _store.clearManagementDraft(jid);

    final updatedDraft = _mergeDraft(
      draft: draft,
      message: message,
      businessProfile: businessProfile,
      conversationContext: conversationContext,
    );

    if (_asksForAvailability(lower) || availFollowUp) {
      await _store.saveDraft(updatedDraft);
      return _handleAvailabilityInquiry(
        message: message,
        lower: lower,
        updatedDraft: updatedDraft,
        conversationContext: conversationContext,
      );
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

  /// Tras mostrar citas futuras: "solo la mía", "la 2", servicio corto sin nueva reserva.
  Future<String?> _maybeAppointmentListFollowUp({
    required String jid,
    required String message,
    required String lower,
    required BusinessProfile businessProfile,
    required ConversationContext conversationContext,
  }) async {
    if (!_assistantRecentlyListedFutureAppointments(conversationContext)) {
      return null;
    }
    if (!_userNarrowsListedAppointmentReply(message, businessProfile)) {
      return null;
    }
    if (_asksListAppointments(lower) ||
        _asksWhenIsMyAppointment(lower) ||
        _asksCancelAppointment(lower) ||
        _asksRescheduleAppointment(lower)) {
      return null;
    }
    final newBookingIntent =
        _isBookingMessage(lower) ||
        _asksForAvailability(lower) ||
        lower.contains('disponib');
    final soloMine =
        _normalize(lower).contains('solo') &&
        (_normalize(lower).contains('mia') ||
            _normalize(lower).contains('mio') ||
            _normalize(lower).contains('mi cita'));
    final cualMine =
        _normalize(lower).contains('cual') && _normalize(lower).contains('mia');
    if (newBookingIntent && !(soloMine || cualMine)) {
      return null;
    }

    final list = await _store.futureAppointmentsForJid(jid);
    if (list.isEmpty) return null;

    final n = _normalize(lower);

    final pickIdx = _parseOrdinalAppointmentPick(n);
    if (pickIdx != null) {
      if (pickIdx < 1 || pickIdx > list.length) {
        return 'En la lista solo hay numeros del **1** al **${list.length}**. '
            'Responde por ejemplo *la 1* o *la 2*.';
      }
      final a = list[pickIdx - 1];
      return 'Esta es la **$pickIdx**:\n${_formatAppointmentLine(pickIdx, a)}';
    }

    if (soloMine || cualMine) {
      final nombre = conversationContext.facts['nombre']?.trim();
      if (nombre == null || nombre.isEmpty) {
        if (list.length == 1) {
          return 'La unica cita futura que veo en este chat es:\n'
              '${_formatAppointmentLine(1, list.first)}';
        }
        return 'Hay **${list.length}** citas; para decirte *la tuya* necesito tu nombre '
            'en memoria o que elijas numero (*la 1*, *la 2*...).\n'
            '${_numberedAppointmentsHeading(list, '')}';
      }
      final nomN = _normalize(nombre);
      final parts = nomN
          .split(RegExp(r'\s+'))
          .where((p) => p.length >= 2)
          .toList();
      final matches = list.where((a) {
        final an = _normalize(a.name);
        if (an.contains(nomN)) return true;
        if (parts.length >= 2) {
          return parts.every((p) => an.contains(p));
        }
        return parts.isNotEmpty && an.contains(parts.first);
      }).toList();
      if (matches.length == 1) {
        return 'La que coincide con *$nombre*:\n${_formatAppointmentLine(1, matches.first)}';
      }
      if (matches.isEmpty) {
        return 'No encontre una cita con nombre parecido a *$nombre*. '
            'Estas son las activas:\n${_numberedAppointmentsHeading(list, '')}\n'
            'Responde *la 1*, *la 2*...';
      }
      return 'Hay varias con datos parecidos. Elige:\n'
          '${_numberedAppointmentsHeading(matches, '')}';
    }

    final svc = _extractService(message, businessProfile);
    if (svc != null &&
        message.trim().length < 96 &&
        !_pricingIntentInMessage(n) &&
        !_asksForAvailability(lower)) {
      final matches = list.where((a) => a.service == svc).toList();
      if (matches.isEmpty) {
        return 'No veo una cita futura de **$svc** en este chat. '
            'Lista actual:\n${_numberedAppointmentsHeading(list, '')}';
      }
      if (matches.length == 1) {
        return 'La cita de **$svc**:\n${_formatAppointmentLine(1, matches.first)}';
      }
      return 'Hay varias de **$svc**. Cual te refieres?\n'
          '${_numberedAppointmentsHeading(matches, '')}\n'
          'Responde *la 1*, *la 2*... segun esta lista.';
    }

    return null;
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
    if (!start.isBefore(end)) return false;

    final availability = await _store.loadAvailability();
    final slotDur = Duration(minutes: availability.slotMinutes);
    if (end.difference(start) != slotDur) return false;

    final dayOnly = _dateOnly(start);
    final dateText = _isoDate(dayOnly);
    if (availability.blockedDates.any((b) => b.date == dateText)) {
      return false;
    }

    final now = DateTime.now();
    final minStart = now.add(Duration(hours: availability.minNoticeHours));
    if (!start.isAfter(minStart)) return false;

    final dayKey = _weekdayKey(dayOnly);
    final ranges = availability.workingHours[dayKey] ?? const <TimeRange>[];
    if (ranges.isEmpty) return false;

    var alignedWithGrid = false;
    for (final range in ranges) {
      final startParts = _parseClock(range.start);
      final endParts = _parseClock(range.end);
      if (startParts == null || endParts == null) continue;

      var cursor = DateTime(
        dayOnly.year,
        dayOnly.month,
        dayOnly.day,
        startParts.hour,
        startParts.minute,
      );
      final rangeEnd = DateTime(
        dayOnly.year,
        dayOnly.month,
        dayOnly.day,
        endParts.hour,
        endParts.minute,
      );

      while (cursor.add(slotDur).compareTo(rangeEnd) <= 0) {
        if (cursor.isAtSameMomentAs(start)) {
          alignedWithGrid = true;
          break;
        }
        cursor = cursor.add(slotDur);
      }
      if (alignedWithGrid) break;
    }
    if (!alignedWithGrid) return false;

    final events = await _blockingEvents(
      ignoreAppointmentId: ignoreAppointmentId,
    );
    return _isFree(start, end, events);
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

  /// Disponibilidad vaga vs dia concreto; marca franjas mañana/tarde/noche.
  Future<String> _handleAvailabilityInquiry({
    required String message,
    required String lower,
    required SchedulingDraft updatedDraft,
    required ConversationContext conversationContext,
  }) async {
    final period = _parseDayPeriod(lower);
    final preferredDate =
        _parsePreferredDate(message) ?? _dateFromDraft(updatedDraft);

    if (preferredDate != null) {
      return _replySlotsForPreferredDay(preferredDate, period);
    }

    final lastScope =
        period != null && _looksLikePeriodRefinement(lower, conversationContext)
        ? _lastAssistantAvailScope(conversationContext)
        : null;

    if (lastScope != null && period != null) {
      final range = _availDateRange(lastScope);
      return _replyConcreteSlotsAfterPeriod(range, period);
    }

    final scope = _inferAvailScope(lower);
    final range = _availDateRange(scope);
    final ranked = await _rankWeekdaysByFreeSlots(
      range.start,
      range.end,
      period: period,
    );

    return await _formatBroadAvailabilityReply(
      ranked: ranked,
      scope: scope,
      window: range,
      appliedPeriod: period,
    );
  }

  Future<String> _replySlotsForPreferredDay(
    DateTime date,
    _DayPeriod? period,
  ) async {
    var slots = await availableSlots(date, limit: 100);
    slots = _filterSlotsByPeriod(slots, period);
    final top = slots.take(3).toList();
    if (top.isEmpty) {
      return 'No veo huecos disponibles${_periodHintSpanish(period)} para '
          '${_formatDate(date)}. ¿Probamos otro dia o prefieres otra franja '
          '(mañana antes de las 14:00, tarde 14:00-18:00, noche después de las 18:00)?';
    }
    final franja = switch (period) {
      null => '',
      _DayPeriod.morning => ' (priorizando la mañana)',
      _DayPeriod.afternoon => ' (priorizando la tarde)',
      _DayPeriod.evening => ' (priorizando la noche)',
    };
    return 'Tengo estos horarios libres para ${_formatDate(date)}$franja:\n'
        '${_formatSlotList(top)}\n'
        '¿Cuál prefieres para reservarlo?';
  }

  Future<String> _replyConcreteSlotsAfterPeriod(
    _AvailWindow window,
    _DayPeriod period,
  ) async {
    final ranked = await _rankWeekdaysByFreeSlots(
      window.start,
      window.end,
      period: period,
    );
    if (ranked.isEmpty) {
      return 'Del ${_formatDate(window.start)} al ${_formatDate(window.end)}, '
          'casi no hay huecos${_periodHintSpanish(period)}.\n'
          '¿Quieres probar otra franja (mañana/tarde/noche) o mencionar un dia '
          'concreto?';
    }

    final topDays = ranked.take(3).map((e) => e.day).toList();
    final picks = await _collectSampleSlotsLines(
      topDays,
      period,
      maxEntries: 5,
    );
    if (picks.isEmpty) {
      return 'No encuentro ejemplos concretos${_periodHintSpanish(period)} '
          'entre el ${_formatDate(window.start)} y el ${_formatDate(window.end)}.';
    }

    final head =
        '${_periodPreferenceLead(period)}, estos huecos siguen libres'
        '${_periodHintSpanish(period)} dentro del ${_formatHumanSpan(window)}:';
    return '$head\n${picks.take(5).join('\n')}\n'
        'Si me dices cual eliges (dia y hora), lo siguiente es confirmarlo en '
        'tu agenda.';
  }

  String _periodPreferenceLead(_DayPeriod period) => switch (period) {
    _DayPeriod.morning => 'Por la mañana',
    _DayPeriod.afternoon => 'Por la tarde',
    _DayPeriod.evening => 'Por la noche',
  };

  Future<List<({DateTime day, int count})>> _rankWeekdaysByFreeSlots(
    DateTime start,
    DateTime end, {
    _DayPeriod? period,
    int skipIfBelow = 0,
  }) async {
    final out = <({DateTime day, int count})>[];
    for (
      var d = _dateOnly(start);
      !d.isAfter(_dateOnly(end));
      d = d.add(const Duration(days: 1))
    ) {
      var slots = await availableSlots(d, limit: 500);
      slots = _filterSlotsByPeriod(slots, period);
      final count = slots.length;
      if (count <= skipIfBelow) continue;
      out.add((day: d, count: count));
    }
    out.sort((a, b) => b.count.compareTo(a.count));
    return out;
  }

  List<DateTime> _filterSlotsByPeriod(
    List<DateTime> slots,
    _DayPeriod? period,
  ) {
    if (period == null) return slots;
    return slots.where((s) => _slotMatchesPeriod(s, period)).toList();
  }

  bool _slotMatchesPeriod(DateTime slotStart, _DayPeriod period) {
    final h = slotStart.hour;
    return switch (period) {
      _DayPeriod.morning => h < 14,
      _DayPeriod.afternoon => h >= 14 && h < 18,
      _DayPeriod.evening => h >= 18,
    };
  }

  String _periodHintSpanish(_DayPeriod? p) {
    return switch (p) {
      null => '',
      _DayPeriod.morning => ' por la mañana',
      _DayPeriod.afternoon => ' por la tarde',
      _DayPeriod.evening => ' por la noche',
    };
  }

  Future<List<String>> _collectSampleSlotsLines(
    Iterable<DateTime> days,
    _DayPeriod period, {
    int maxEntries = 5,
  }) async {
    final out = <String>[];
    for (final day in days) {
      final filtered = _filterSlotsByPeriod(
        await availableSlots(day, limit: 48),
        period,
      );
      for (final slot in filtered.take(2)) {
        out.add('- ${_formatDate(slot)} a las ${_formatTime(slot)}');
        if (out.length >= maxEntries) return out;
      }
    }
    return out;
  }

  Future<String> _formatBroadAvailabilityReply({
    required List<({DateTime day, int count})> ranked,
    required _AvailScope scope,
    required _AvailWindow window,
    required _DayPeriod? appliedPeriod,
  }) async {
    if (ranked.isEmpty) {
      final scopeHints = switch (scope) {
        _AvailScope.thisWeek => '**la siguiente semana** o **resto del mes**',
        _AvailScope.nextWeek => '**esta semana** o **resto del mes**',
        _AvailScope.restOfMay => '**esta semana** o **la siguiente semana**',
      };
      return 'En el lapso ${_formatHumanSpan(window)} no veo dias laborales '
          'con huecos claros${_periodHintSpanish(appliedPeriod)}. '
          '¿Prefieres otra mirada ($scopeHints) o dar un dia concreto?';
    }

    final topDays = ranked.take(3).toList();
    final joined = topDays
        .map(
          (e) =>
              '${_weekdaySpanish(e.day.weekday)} ${_formatDate(e.day)} '
              '(unos ${e.count} huecos libres${_franjaCue(appliedPeriod)})',
        )
        .join('; ');

    if (appliedPeriod != null) {
      final picks = await _collectSampleSlotsLines(
        topDays.map((e) => e.day),
        appliedPeriod,
        maxEntries: 5,
      );
      return '${_availIntroLine(scope)}\nYa marcaste que prefieres'
          '${_periodHintSpanish(appliedPeriod)}. Entre ${_formatHumanSpan(window)} '
          ', los dias con mas opciones ${_franjaCueCompact(appliedPeriod)} son: '
          '$joined.'
          '${picks.isEmpty ? '' : '\nAlgunos horarios ejemplo:\n${picks.take(5).join('\n')}'}\n'
          'Respondeme cual te sirve o dime un dia y horario exactos en un mensaje.';
    }

    return '${_availIntroLine(scope)}\nEntre ${_formatHumanSpan(window)} '
        ', estos son los dias con **menos citas acumuladas** (hay mas huecos '
        'relativos): $joined.\n'
        '\n¿Te va mejor **por la mañana** (antes de las 14:00), **por la tarde** '
        '(14:00 a 18:00) o **por la noche** (después de las 18:00)? Con eso '
        'te sugiero ya horarios muy concretos.\n'
        'Si desde el primer mensaje me dices **dia y hora**, acoto la busqueda '
        'al instante.';
  }

  String _availIntroLine(_AvailScope scope) => switch (scope) {
    _AvailScope.thisWeek =>
      'Esta semana revisando la agenda de demostracion ($_kDemoCalendarYear).',
    _AvailScope.nextWeek =>
      'La siguiente semana en la agenda de demostracion ($_kDemoCalendarYear).',
    _AvailScope.restOfMay =>
      'En lo que queda de mayo (hasta ${_formatDate(DateTime(_kDemoCalendarYear, 5, 30))}) '
          'dentro del calendario demo.',
  };

  String _franjaCue(_DayPeriod? p) => p == null ? '' : ' en esa franja';

  String _franjaCueCompact(_DayPeriod p) => switch (p) {
    _DayPeriod.morning => 'por la mañana',
    _DayPeriod.afternoon => 'por la tarde',
    _DayPeriod.evening => 'por la noche',
  };

  String _formatHumanSpan(_AvailWindow w) =>
      '${_formatDate(w.start)} al ${_formatDate(w.end)}';

  _AvailWindow _availDateRange(_AvailScope scope) {
    final mayStart = DateTime(_kDemoCalendarYear, 5, 11);
    final mayEnd = DateTime(_kDemoCalendarYear, 5, 30);
    final ref = _effectiveRefDayForDemo(DateTime.now());

    switch (scope) {
      case _AvailScope.restOfMay:
        var start = ref.isBefore(mayStart) ? mayStart : ref;
        final startNorm = _dateOnly(start);
        if (startNorm.isAfter(_dateOnly(mayEnd))) {
          start = mayStart;
        }
        return _AvailWindow(start: _dateOnly(start), end: mayEnd);

      case _AvailScope.thisWeek:
        final monClip = () {
          final mon = _weekMondayOf(ref);
          return mon.isBefore(mayStart) ? mayStart : _dateOnly(mon);
        }();

        final sunRaw = monClip.add(const Duration(days: 6));
        var start = ref.isAfter(monClip) ? _dateOnly(ref) : _dateOnly(monClip);
        if (start.isBefore(mayStart)) {
          start = mayStart;
        }
        final endRaw = sunRaw.isAfter(mayEnd) ? mayEnd : _dateOnly(sunRaw);

        if (start.isAfter(endRaw)) {
          return _AvailWindow(start: mayStart, end: mayEnd);
        }
        return _AvailWindow(start: start, end: endRaw);

      case _AvailScope.nextWeek:
        final weekMon = _weekMondayOf(ref);
        final anchorMon = weekMon.isBefore(mayStart) ? mayStart : weekMon;
        final nextMon = anchorMon.add(const Duration(days: 7));
        final nextSun = nextMon.add(const Duration(days: 6));
        var start = _dateOnly(nextMon);
        if (start.isBefore(mayStart)) start = mayStart;
        var end = nextSun.isAfter(mayEnd) ? mayEnd : _dateOnly(nextSun);
        if (start.isAfter(end)) {
          return _AvailWindow(start: mayStart, end: mayEnd);
        }
        return _AvailWindow(start: start, end: end);
    }
  }
}

DateTime _effectiveRefDayForDemo(DateTime now) {
  final mayStart = DateTime(_kDemoCalendarYear, 5, 11);
  final mayEnd = DateTime(_kDemoCalendarYear, 5, 30);
  final d = _dateOnly(now);
  if (!d.isBefore(mayStart) && !d.isAfter(mayEnd)) {
    return d;
  }
  return mayStart;
}

DateTime _weekMondayOf(DateTime d) =>
    _dateOnly(d.subtract(Duration(days: d.weekday - DateTime.monday)));

String _weekdaySpanish(int weekday) {
  switch (weekday) {
    case DateTime.monday:
      return 'Lunes';
    case DateTime.tuesday:
      return 'Martes';
    case DateTime.wednesday:
      return 'Miercoles';
    case DateTime.thursday:
      return 'Jueves';
    case DateTime.friday:
      return 'Viernes';
    case DateTime.saturday:
      return 'Sabado';
    case DateTime.sunday:
      return 'Domingo';
    default:
      return '?';
  }
}

_AvailScope _inferAvailScope(String lower) {
  if (lower.contains('resto del mes')) {
    return _AvailScope.restOfMay;
  }
  if (lower.contains('lo que queda')) {
    return _AvailScope.restOfMay;
  }
  if (lower.contains('en mayo')) {
    return _AvailScope.restOfMay;
  }
  if (lower.contains('este mes')) {
    return _AvailScope.restOfMay;
  }
  if (lower.contains('siguiente semana') ||
      lower.contains('proxima semana') ||
      lower.contains('semana que viene') ||
      lower.contains('la semana siguiente') ||
      lower.contains('semana entrante')) {
    return _AvailScope.nextWeek;
  }
  return _AvailScope.thisWeek;
}

_DayPeriod? _parseDayPeriod(String lower) {
  if (lower.contains('por la noche') || lower.contains('en la noche')) {
    return _DayPeriod.evening;
  }
  if (lower.contains('por la tarde') ||
      lower.contains('en la tarde') ||
      lower.contains('de tarde') ||
      RegExp(r'\btarde\b').hasMatch(lower)) {
    return _DayPeriod.afternoon;
  }
  if (lower.contains('por la manana') ||
      lower.contains('en la manana') ||
      lower.contains('media manana')) {
    return _DayPeriod.morning;
  }
  return null;
}

bool _containsBroadAvailabilityIntent(String lower) {
  return lower.contains('disponibilidad') ||
      lower.contains('que dias') ||
      lower.contains('qué dias') ||
      lower.contains('que dia') ||
      lower.contains('qué dia') ||
      lower.contains('horarios disponibles') ||
      lower.contains('horarios libres');
}

bool _looksLikePeriodRefinement(String lower, ConversationContext ctx) {
  final parsed = _parseDayPeriod(lower);
  if (parsed == null) {
    return false;
  }
  if (lower.length > 140) {
    return false;
  }
  if (_lastAssistantAvailScope(ctx) == null) {
    return false;
  }
  if (_containsBroadAvailabilityIntent(lower)) {
    return false;
  }
  return true;
}

_AvailScope? _lastAssistantAvailScope(ConversationContext ctx) {
  for (var i = ctx.recentMessages.length - 1; i >= 0; i--) {
    final m = ctx.recentMessages[i];
    if (m.role != 'assistant') {
      continue;
    }
    final t = _normalize(m.text);
    if (!(t.contains('menos citas acumuladas') ||
        t.contains('mas huecos') ||
        t.contains('huecos relativos'))) {
      continue;
    }
    if (t.contains('en lo que queda de mayo')) {
      return _AvailScope.restOfMay;
    }
    if (t.contains('la siguiente semana en la agenda') ||
        t.contains('siguiente semana en la agenda')) {
      return _AvailScope.nextWeek;
    }
    if (t.contains('esta semana revisando')) {
      return _AvailScope.thisWeek;
    }
  }
  return null;
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

/// Intención "¿cuándo / qué día es mi cita ya existente?" (no confundir con agendar).
bool _asksWhenIsMyAppointment(String lower) {
  if (RegExp(r'que\s+dia\s+prefier|cual\s+dia\s+prefier').hasMatch(lower)) {
    return false;
  }
  if (lower.contains('ya tengo') && lower.contains('cita')) return true;
  if (lower.contains('si ya tengo') && lower.contains('cita')) return true;
  if (lower.contains('no recuerdo') &&
      (lower.contains('que dia') ||
          lower.contains('cuando') ||
          lower.contains('cita') ||
          lower.contains('fecha'))) {
    return true;
  }
  if (lower.contains('quiero saber') &&
      lower.contains('cita') &&
      (lower.contains('tengo') ||
          lower.contains('si ya') ||
          lower.contains('ya tengo') ||
          lower.contains('si ya tengo'))) {
    return true;
  }
  if (lower.contains('cita programada') &&
      (lower.contains('cuando') ||
          lower.contains('que dia') ||
          lower.contains('que hora'))) {
    return true;
  }
  if ((lower.contains('que dia') || lower.contains('cuando')) &&
      (lower.contains('tengo programad') ||
          lower.contains('tengo agendad') ||
          lower.contains('tengo la cita'))) {
    return true;
  }
  if (lower.contains('dia tengo') && lower.contains('programad')) return true;
  return false;
}

bool _assistantRecentlyListedFutureAppointments(ConversationContext ctx) {
  for (var i = ctx.recentMessages.length - 1; i >= 0; i--) {
    final m = ctx.recentMessages[i];
    if (m.role != 'assistant') continue;
    final t = m.text.toLowerCase();
    if (t.contains('no tengo citas futuras') ||
        t.contains('no hay citas futuras')) {
      return false;
    }
    if (t.contains('proximas citas')) {
      return !t.contains('cancelar') && !t.contains('reprogramar');
    }
    if (RegExp(r'^\d+\.\s', multiLine: true).hasMatch(m.text) &&
        !t.contains('cancelar') &&
        !t.contains('reprogramar')) {
      return true;
    }
    return false;
  }
  return false;
}

bool _pricingIntentInMessage(String normalizedLower) {
  return normalizedLower.contains('precio') ||
      normalizedLower.contains('presio') ||
      normalizedLower.contains('costo') ||
      normalizedLower.contains('cuanto');
}

bool _userNarrowsListedAppointmentReply(
  String message,
  BusinessProfile profile,
) {
  final lower = message.trim();
  final n = _normalize(lower);
  if (n.length > 160) return false;

  if (_parseOrdinalAppointmentPick(n) != null) return true;

  if (RegExp(
    r'\b(?:la|el)\s+(primera|segunda|tercera|cuarta|quinta)\b',
  ).hasMatch(n)) {
    return true;
  }

  if (n.contains('solo') &&
      (n.contains('mia') || n.contains('mio') || n.contains('mi cita'))) {
    return true;
  }
  if (n.contains('cual') && n.contains('mia')) return true;

  final svc = _extractService(message, profile);
  if (svc != null &&
      lower.length < 96 &&
      !_pricingIntentInMessage(n) &&
      !n.contains('agendar') &&
      !n.contains('quiero cita') &&
      !n.contains('disponib')) {
    return true;
  }

  return false;
}

int? _parseOrdinalAppointmentPick(String normalizedLower) {
  final compact = normalizedLower.trim();
  if (RegExp(r'^\s*([1-9]|1\d)\s*$').hasMatch(compact)) {
    return int.tryParse(compact.trim());
  }
  final opt = RegExp(
    r'\b(?:opcion|numero)\s+([1-9]|1\d)\b',
  ).firstMatch(normalizedLower);
  if (opt != null) return int.tryParse(opt.group(1)!);

  final la = RegExp(r'\bla\s+([1-9]|1\d)\b').firstMatch(normalizedLower);
  if (la != null) return int.tryParse(la.group(1)!);

  if (normalizedLower.contains('primera')) return 1;
  if (normalizedLower.contains('segunda')) return 2;
  if (normalizedLower.contains('tercera')) return 3;
  if (normalizedLower.contains('cuarta')) return 4;
  if (normalizedLower.contains('quinta')) return 5;
  return null;
}

/// Expuesto para el ejecutable: evitar prompt de nombre antes que aclaraciones tras ver citas.
bool awaitingAppointmentListClarification(
  ConversationContext ctx,
  String rawMessage,
  BusinessProfile profile,
) {
  return _assistantRecentlyListedFutureAppointments(ctx) &&
      _userNarrowsListedAppointmentReply(rawMessage, profile);
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

/// Listar / cancelar / reprogramar no deben bloquearse por falta de `nombre` en memoria.
bool schedulingSkipsNombrePrompt(String rawMessage) {
  final lower = _normalize(rawMessage.trim());
  return _asksListAppointments(lower) ||
      _asksWhenIsMyAppointment(lower) ||
      _asksCancelAppointment(lower) ||
      _asksRescheduleAppointment(lower);
}

enum _MissingField { name, service, date, time }

SchedulingDraft _mergeDraft({
  required SchedulingDraft draft,
  required String message,
  required BusinessProfile businessProfile,
  required ConversationContext conversationContext,
}) {
  final facts = conversationContext.facts;
  final lower = _normalize(message);
  var extracted = _extractFullName(message);
  final selfBook =
      _userSelfBooksForSelf(lower) || _userWantsSavedContactName(lower);
  if (selfBook &&
      _wordCount(extracted) <= 1 &&
      _wordCount(facts['nombre']) >= 2) {
    extracted = null;
  }
  final remembered = facts['nombre']?.trim();
  final preferRemembered =
      remembered != null &&
      remembered.isNotEmpty &&
      _isRicherPersonalName(remembered, draft.name);
  final mergedName = _firstNonEmpty([
    extracted,
    if (selfBook) remembered,
    if (preferRemembered) remembered,
    draft.name,
    remembered,
  ]);
  final mergedService = _firstNonEmpty([
    _extractService(message, businessProfile),
    draft.service,
    facts['servicio_deseado'],
  ]);
  final date = _parsePreferredDate(message);
  final time = _parsePreferredTime(message);
  return draft.copyWith(
    name: mergedName.isEmpty ? null : mergedName,
    service: mergedService.isEmpty ? null : mergedService,
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

bool _hasNextWeekMention(String lower) {
  return lower.contains('siguiente semana') ||
      lower.contains('proxima semana') ||
      lower.contains('semana que viene') ||
      lower.contains('la semana siguiente') ||
      lower.contains('semana entrante');
}

bool _asksForAvailability(String lower) {
  if (lower.contains('disponibilidad') ||
      lower.contains('disponible') ||
      lower.contains('que dias') ||
      lower.contains('qué dias') ||
      lower.contains('que horarios') ||
      lower.contains('qué horarios') ||
      lower.contains('horarios libres') ||
      lower.contains('espacio') ||
      lower.contains('huecos')) {
    return true;
  }
  if (_hasNextWeekMention(lower) &&
      (lower.contains('libre') ||
          lower.contains('disponib') ||
          lower.contains('hueco') ||
          lower.contains('tienes') ||
          RegExp(r'\b(no|nop)\b').hasMatch(lower))) {
    return true;
  }
  if ((lower.contains('que dia') || lower.contains('cual dia')) &&
      lower.contains('tienes') &&
      lower.contains('libre') &&
      (_hasNextWeekMention(lower) ||
          lower.contains('esta semana') ||
          lower.contains('proxima semana'))) {
    return true;
  }
  final looselyAboutBooking =
      lower.contains('cita') ||
      lower.contains('agendar') ||
      lower.contains('reserv');
  return looselyAboutBooking &&
      (lower.contains('esta semana') ||
          lower.contains('resto del mes') ||
          lower.contains('este mes') ||
          lower.contains('en mayo') ||
          _hasNextWeekMention(lower));
}

bool _userSelfBooksForSelf(String lower) {
  return lower.contains('al mio') ||
      lower.contains('al mismo') ||
      lower.contains('a mi nombre') ||
      lower.contains('para mi') ||
      lower.contains('mi mismo nombre') ||
      lower.contains('yo mismo') ||
      lower.contains('para mi mismo') ||
      lower.contains('la cita es para mi') ||
      lower.contains('cita para mi') ||
      lower.contains('agendo para mi') ||
      lower.contains('reservo para mi');
}

bool _userWantsSavedContactName(String lower) {
  return lower.contains('mismo nombre') ||
      lower.contains('el mismo nombre') ||
      lower.contains('nombre de antes') ||
      lower.contains('como antes') ||
      lower.contains('ya te di mi nombre') ||
      lower.contains('mi nombre ya') ||
      lower.contains('usa mi nombre') ||
      lower.contains('usa el mismo') ||
      lower.contains('usar mi nombre') ||
      lower.contains('usar el mismo') ||
      (lower.contains('el mismo') &&
          (lower.contains('nombre') ||
              lower.contains('me llam') ||
              lower.contains('paciente')));
}

bool _isRicherPersonalName(String candidate, String draftName) {
  final d = draftName.trim();
  final c = candidate.trim();
  if (c.isEmpty) return false;
  if (d.isEmpty) return true;
  final wc = _wordCount(c);
  final wd = _wordCount(d);
  if (wc > wd) return true;
  if (wc == wd && wc >= 2 && c.length > d.length + 3) return true;
  return false;
}

String? _extractFullName(String message) {
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

int _wordCount(String? value) {
  if (value == null || value.trim().isEmpty) return 0;
  return value.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
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

  final slashDMY = RegExp(
    r'\b(\d{1,2})[/.-](\d{1,2})(?:[/.-](\d{2,4}))?\b',
  ).firstMatch(lower);
  if (slashDMY != null) {
    final d = int.tryParse(slashDMY.group(1)!);
    final mo = int.tryParse(slashDMY.group(2)!);
    if (d != null && mo != null && d >= 1 && d <= 31 && mo >= 1 && mo <= 12) {
      final yRaw = slashDMY.group(3);
      var y = yRaw != null ? int.tryParse(yRaw) : null;
      if (y != null && y < 100) y += 2000;
      y ??= _kDemoCalendarYear;
      return _dateOnly(DateTime(y, mo, d));
    }
  }

  final mayOnly = _parseDemoCalendarDayHint(lower);
  if (mayOnly != null) return mayOnly;

  for (final entry in _weekdays.entries) {
    if (lower.contains(entry.key)) {
      return _nextWeekday(now, entry.value);
    }
  }
  return null;
}

DateTime? _parseDemoCalendarDayHint(String lower) {
  final mayStart = DateTime(_kDemoCalendarYear, 5, 11);
  final mayEnd = DateTime(_kDemoCalendarYear, 5, 30);
  final ref = _effectiveRefDayForDemo(DateTime.now());

  Match? m = RegExp(
    r'\b(?:el\s+)?(?:d[ií]a\s+)?(\d{1,2})\b(?:\s*(?:de\s*)?mayo)?',
  ).firstMatch(lower);
  m ??= RegExp(r'^\s*(\d{1,2})\s*$').firstMatch(lower.trim());
  if (m == null) return null;
  final day = int.tryParse(m.group(1)!);
  if (day == null || day < 1 || day > 31) return null;
  final candidate = DateTime(_kDemoCalendarYear, 5, day);
  if (!candidate.isBefore(mayStart) && !candidate.isAfter(mayEnd)) {
    return candidate;
  }
  if (!ref.isBefore(mayStart) && !ref.isAfter(mayEnd)) {
    final tryMonth = DateTime(ref.year, ref.month, day);
    if (!tryMonth.isBefore(mayStart) && !tryMonth.isAfter(mayEnd)) {
      return _dateOnly(tryMonth);
    }
  }
  return null;
}

bool _schedulingYieldsToSmalltalk(String lower) {
  final n = _normalize(lower);
  if (n.length > 120) return false;
  if (_isBookingMessage(n) || _asksForAvailability(n)) return false;
  if (n.contains('cita') || n.contains('agendar') || n.contains('agenda')) {
    return false;
  }
  if ((n.contains('sabes') || n.contains('saben')) &&
      n.contains('quien') &&
      (n.contains('yo') || n.contains('llamo'))) {
    return true;
  }
  if (n.contains('quien soy') || n.contains('como me llamo')) {
    return true;
  }
  return false;
}

String? _parsePreferredTime(String message) {
  var lower = _normalize(message).replaceAll(RegExp(r'\balas\b'), 'a las');
  lower = lower
      .replaceAll(RegExp(r'\b\d{4}-\d{2}-\d{2}\b'), ' ')
      .replaceAll(RegExp(r'\b\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}\b'), ' ');

  for (final match in RegExp(
    r'\b(\d{1,2}):(\d{2})\s*(am|pm|a\.m\.|p\.m\.)?\b',
  ).allMatches(lower)) {
    final clock = _coerceBookingClock(match);
    if (clock != null) return clock;
  }

  for (final match in RegExp(
    r'\ba las\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?\b',
  ).allMatches(lower)) {
    final clock = _coerceBookingClock(match);
    if (clock != null) return clock;
  }

  for (final match in RegExp(
    r'^\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?\s*$',
  ).allMatches(lower.trim())) {
    final clock = _coerceBookingClock(match);
    if (clock != null) return clock;
  }

  return null;
}

/// Interpreta grupo (hora[, minutos][, sufijo]) de [_parsePreferredTime].
String? _coerceBookingClock(RegExpMatch match) {
  var hour = int.tryParse(match.group(1) ?? '');
  final ms = match.group(2);
  final minute = ms != null && ms.isNotEmpty ? (int.tryParse(ms) ?? 0) : 0;
  final suffix = match.group(3);
  if (hour == null || hour > 23 || minute > 59) return null;
  if (suffix != null && suffix.contains('p') && hour < 12) hour += 12;
  if (suffix != null && suffix.contains('a') && hour == 12) hour = 0;
  if ((suffix == null || suffix.trim().isEmpty) && hour >= 1 && hour <= 7) {
    hour += 12;
  }
  if (hour < 8 || hour > 21) return null;
  return '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';
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
