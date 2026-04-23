import 'package:drago_whatsapp_flutter/whatsapp_bot_platform_interface.dart';
import 'package:flutter/foundation.dart';

/// Solo para compilar en web; no se usa (el flujo web va por [DragoEmbeddedWaPage]).
Future<WhatsappClient?> dragoConnectHeadless({
  required void Function(String) onStatus,
  required void Function(String url, Uint8List? image) onQr,
}) async {
  debugPrint('dragoConnectHeadless stub: no deberia llamarse en web.');
  return null;
}
