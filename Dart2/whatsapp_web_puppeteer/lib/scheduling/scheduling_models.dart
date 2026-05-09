class AvailabilityConfig {
  const AvailabilityConfig({
    required this.timezone,
    required this.slotMinutes,
    required this.bookingWindowDays,
    required this.minNoticeHours,
    required this.workingHours,
    required this.blockedDates,
  });

  factory AvailabilityConfig.fromJson(Map<String, dynamic> json) {
    return AvailabilityConfig(
      timezone: _string(json['timezone'], fallback: 'America/Mexico_City'),
      slotMinutes: _int(json['slotMinutes'], fallback: 30),
      bookingWindowDays: _int(json['bookingWindowDays'], fallback: 30),
      minNoticeHours: _int(json['minNoticeHours'], fallback: 4),
      workingHours: _workingHours(json['workingHours']),
      blockedDates: _blockedDates(json['blockedDates']),
    );
  }

  final String timezone;
  final int slotMinutes;
  final int bookingWindowDays;
  final int minNoticeHours;
  final Map<String, List<TimeRange>> workingHours;
  final List<BlockedDate> blockedDates;

  Map<String, dynamic> toJson() => {
    'timezone': timezone,
    'slotMinutes': slotMinutes,
    'bookingWindowDays': bookingWindowDays,
    'minNoticeHours': minNoticeHours,
    'workingHours': workingHours.map(
      (key, value) =>
          MapEntry(key, value.map((range) => range.toJson()).toList()),
    ),
    'blockedDates': blockedDates.map((date) => date.toJson()).toList(),
  };

  static AvailabilityConfig defaultDental() {
    final weekdayHours = [const TimeRange(start: '10:00', end: '19:30')];
    return AvailabilityConfig(
      timezone: 'America/Mexico_City',
      slotMinutes: 30,
      bookingWindowDays: 30,
      minNoticeHours: 4,
      workingHours: {
        'monday': weekdayHours,
        'tuesday': weekdayHours,
        'wednesday': weekdayHours,
        'thursday': weekdayHours,
        'friday': weekdayHours,
        'saturday': const [],
        'sunday': const [],
      },
      blockedDates: const [],
    );
  }
}

class TimeRange {
  const TimeRange({required this.start, required this.end});

  factory TimeRange.fromJson(Map<String, dynamic> json) {
    return TimeRange(start: _string(json['start']), end: _string(json['end']));
  }

  final String start;
  final String end;

  Map<String, dynamic> toJson() => {'start': start, 'end': end};
}

class BlockedDate {
  const BlockedDate({required this.date, required this.reason});

  factory BlockedDate.fromJson(Map<String, dynamic> json) {
    return BlockedDate(
      date: _string(json['date']),
      reason: _string(json['reason']),
    );
  }

  final String date;
  final String reason;

  Map<String, dynamic> toJson() => {'date': date, 'reason': reason};
}

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.type,
    required this.status,
    required this.start,
    required this.end,
    required this.title,
    this.appointmentId,
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    return CalendarEvent(
      id: _string(json['id']),
      type: _string(json['type']),
      status: _string(json['status']),
      start: DateTime.parse(_string(json['start'])),
      end: DateTime.parse(_string(json['end'])),
      title: _string(json['title']),
      appointmentId: _nullableString(json['appointmentId']),
    );
  }

  final String id;
  final String type;
  final String status;
  final DateTime start;
  final DateTime end;
  final String title;
  final String? appointmentId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'status': status,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'title': title,
    if (appointmentId != null) 'appointmentId': appointmentId,
  };
}

class Appointment {
  const Appointment({
    required this.id,
    required this.jid,
    required this.name,
    required this.service,
    required this.start,
    required this.end,
    required this.status,
    required this.source,
    required this.notes,
    required this.createdAt,
  });

  factory Appointment.fromJson(Map<String, dynamic> json) {
    return Appointment(
      id: _string(json['id']),
      jid: _string(json['jid']),
      name: _string(json['name']),
      service: _string(json['service']),
      start: DateTime.parse(_string(json['start'])),
      end: DateTime.parse(_string(json['end'])),
      status: _string(json['status']),
      source: _string(json['source'], fallback: 'whatsapp'),
      notes: _string(json['notes']),
      createdAt: DateTime.parse(_string(json['createdAt'])),
    );
  }

  final String id;
  final String jid;
  final String name;
  final String service;
  final DateTime start;
  final DateTime end;
  final String status;
  final String source;
  final String notes;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'jid': jid,
    'name': name,
    'service': service,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'status': status,
    'source': source,
    'notes': notes,
    'createdAt': createdAt.toIso8601String(),
  };
}

class SchedulingDraft {
  const SchedulingDraft({
    required this.jid,
    required this.name,
    required this.service,
    required this.preferredDate,
    required this.preferredTime,
    required this.updatedAt,
  });

  factory SchedulingDraft.empty(String jid) {
    return SchedulingDraft(
      jid: jid,
      name: '',
      service: '',
      preferredDate: '',
      preferredTime: '',
      updatedAt: DateTime.now(),
    );
  }

  factory SchedulingDraft.fromJson(Map<String, dynamic> json) {
    return SchedulingDraft(
      jid: _string(json['jid']),
      name: _string(json['name']),
      service: _string(json['service']),
      preferredDate: _string(json['preferredDate']),
      preferredTime: _string(json['preferredTime']),
      updatedAt:
          DateTime.tryParse(_string(json['updatedAt'])) ?? DateTime.now(),
    );
  }

