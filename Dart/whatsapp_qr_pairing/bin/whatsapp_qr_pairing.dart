import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:whatsapp_qr_pairing/neonize_pairing.dart' deferred as pairing;

/// Activa `package:logging` para el paquete `neonize` (emit, callbacks, etc.).
void _configureDartLoggingFromEnv() {
  final raw = Platform.environment['NEONIZE_LOG_LEVEL']?.trim().toUpperCase();
  var level = Level.INFO;
  if (raw == 'DEBUG' ||
      raw == 'FINEST' ||
      raw == 'FINE' ||
      raw == 'ALL' ||
      raw == 'TRACE') {
    level = Level.ALL;
  } else if (raw == 'WARNING' || raw == 'WARN') {
    level = Level.WARNING;
  } else if (raw == 'SEVERE' || raw == 'ERROR') {
    level = Level.SEVERE;
  }
  Logger.root.level = level;
  Logger.root.onRecord.listen((r) {
    stdout.writeln('[neonize-dart] ${r.level.name}: ${r.message}');
  });
}

/// Resuelve la ruta al binario Neonize: `NEONIZE_PATH` o, si falta, un archivo
/// conocido en el directorio de trabajo (mismo criterio que README / Baileys).
String? _resolveNeonizeLibraryPath() {
  final fromEnv = Platform.environment['NEONIZE_PATH']?.trim();
  if (fromEnv != null && fromEnv.isNotEmpty) {
    return fromEnv;
  }
  final cwd = Directory.current.path;
  final names = <String>[
    if (Platform.isWindows) ...[
      'neonize-windows-amd64.dll',
      'neonize-windows-arm64.dll',
      'neonize-windows-386.dll',
    ],
    if (Platform.isLinux) 'libneonize.so',
    if (Platform.isMacOS) 'libneonize.dylib',
  ];
  for (final name in names) {
    final f = File(p.join(cwd, name));
    if (f.existsSync()) return f.path;
  }
  return null;
}

Future<void> main(List<String> arguments) async {
  _configureDartLoggingFromEnv();
  final neonizePath = _resolveNeonizeLibraryPath();
  if (neonizePath == null) {
    stderr.writeln(_missingNeonizePathMessage());
    exitCode = 64;
    return;
  }
  final libFile = File(neonizePath);
  if (!libFile.existsSync()) {
    stderr.writeln(
      'NEONIZE_PATH apunta a un archivo inexistente:\n  ${libFile.absolute.path}',
    );
    exitCode = 64;
    return;
  }
  final neonizeEnv = Platform.environment['NEONIZE_PATH'];
  final usedExplicitEnv =
      neonizeEnv != null && neonizeEnv.trim().isNotEmpty;
  if (!usedExplicitEnv) {
    stdout.writeln(
      '(Usando libreria en el directorio actual: ${libFile.path})\n',
    );
  }

  await pairing.loadLibrary();
  pairing.runQrPairing(workingDirectory: Directory.current);
}

String _missingNeonizePathMessage() {
  return '''
NEONIZE_PATH no esta definido y no se encontro ningun binario Neonize en esta carpeta.

Neonize carga una libreria nativa (.dll en Windows, .so en Linux, .dylib en macOS).

Opcion A — misma carpeta que pubspec.yaml (recomendado, como Baileys con .env local):
  Coloca aqui el archivo descargado, por ejemplo:
    neonize-windows-amd64.dll
  y vuelve a ejecutar: dart run

Opcion B — variable de entorno:
  PowerShell (Windows):
    \$env:NEONIZE_PATH="C:\\ruta\\completa\\neonize-windows-amd64.dll"
    dart run

  Linux / macOS:
    export NEONIZE_PATH=/ruta/a/libneonize.so
    dart run

Descarga del .dll (Windows x64), misma linea que en Dart/docs/MIGRATION_FROM_NODE_BAILEYS.md:
  https://github.com/krypton-byte/neonize/releases/download/0.3.16.post0/neonize-windows-amd64.dll

(No uses el archivo .whl de Python; necesitas el .dll.)

Docker: monta el .so y NEONIZE_PATH (ver Dart/docker-compose.yml).
''';
}
