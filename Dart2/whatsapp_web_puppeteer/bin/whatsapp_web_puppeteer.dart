import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:qr/qr.dart' as qr_pkg;
import 'package:whatsapp_bot_flutter/whatsapp_bot_flutter.dart';
import 'package:whatsapp_web_puppeteer/ai/ai_service.dart';
import 'package:whatsapp_web_puppeteer/ai/providers/ollama_provider.dart';
import 'package:whatsapp_web_puppeteer/storage/local_conversation_store.dart';

enum _BotRunSignal { stop, reconnect }

Future<void> main(List<String> arguments) async {
  WhatsappBotUtils.enableLogs(_envFlag('WPP_VERBOSE_LOGS'));

  final cwd = Directory.current;
  final dataDir = Directory(p.join(cwd.path, 'data'));
  final chromeDir = Directory(p.join(cwd.path, '.local-chromium'));
  final sessionDir = Directory(p.join(dataDir.path, 'whatsapp-session'));
  final storeDir = Directory(p.join(dataDir.path, 'store'));
  final businessProfileFile = File(
    p.join(dataDir.path, 'business_profile.json'),
  );
  for (final dir in [dataDir, chromeDir, sessionDir, storeDir]) {
    if (!dir.existsSync()) dir.createSync(recursive: true);
  }

  final headless = _envFlag('HEADLESS_CHROME');
  final phoneLink = Platform.environment['WHATSAPP_LINK_PHONE']?.trim();
  final ollamaBaseUrl = Uri.parse(
    Platform.environment['OLLAMA_BASE_URL'] ?? 'http://localhost:11434',
  );
  final ollamaModel = Platform.environment['OLLAMA_MODEL'] ?? 'llama3.2:3b';
  final aiService = AIService(
    provider: OllamaProvider(baseUrl: ollamaBaseUrl, model: ollamaModel),
  );
  final conversationStore = LocalConversationStore(
    storeDirectory: storeDir,
    businessProfileFile: businessProfileFile,
  );
  await conversationStore.ensureReady();
  stdout.writeln('Dart2 WhatsApp Web bot (Puppeteer + WA-JS)');
  stdout.writeln('Sesion: ${sessionDir.path}');
  stdout.writeln('Chromium cache: ${chromeDir.path}');
  stdout.writeln('Memoria local: ${storeDir.path}');
  stdout.writeln('Perfil del negocio: ${businessProfileFile.path}');
  stdout.writeln('AI provider: Ollama ($ollamaBaseUrl), model: $ollamaModel');
  stdout.writeln(
    headless
        ? 'Chrome abrira en modo headless; usa el QR de consola/archivo.'
        : 'Chrome abrira visible; escanea el QR de esa ventana si aparece.',
  );
  if (phoneLink != null && phoneLink.isNotEmpty) {
    stdout.writeln(
      'Vinculacion por codigo telefonico activada para $phoneLink.',
    );
  }
  stdout.writeln('');

  final stopSignal = Completer<void>();
  late final StreamSubscription<ProcessSignal> sigintSub;
  sigintSub = ProcessSignal.sigint.watch().listen((_) {
    stdout.writeln('');
    stdout.writeln('Cerrando bot...');
    if (!stopSignal.isCompleted) stopSignal.complete();
  });

  try {
    while (!stopSignal.isCompleted) {
      final signal = await _runBotSession(
        dataDir: dataDir,
        chromeDir: chromeDir,
        sessionDir: sessionDir,
        headless: headless,
        phoneLink: phoneLink,
        aiService: aiService,
        conversationStore: conversationStore,
        stopSignal: stopSignal.future,
      );

      if (signal == _BotRunSignal.stop || stopSignal.isCompleted) break;

      stderr.writeln('[reconnect] Reintentando conexion en 5 segundos...');
      await Future.any([
        Future<void>.delayed(const Duration(seconds: 5)),
        stopSignal.future,
      ]);
    }
  } finally {
    await sigintSub.cancel();
  }
}

