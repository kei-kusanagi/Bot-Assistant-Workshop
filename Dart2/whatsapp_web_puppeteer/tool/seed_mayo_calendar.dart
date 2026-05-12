/// Genera datos demo de mayo (citas ocupadas). Uso desde la carpeta del proyecto:
///   dart run tool/seed_mayo_calendar.dart
///
/// Pisa calendar_events.json y appointments.json en data/.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

void main(List<String> args) {
  final year = args.isNotEmpty ? int.tryParse(args.first) ?? 2026 : 2026;
  final cwd = Directory.current;
  final dataDir = Directory(p.join(cwd.path, 'data'));
  if (!dataDir.existsSync()) {
    stderr.writeln(
      'No existe data/ (ejecuta desde Dart2/whatsapp_web_puppeteer).',
    );
    exitCode = 1;
    return;
  }

  final rnd = Random(42);
  const slotMinutes = 30;
  const startHour = 10;
  const endHour = 19;
  const endMinute = 30;

  final services = [
    'Valoracion dental',
    'Limpieza dental',
    'Resinas',
    'Endodoncia',
    'Extracciones',
  ];
  final names = ['Ana', 'Luis', 'María', 'Pedro', 'Sofía', 'Demo Paciente'];
  final demoJids = [
    'demo001@lid',
    'demo002@lid',
    'demo003@lid',
    '86062705705098@lid',
  ];

  final appointments = <Map<String, dynamic>>[];
  final events = <Map<String, dynamic>>[];

  var micro = DateTime.now().microsecondsSinceEpoch;

  for (var day = 11; day <= 30; day++) {
    final d = DateTime(year, 5, day);
    if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
      continue;
    }

    final slotStarts = <DateTime>[];
    for (var h = startHour; h <= endHour; h++) {
      for (var m = 0; m < 60; m += slotMinutes) {
        if (h == endHour && m > endMinute) break;
        if (h == endHour && m == endMinute) break;
        final start = DateTime(year, 5, day, h, m);
        final end = start.add(const Duration(minutes: slotMinutes));
        if (end.hour > endHour ||
            (end.hour == endHour && end.minute > endMinute)) {
          break;
        }
        slotStarts.add(start);
      }
    }

    final nBusy = (slotStarts.length * (0.35 + rnd.nextDouble() * 0.45))
        .round();
    slotStarts.shuffle(rnd);
    final taken = slotStarts.take(nBusy);

    for (final start in taken) {
      micro += 17;
      final id = 'appt_seed_$micro';
      final evId = 'evt_seed_$micro';
      final end = start.add(const Duration(minutes: slotMinutes));
      final name = names[rnd.nextInt(names.length)];
      final service = services[rnd.nextInt(services.length)];
      final jid = demoJids[rnd.nextInt(demoJids.length)];

      appointments.add({
        'id': id,
        'jid': jid,
        'name': name,
        'service': service,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'status': 'confirmed',
        'source': 'demo_seed',
        'notes': 'Generado por tool/seed_mayo_calendar.dart',
        'createdAt': DateTime.now().toIso8601String(),
      });
      events.add({
        'id': evId,
        'type': 'appointment',
        'status': 'confirmed',
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'title': '$service - $name',
        'appointmentId': id,
      });
    }
  }

  final apptFile = File(p.join(dataDir.path, 'appointments.json'));
  final evFile = File(p.join(dataDir.path, 'calendar_events.json'));
  const enc = JsonEncoder.withIndent('  ');
  apptFile.writeAsStringSync(
    '${enc.convert({'appointments': appointments})}\n',
  );
  evFile.writeAsStringSync('${enc.convert({'events': events})}\n');

  stdout.writeln(
    'OK: ${appointments.length} citas demo en mayo $year (lun-vie) -> ${apptFile.path} y ${evFile.path}',
  );
}
