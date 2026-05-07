import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:whatsapp_web_puppeteer/scheduling/scheduling_models.dart';

class LocalSchedulingStore {
  LocalSchedulingStore({
    required Directory dataDirectory,
    required Directory storeDirectory,
  }) : _availabilityFile = File(
         p.join(dataDirectory.path, 'availability.json'),
       ),
       _calendarEventsFile = File(
         p.join(dataDirectory.path, 'calendar_events.json'),
       ),
       _appointmentsFile = File(
         p.join(dataDirectory.path, 'appointments.json'),
       ),
       _draftsDirectory = Directory(
         p.join(storeDirectory.path, 'appointment_drafts'),
       );

  final File _availabilityFile;
  final File _calendarEventsFile;
  final File _appointmentsFile;
  final Directory _draftsDirectory;

  Future<void> ensureReady() async {
    if (!await _availabilityFile.exists()) {
      await _writeJson(
        _availabilityFile,
        AvailabilityConfig.defaultDental().toJson(),
      );
    }
    if (!await _calendarEventsFile.exists()) {
      await _writeJson(_calendarEventsFile, {
        'events': <Map<String, dynamic>>[],
      });
    }
    if (!await _appointmentsFile.exists()) {
      await _writeJson(_appointmentsFile, {
        'appointments': <Map<String, dynamic>>[],
      });
    }
    if (!await _draftsDirectory.exists()) {
      await _draftsDirectory.create(recursive: true);
    }
  }

  Future<AvailabilityConfig> loadAvailability() async {
    await ensureReady();
    return AvailabilityConfig.fromJson(
      await _readJsonObject(_availabilityFile),
    );
  }

  Future<List<CalendarEvent>> loadCalendarEvents() async {
    await ensureReady();
    final json = await _readJsonObject(_calendarEventsFile);
    final rawEvents = json['events'];
    if (rawEvents is! List) return <CalendarEvent>[];
    return rawEvents
        .whereType<Map>()
        .map(
          (event) => CalendarEvent.fromJson(Map<String, dynamic>.from(event)),
        )
        .toList();
  }

  Future<List<Appointment>> loadAppointments() async {
    await ensureReady();
    final json = await _readJsonObject(_appointmentsFile);
    final rawAppointments = json['appointments'];
    if (rawAppointments is! List) return <Appointment>[];
    return rawAppointments
        .whereType<Map>()
        .map(
          (appointment) =>
              Appointment.fromJson(Map<String, dynamic>.from(appointment)),
        )
        .toList();
  }

  Future<SchedulingDraft> loadDraft(String jid) async {
    await ensureReady();
    final file = _draftFile(jid);
    if (!await file.exists()) return SchedulingDraft.empty(jid);
    final json = await _readJsonObject(file);
    if (json.isEmpty) return SchedulingDraft.empty(jid);
    return SchedulingDraft.fromJson(json);
  }

  Future<void> saveDraft(SchedulingDraft draft) async {
    await ensureReady();
    await _writeJson(_draftFile(draft.jid), draft.toJson());
  }

  Future<void> clearDraft(String jid) async {
    final file = _draftFile(jid);
    if (await file.exists()) await file.delete();
  }

  Future<Appointment> createConfirmedAppointment({
    required String jid,
    required String name,
    required String service,
    required DateTime start,
    required DateTime end,
    String notes = '',
  }) async {
    await ensureReady();
    final now = DateTime.now();
    final id = 'appt_${now.microsecondsSinceEpoch}';
    final appointment = Appointment(
      id: id,
      jid: jid,
      name: name,
      service: service,
      start: start,
      end: end,
      status: 'confirmed',
      source: 'whatsapp',
      notes: notes,
      createdAt: now,
    );
    final event = CalendarEvent(
      id: 'evt_${now.microsecondsSinceEpoch}',
      type: 'appointment',
      status: 'confirmed',
      start: start,
      end: end,
      title: '$service - $name',
      appointmentId: id,
    );

    final appointmentsJson = await _readJsonObject(_appointmentsFile);
    final appointments = appointmentsJson['appointments'] is List
        ? List<dynamic>.from(appointmentsJson['appointments'] as List)
        : <dynamic>[];
    appointments.add(appointment.toJson());
    await _writeJson(_appointmentsFile, {'appointments': appointments});

    final eventsJson = await _readJsonObject(_calendarEventsFile);
    final events = eventsJson['events'] is List
        ? List<dynamic>.from(eventsJson['events'] as List)
        : <dynamic>[];
    events.add(event.toJson());
    await _writeJson(_calendarEventsFile, {'events': events});

    await clearDraft(jid);
    return appointment;
  }

  File _draftFile(String jid) {
    return File(p.join(_draftsDirectory.path, '${_safeFileName(jid)}.json'));
  }
}

Future<Map<String, dynamic>> _readJsonObject(File file) async {
  try {
    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {}
  return <String, dynamic>{};
}

Future<void> _writeJson(File file, Map<String, dynamic> json) async {
  if (!await file.parent.exists()) {
    await file.parent.create(recursive: true);
  }
  const encoder = JsonEncoder.withIndent('  ');
  await file.writeAsString('${encoder.convert(json)}\n');
}

String _safeFileName(String jid) {
  return jid.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
}