Future<_BotRunSignal> _runBotSession({
  required Directory dataDir,
  required Directory chromeDir,
  required Directory sessionDir,
  required bool headless,
  required String? phoneLink,
  required AIService aiService,
  required LocalConversationStore conversationStore,
  required Future<void> stopSignal,
}) async {
  final handledMessageIds = <String>{};
  final sessionSignal = Completer<_BotRunSignal>();
  WhatsappClient? client;
  Timer? pollingTimer;

  void requestReconnect(Object error) {
    if (sessionSignal.isCompleted) return;
    stderr.writeln('[reconnect] La sesion de Chrome se cerro: $error');
    sessionSignal.complete(_BotRunSignal.reconnect);
  }

  try {
    client = await WhatsappBotFlutter.connect(
      sessionDirectory: sessionDir.path,
      chromiumDownloadDirectory: chromeDir.path,
      headless: headless,
      linkWithPhoneNumber: phoneLink == null || phoneLink.isEmpty
          ? null
          : phoneLink,
      qrCodeWaitDurationSeconds: 180,
      connectionTimeout: const Duration(seconds: 60),
      wppInitTimeout: const Duration(seconds: 45),
      puppeteerNavigationTimeout: const Duration(seconds: 90),
      puppeteerArgs: const [
        '--remote-allow-origins=*',
        '--disable-dev-shm-usage',
        '--no-first-run',
        '--no-default-browser-check',
      ],
      chromeDownloadProgress: (received, total) {
        if (total <= 0) return;
        final percent = (received * 100 / total)
            .clamp(0, 100)
            .toStringAsFixed(0);
        stdout.write('\rDescargando Chromium: $percent%');
        if (received >= total) stdout.writeln('');
      },
      onConnectionEvent: (event) {
        stdout.writeln('[conn] ${event.name}');
      },
      onPhoneLinkCode: (code) {
        stdout.writeln('');
        stdout.writeln('Codigo para vincular WhatsApp: $code');
        stdout.writeln(
          'En WhatsApp: Dispositivos vinculados > Vincular con numero de telefono.',
        );
        stdout.writeln('');
      },
      onQrCode: (qr, imageBytes) async {
        stdout.writeln('');
        stdout.writeln(
          'QR recibido. Escanealo con WhatsApp > Dispositivos vinculados.',
        );
        if (imageBytes != null) {
          final out = File(p.join(dataDir.path, 'last_qr.png'));
          await out.writeAsBytes(_pngBytes(imageBytes));
          stdout.writeln('Tambien guarde el QR en: ${out.path}');
        }
        if (qr.isNotEmpty) {
          stdout.writeln('');
          stdout.writeln('QR en consola:');
          _writeQrAscii(qr);
          stdout.writeln('');
        }
      },
    );

    if (client == null) {
      stderr.writeln('No se pudo crear el cliente WhatsApp.');
      exitCode = 1;
      return _BotRunSignal.stop;
    }

    stdout.writeln('Cliente creado. Registrando listener de mensajes...');
    await client.on(WhatsappEvent.chatNewMessage, (data) {
      unawaited(
        _handleIncoming(
          client!,
          aiService,
          conversationStore,
          data,
          handledMessageIds,
        ).catchError((Object error) {
          if (_isBrowserSessionClosedError(error)) {
            requestReconnect(error);
            return;
          }
          stderr.writeln('[RX-ERROR] No pude procesar un mensaje: $error');
        }),
      );
    });
    pollingTimer = _startMessagePolling(
      client,
      aiService,
      conversationStore,
      handledMessageIds,
      onFatalError: requestReconnect,
    );

    stdout.writeln('');
    stdout.writeln(
      'Bot activo. Desde otro numero escribe al WhatsApp vinculado.',
    );
    stdout.writeln(
      'Las respuestas ahora salen de Ollama, no de if/else fijos.',
    );
    stdout.writeln(
      'Deja esta terminal abierta. Pulsa Ctrl+C para cerrar Chrome y salir.',
    );
    final signal = await Future.any([
      stopSignal.then((_) => _BotRunSignal.stop),
      sessionSignal.future,
    ]);
    return signal;
  } catch (error, stackTrace) {
    stderr.writeln('');
    stderr.writeln('Error iniciando el bot: $error');
    if (_envFlag('DART2_DEBUG_STACK')) {
      stderr.writeln(stackTrace);
    }
    if (_isBrowserSessionClosedError(error)) {
      return _BotRunSignal.reconnect;
    }
    exitCode = 1;
    return _BotRunSignal.stop;
  } finally {
    pollingTimer?.cancel();
    try {
      await client?.disconnect();
    } catch (error) {
      if (_envFlag('DART2_DEBUG_STACK')) {
        stderr.writeln('[disconnect-error] $error');
      }
    }
  }
}

