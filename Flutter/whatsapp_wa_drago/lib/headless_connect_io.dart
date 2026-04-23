import 'dart:io';

import 'package:drago_whatsapp_flutter/drago_whatsapp_flutter.dart';
import 'package:drago_whatsapp_flutter/whatsapp_bot_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<WhatsappClient?> dragoConnectHeadless({
  required void Function(String) onStatus,
  required void Function(String url, Uint8List? image) onQr,
}) async {
  final support = await getApplicationSupportDirectory();
  final sessionDir = p.join(support.path, 'drago_whatsapp_session');
  await Directory(sessionDir).create(recursive: true);

  debugPrint('Drago connect (headless): sessionDir=$sessionDir');

  return DragoWhatsappFlutter.connect(
    saveSession: true,
    sessionPath: sessionDir,
    qrCodeWaitDurationSeconds: 120,
    connectionTimeout: const Duration(seconds: 60),
    onConnectionEvent: (e) => onStatus('Conexion: ${e.name}'),
    onQrCode: onQr,
  );
}