  final String jid;
  final String name;
  final String service;
  final String preferredDate;
  final String preferredTime;
  final DateTime updatedAt;

  SchedulingDraft copyWith({
    String? name,
    String? service,
    String? preferredDate,
    String? preferredTime,
  }) {
    return SchedulingDraft(
      jid: jid,
      name: name ?? this.name,
      service: service ?? this.service,
      preferredDate: preferredDate ?? this.preferredDate,
      preferredTime: preferredTime ?? this.preferredTime,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'jid': jid,
    'name': name,
    'service': service,
    'preferredDate': preferredDate,
    'preferredTime': preferredTime,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

/// Borrador para cancelacion o reprogramacion (multipaso por chat).
class SchedulingManagementDraft {
  const SchedulingManagementDraft({
    required this.jid,
    required this.phase,
    required this.candidateAppointmentIds,
    required this.selectedAppointmentId,
    required this.newPreferredDate,
    required this.newPreferredTime,
    required this.updatedAt,
  });

  factory SchedulingManagementDraft.empty(String jid) {
    return SchedulingManagementDraft(
      jid: jid,
      phase: ManagementPhase.idle,
      candidateAppointmentIds: const [],
      selectedAppointmentId: null,
      newPreferredDate: '',
      newPreferredTime: '',
      updatedAt: DateTime.now(),
    );
  }

  factory SchedulingManagementDraft.fromJson(Map<String, dynamic> json) {
    final rawCandidates = json['candidateAppointmentIds'];
    final ids = <String>[];
    if (rawCandidates is List) {
      for (final item in rawCandidates) {
        if (item != null && item.toString().trim().isNotEmpty) {
          ids.add(item.toString().trim());
        }
      }
    }
    return SchedulingManagementDraft(
      jid: _string(json['jid']),
      phase: ManagementPhase.fromWire(_string(json['phase'], fallback: 'idle')),
      candidateAppointmentIds: ids,
      selectedAppointmentId: _nullableString(json['selectedAppointmentId']),
      newPreferredDate: _string(json['newPreferredDate']),
      newPreferredTime: _string(json['newPreferredTime']),
      updatedAt:
          DateTime.tryParse(_string(json['updatedAt'])) ?? DateTime.now(),
    );
  }

  final String jid;
  final ManagementPhase phase;
  final List<String> candidateAppointmentIds;
  final String? selectedAppointmentId;
  final String newPreferredDate;
  final String newPreferredTime;
  final DateTime updatedAt;

  SchedulingManagementDraft copyWith({
    ManagementPhase? phase,
    List<String>? candidateAppointmentIds,
    String? selectedAppointmentId,
    bool clearSelected = false,
    String? newPreferredDate,
    String? newPreferredTime,
  }) {
    return SchedulingManagementDraft(
      jid: jid,
      phase: phase ?? this.phase,
      candidateAppointmentIds:
          candidateAppointmentIds ?? this.candidateAppointmentIds,
      selectedAppointmentId: clearSelected
          ? null
          : (selectedAppointmentId ?? this.selectedAppointmentId),
      newPreferredDate: newPreferredDate ?? this.newPreferredDate,
      newPreferredTime: newPreferredTime ?? this.newPreferredTime,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'jid': jid,
    'phase': phase.wireName,
    'candidateAppointmentIds': candidateAppointmentIds,
    if (selectedAppointmentId != null)
      'selectedAppointmentId': selectedAppointmentId,
    'newPreferredDate': newPreferredDate,
    'newPreferredTime': newPreferredTime,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

enum ManagementPhase {
  idle,
  cancelPick,
  cancelConfirm,
  reschedulePick,
  rescheduleSlot;

  String get wireName => switch (this) {
    ManagementPhase.idle => 'idle',
    ManagementPhase.cancelPick => 'cancel_pick',
    ManagementPhase.cancelConfirm => 'cancel_confirm',
    ManagementPhase.reschedulePick => 'reschedule_pick',
    ManagementPhase.rescheduleSlot => 'reschedule_slot',
  };

  static ManagementPhase fromWire(String value) => switch (_normPhase(value)) {
    'cancel_pick' => ManagementPhase.cancelPick,
    'cancel_confirm' => ManagementPhase.cancelConfirm,
    'reschedule_pick' => ManagementPhase.reschedulePick,
    'reschedule_slot' => ManagementPhase.rescheduleSlot,
    _ => ManagementPhase.idle,
  };
}

String _normPhase(String raw) => raw.trim().toLowerCase().replaceAll(' ', '_');

Map<String, List<TimeRange>> _workingHours(Object? value) {
  final fallback = AvailabilityConfig.defaultDental().workingHours;
  if (value is! Map) return fallback;
  return value.map((key, rawRanges) {
    if (rawRanges is! List) return MapEntry(key.toString(), <TimeRange>[]);
    return MapEntry(
      key.toString(),
      rawRanges
          .whereType<Map>()
          .map((range) => TimeRange.fromJson(Map<String, dynamic>.from(range)))
          .toList(),
    );
  });
}

List<BlockedDate> _blockedDates(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((date) => BlockedDate.fromJson(Map<String, dynamic>.from(date)))
      .toList();
}

String _string(Object? value, {String fallback = ''}) {
  if (value is! String) return fallback;
  final trimmed = value.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

String? _nullableString(Object? value) {
  final parsed = _string(value);
  return parsed.isEmpty ? null : parsed;
}

int _int(Object? value, {required int fallback}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}
