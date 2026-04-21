import 'dart:io';

import 'package:neonize/neonize.dart';
import 'package:path/path.dart' as p;

String? _plainTextFromPayload(Message envelope) {
  if (!envelope.hasMessage()) return null;
  final wm = envelope.message;
  if (wm.hasConversation()) {
    final t = wm.conversation.trim();
    return t.isEmpty ? null : t;
  }
  if (wm.hasExtendedTextMessage() && wm.extendedTextMessage.hasText()) {
    final t = wm.extendedTextMessage.text.trim();
    return t.isEmpty ? null : t;
  }
  return null;
}

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

  client.on<Message>((received) {
    if (!received.hasInfo()) return;
    final source = received.info.messageSource;
    if (source.hasIsFromMe() && source.isFromMe) return;
    if (!source.hasChat()) return;

    final body = _plainTextFromPayload(received);
    if (body == null) return;

    stdout.writeln('[RX] $body');

    final lower = body.toLowerCase();
    final reply = lower == 'ping' ? 'pong' : 'Recibido: $body';
    client.sendMessage(source.chat, text: reply);
  });

  stdout.writeln('Iniciando cliente Neonize...');
  client.connect();

  stdout.writeln('Proceso activo. Pulsa Enter para desconectar y salir.');
  stdin.readLineSync();
  client.disconnect();
  stdout.writeln('Desconectado.');
}
