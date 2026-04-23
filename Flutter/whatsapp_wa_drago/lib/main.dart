import 'dart:async';

import 'package:drago_whatsapp_flutter/whatsapp_bot_platform_interface.dart';

import 'drago_embedded_wa_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'headless_connect_io.dart' if (dart.library.html) 'headless_connect_stub.dart'
    as headless_drago;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PlatformDispatcher error: $error\n$stack');
    return true;
  };
  runApp(const WaDragoApp());
}

class WaDragoApp extends StatelessWidget {
  const WaDragoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WhatsApp (Dart) — Drago',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF25D366)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late String _status;
  bool _busy = false;
  Uint8List? _qrBytes;
  WhatsappClient? _client;

  /// Web (Chrome) y Windows escritorio: WebView embebido. Resto: headless (vm).
  bool get _useEmbeddedDrago =>
      kIsWeb || (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows);

  @override
  void initState() {
    super.initState();
    _status = kIsWeb
        ? 'Modo web: Drago no puede incrustar WhatsApp aqui (bloqueo de Meta). Pulsa Conectar para ver la explicacion y abrir WA en otra pestaña.'
        : 'Pulsa Conectar. Windows .exe usa WebView embebido; si se cierra, prueba drivers GPU / WebView2 o la ruta Neonize (Dart sin esta UI).';
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _status = 'Iniciando...';
      _qrBytes = null;
    });

    try {
      if (_useEmbeddedDrago) {
        if (kIsWeb) {
          debugPrint('Web: WhatsApp no permite iframe; pantalla informativa.');
        } else {
          debugPrint('Windows: Drago con WebView visible (connectWithInAppBrowser).');
        }
        final client = await Navigator.of(context).push<WhatsappClient?>(
          MaterialPageRoute(
            builder: (_) => const DragoEmbeddedWaPage(),
          ),
        );
        if (!mounted) return;
        _client = client;
        setState(() {
          _busy = false;
          _status = client != null
              ? 'Listo. Cliente conectado.'
              : 'Sin cliente: saliste o no termino el emparejamiento.';
        });
        return;
      }

      _client = await headless_drago.dragoConnectHeadless(
        onStatus: (s) {
          if (!mounted) return;
          setState(() => _status = s);
        },
        onQr: (url, image) {
          if (!mounted) return;
          setState(() {
            _status = 'Escanea el QR con el movil (Dispositivos vinculados).';
            _qrBytes = image;
            if (image == null) {
              _status =
                  'URL del QR: ${url.length > 80 ? "${url.substring(0, 80)}..." : url}';
            }
          });
        },
      );

      if (!mounted) return;
      if (_client != null) {
        setState(() {
          _status = 'Listo. Cliente conectado (WPP + sesion en disco).';
          _busy = false;
        });
      } else {
        setState(() {
          _status = 'No se obtuvo sesion. Reintenta o revisa consola de depuracion.';
          _busy = false;
        });
      }
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _status = 'Error: $e\n(st revisar consola de Flutter)';
        _busy = false;
      });
      debugPrint('Drago error: $e\n$st');
    }
  }

  @override
  void dispose() {
    final c = _client;
    if (c != null) {
      unawaited(c.disconnect());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp en Dart (Drago)'),
        backgroundColor: const Color(0xFF25D366),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (kIsWeb)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'En el navegador, WhatsApp Web no se puede incrustar en esta app (politica de Meta).',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            FilledButton(
              onPressed: _busy ? null : _connect,
              child: Text(_busy ? 'Conectando...' : 'Conectar (QR)'),
            ),
            const SizedBox(height: 16),
            Text(_status, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),
            Expanded(
              child: _qrBytes != null
                  ? Center(
                      child: Image.memory(
                        _qrBytes!,
                        fit: BoxFit.contain,
                      ),
                    )
                  : const Center(
                      child: Text(
                        'El codigo QR aparecera aqui cuando el paquete lo reciba de WhatsApp Web.',
                        textAlign: TextAlign.center,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