Future<void> _handleIncoming(
  WhatsappClient client,
  AIService aiService,
  LocalConversationStore conversationStore,
  dynamic data,
  Set<String> handledMessageIds,
) async {
  final messages = Message.parse(data);
  for (final message in messages) {
    final id = message.id;
    if (id?.fromMe ?? true) continue;

    final from = message.from;
    final body = (message.body ?? message.caption ?? '').trim();
    if (from == null || from.isEmpty || body.isEmpty) continue;
    if (!_isSupportedIncomingChat(from)) {
      stdout.writeln('[SKIP] Ignorando origen no soportado: $from');
      continue;
    }
    if (!_markMessageAsNew(
      message.id?.serialized ?? message.id?.id,
      handledMessageIds,
    )) {
      continue;
    }

    stdout.writeln('[RX] $from: $body');

    await _generateAndSendReply(
      client,
      aiService,
      conversationStore,
      to: from,
      body: body,
      id: id,
    );
  }
}

Timer _startMessagePolling(
  WhatsappClient client,
  AIService aiService,
  LocalConversationStore conversationStore,
  Set<String> handledMessageIds, {
  required void Function(Object error) onFatalError,
}) {
  var polling = false;
  return Timer.periodic(const Duration(seconds: 3), (_) {
    if (polling) return;
    polling = true;
    unawaited(
      _pollUnreadMessages(
        client,
        aiService,
        conversationStore,
        handledMessageIds,
        onFatalError: onFatalError,
      ).whenComplete(() {
        polling = false;
      }),
    );
  });
}

Future<void> _pollUnreadMessages(
  WhatsappClient client,
  AIService aiService,
  LocalConversationStore conversationStore,
  Set<String> handledMessageIds, {
  required void Function(Object error) onFatalError,
}) async {
  try {
    final raw = await client.wpClient.evaluateJs(
      r'''WPP.chat.list({ onlyUsers: true }).then((chats) => chats
        .filter((chat) => (chat.unreadCount || 0) > 0)
        .slice(0, 10)
        .map((chat) => ({
          id: chat.id?._serialized || chat.id,
          messages: (chat.msgs || [])
            .slice(-5)
            .map((msg) => ({
              id: msg.id?._serialized || msg.id?.id || msg.id,
              fromMe: !!msg.id?.fromMe,
              from: msg.from?._serialized || msg.from || chat.id?._serialized || chat.id,
              body: msg.body || msg.caption || '',
              t: msg.t || 0
            }))
        })))''',
      methodName: 'pollUnreadMessages',
      forceJsonParseResult: true,
    );
    if (raw is! List) return;

    for (final chat in raw) {
      if (chat is! Map) continue;
      final messages = chat['messages'];
      if (messages is! List) continue;

      for (final rawMessage in messages) {
        if (rawMessage is! Map) continue;
        if (rawMessage['fromMe'] == true) continue;

        final id = rawMessage['id']?.toString();
        if (!_markMessageAsNew(id, handledMessageIds)) continue;

        final from = rawMessage['from']?.toString() ?? chat['id']?.toString();
        final body = rawMessage['body']?.toString().trim() ?? '';
        if (from == null || from.isEmpty || body.isEmpty) continue;
        if (!_isSupportedIncomingChat(from)) {
          stdout.writeln('[SKIP/poll] Ignorando origen no soportado: $from');
          continue;
        }

        stdout.writeln('[RX/poll] $from: $body');
        await _generateAndSendReply(
          client,
          aiService,
          conversationStore,
          to: from,
          body: body,
        );
      }
    }
  } catch (error) {
    if (_isBrowserSessionClosedError(error)) {
      onFatalError(error);
      return;
    }
    if (_envFlag('DART2_DEBUG_POLLING')) {
      stderr.writeln('[poll-error] $error');
    }
  }
}

bool _markMessageAsNew(String? id, Set<String> handledMessageIds) {
  if (id == null || id.isEmpty) return true;
  if (handledMessageIds.contains(id)) return false;
  handledMessageIds.add(id);
  if (handledMessageIds.length > 500) {
    handledMessageIds.remove(handledMessageIds.first);
  }
  return true;
}

bool _isSupportedIncomingChat(String jid) {
  if (jid.endsWith('@newsletter')) return false;
  if (jid.endsWith('@g.us')) return false;
  if (jid == 'status@broadcast' || jid.contains('broadcast')) return false;
  return jid.endsWith('@lid') ||
      jid.endsWith('@c.us') ||
      jid.endsWith('@s.whatsapp.net');
}

