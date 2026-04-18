import 'dart:io';

import 'package:whatsapp_qr_pairing/neonize_pairing.dart' deferred as pairing;

Future<void> main(List<String> arguments) async {
  final neonizePath = Platform.environment['NEONIZE_PATH'];
  if (neonizePath == null || neonizePath.trim().isEmpty) {
    stderr.writeln(_missingNeonizePathMessage());
    exitCode = 64;
    return;
  }
  final libFile = File(neonizePath.trim());
  if (!libFile.existsSync()) {
    stderr.writeln(
      'NEONIZE_PATH apunta a un archivo inexistente:\n  ${libFile.absolute.path}',
    );
    exitCode = 64;
    return;
  }

  await pairing.loadLibrary();
  pairing.runQrPairing(workingDirectory: Directory.current);
}

String _missingNeonizePathMessage() {
  return '''
NEONIZE_PATH no esta definido o esta vacio.

Neonize (el paquete Dart) carga una libreria nativa (.dll en Windows, .so en Linux).
Antes de ejecutar este programa:

1. Descarga la libreria Neonize para tu plataforma desde el proyecto neonize-dart
   (repositorio: https://github.com/krypton-byte/neonize-dart ).
2. Define la variable de entorno apuntando al archivo:

   PowerShell (Windows):
     \$env:NEONIZE_PATH="C:\\ruta\\completa\\neonize-windows-amd64.dll"
     dart run

   Linux / macOS:
     export NEONIZE_PATH=/ruta/a/libneonize.so
     dart run

3. En Docker, monta el .so y establece NEONIZE_PATH (ver docker-compose.yml).
''';
}
