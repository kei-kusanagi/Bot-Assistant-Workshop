import 'dart:io';

import 'package:neonize/neonize.dart';
import 'package:path/path.dart' as p;

/// Misma idea que `node/whatsapp-bot-baileys`: mostrar QR y vincular la cuenta
/// (multi-dispositivo). Aquí el motor es **Neonize** (Go) vía FFI, no Baileys.
void runQrPairing({required Directory workingDirectory}) {
  final dataRoot = Directory(p.join(workingDirectory.path, 'data'));
  if (!dataRoot.existsSync()) {
    dataRoot.createSync(recursive: true);
  }
  final tempDir = Directory(p.join(dataRoot.path, 'temp'));
  if (!tempDir.existsSync()) {
    tempDir.createSync(recursive: true);
  }
  final dbPath = p.join(dataRoot.path, 'neonize.db');

  final client = NewAClient(
    name: 'workshop-dart-qr',
    config: Config(tempPath: tempDir.path, databasePath: dbPath),
  );

  client.qr((String qrData) {
    stdout.writeln('');
    stdout.writeln(
      'Escanea este QR con WhatsApp (Ajustes > Dispositivos vinculados):',
    );
    stdout.writeln('');
    qrTerminal(qrData, 2, size: 4);
    stdout.writeln('');
  });

  client.on<Connected>((_) {
    stdout.writeln('Conectado a WhatsApp (sesion lista).');
  });

  stdout.writeln('Iniciando cliente Neonize...');
  client.connect();

  stdout.writeln('Proceso activo. Pulsa Enter para desconectar y salir.');
  stdin.readLineSync();
  client.disconnect();
  stdout.writeln('Desconectado.');
}