bool _isBrowserSessionClosedError(Object error) {
  final message = error.toString().toLowerCase();
  return message.contains('session closed') ||
      message.contains('page has been closed') ||
      message.contains('target closed') ||
      message.contains('browser has disconnected') ||
      message.contains('websocket url not found');
}

Future<void> _generateAndSendReply(
  WhatsappClient client,
  AIService aiService,
  LocalConversationStore conversationStore, {
  required String to,
  required String body,
  MessageId? id,
}) async {
  if (conversationStore.isIncomingMessageTooLong(body)) {
    final reply =
        'Recibi un mensaje demasiado largo para procesarlo completo. Puedes resumirme en pocas lineas que necesitas preguntar o agendar?';
    await conversationStore.saveRejectedLongMessage(to, body);
    await _sendReply(client, to: to, message: reply, replyMessageId: id);
    await conversationStore.saveAssistantMessage(to, reply);
    stdout.writeln('[TX] $to: $reply');
    return;
  }

  try {
    await conversationStore.saveUserMessage(to, body);
    final businessProfile = await conversationStore.loadBusinessProfile();
    final conversationContext = await conversationStore.loadContext(to);
    final reply = await aiService.getResponse(
      body,
      businessProfile: businessProfile,
      conversationContext: conversationContext,
    );
    await _sendReply(client, to: to, message: reply, replyMessageId: id);
    await conversationStore.saveAssistantMessage(to, reply);
    stdout.writeln('[TX] $to: $reply');
  } catch (error) {
    if (_isBrowserSessionClosedError(error)) rethrow;
    stderr.writeln('[TX-ERROR] No pude responder a $to: $error');
    try {
      await _sendReply(
        client,
        to: to,
        message:
            'Por ahora no pude consultar la IA local. Revisa que Ollama este corriendo y que el modelo este instalado.',
        replyMessageId: id,
      );
      await conversationStore.saveAssistantMessage(
        to,
        'Por ahora no pude consultar la IA local. Revisa que Ollama este corriendo y que el modelo este instalado.',
      );
    } catch (fallbackError) {
      if (_isBrowserSessionClosedError(fallbackError)) rethrow;
      stderr.writeln(
        '[TX-FALLBACK-ERROR] Tampoco pude enviar fallback a $to: $fallbackError',
      );
    }
  }
}

Future<void> _sendReply(
  WhatsappClient client, {
  required String to,
  required String message,
  MessageId? replyMessageId,
}) async {
  // whatsapp_bot_flutter convierte todo lo que no contiene ".us" a "@c.us".
  // Los chats nuevos pueden llegar como "@lid"; para esos casos hay que enviar
  // directo a WPP.chat con el id crudo que recibimos de WhatsApp Web.
  if (to.contains('@')) {
    await client.wpClient.evaluateJs(
      '''WPP.chat.sendTextMessage(${to.jsParse}, ${message.jsParse}, {
        quotedMsg: ${replyMessageId?.serialized.jsParse},
        createChat: true
      });''',
      methodName: 'sendTextMessageRaw',
    );
    return;
  }

  await client.chat.sendTextMessage(
    phone: to,
    message: message,
    replyMessageId: replyMessageId,
  );
}

bool _envFlag(String name) {
  final raw = Platform.environment[name]?.trim().toLowerCase();
  return raw == '1' || raw == 'true' || raw == 'yes' || raw == 'si';
}

Uint8List _pngBytes(Uint8List bytesOrDataUrl) {
  final value = utf8.decode(bytesOrDataUrl, allowMalformed: true);
  final comma = value.indexOf(',');
  if (value.startsWith('data:image') && comma != -1) {
    return base64Decode(value.substring(comma + 1));
  }
  return bytesOrDataUrl;
}

void _writeQrAscii(String qrData) {
  try {
    final qrCode = qr_pkg.QrCode.fromData(
      data: qrData,
      errorCorrectLevel: qr_pkg.QrErrorCorrectLevel.L,
    );
    final qrImage = qr_pkg.QrImage(qrCode);
    const dark = '██';
    const light = '  ';
    for (var y = 0; y < qrImage.moduleCount; y++) {
      final row = StringBuffer();
      for (var x = 0; x < qrImage.moduleCount; x++) {
        row.write(qrImage.isDark(y, x) ? dark : light);
      }
      stdout.writeln(row.toString());
    }
  } catch (_) {
    stdout.writeln(qrData);
  }
}
