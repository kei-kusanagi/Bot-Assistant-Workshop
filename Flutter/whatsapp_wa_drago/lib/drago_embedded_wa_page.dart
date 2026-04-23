import 'package:drago_whatsapp_flutter/drago_whatsapp_flutter.dart';
import 'package:drago_whatsapp_flutter/whatsapp_bot_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

/// WhatsApp Web embebido + [connectWithInAppBrowser] (ejemplo Drago).
/// Usar en **web (Chrome)** o **Windows escritorio**; evita el headless nativo
/// que en Windows suele cerrar el proceso.
class DragoEmbeddedWaPage extends StatefulWidget {
  const DragoEmbeddedWaPage({super.key});

  @override
  State<DragoEmbeddedWaPage> createState() => _DragoEmbeddedWaPageState();
}

class _DragoEmbeddedWaPageState extends State<DragoEmbeddedWaPage> {
  String _status = 'Cargando WhatsApp Web...';
  Uint8List? _qrBytes;
  bool _dragoConnectStarted = false;

  Future<void> _beginDrago(InAppWebViewController controller) async {
    if (_dragoConnectStarted) return;
    _dragoConnectStarted = true;
    if (mounted) {
      setState(() => _status = 'Iniciando WPP (whatsapp-web.js)...');
    }

    try {
      final client = await DragoWhatsappFlutter.connectWithInAppBrowser(
        controller: controller,
        qrCodeWaitDurationSeconds: 120,
        onConnectionEvent: (e) {
          if (!mounted) return;
          setState(() => _status = 'Conexion: ${e.name}');
        },
        onQrCode: (url, image) {
          if (!mounted) return;
          setState(() {
            _status = image == null
                ? 'URL QR: ${url.length > 72 ? "${url.substring(0, 72)}..." : url}'
                : 'Escanea el QR con el movil (Dispositivos vinculados).';
            _qrBytes = image;
          });
        },
      );

      if (!mounted) return;
      if (client != null) {
        Navigator.of(context).pop(client);
      } else {
        setState(() {
          _status =
              'No se obtuvo sesion a tiempo. Puedes volver atras y reintentar.';
          _dragoConnectStarted = false;
        });
      }
    } catch (e, st) {
      if (mounted) {
        setState(() {
          _status = 'Error: $e';
          _dragoConnectStarted = false;
        });
      }
      debugPrint('connectWithInAppBrowser: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      final waUri = Uri.parse(WhatsAppMetadata.whatsAppURL);
      return Scaffold(
        appBar: AppBar(
          title: const Text('Vincular WhatsApp'),
          backgroundColor: const Color(0xFF25D366),
          foregroundColor: Colors.white,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.info_outline, size: 48, color: Color(0xFF25D366)),
              const SizedBox(height: 16),
              Text(
                'WhatsApp no permite cargar web.whatsapp.com dentro de esta app en el navegador (bloqueo por seguridad: no se puede usar en un iframe desde localhost).',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              Text(
                'Por eso ves “rechazó la conexión”: no es un fallo de Flutter, es la política de Meta.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () async {
                  final ok = await launchUrl(
                    waUri,
                    webOnlyWindowName: '_blank',
                  );
                  if (!context.mounted) return;
                  if (!ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No se pudo abrir el enlace.'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Abrir WhatsApp Web en una pestaña nueva'),
              ),
              const SizedBox(height: 20),
              Text(
                'Eso abre WhatsApp en el navegador para uso manual. El bot Drago (whatsapp-web.js inyectado) no puede integrarse desde esta pantalla en modo web.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vincular WhatsApp'),
        backgroundColor: const Color(0xFF25D366),
        foregroundColor: Colors.white,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_status, style: Theme.of(context).textTheme.bodyMedium),
          ),
          if (_qrBytes != null)
            SizedBox(
              height: 140,
              child: Center(
                child: Image.memory(_qrBytes!, fit: BoxFit.contain),
              ),
            ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri.uri(Uri.parse(WhatsAppMetadata.whatsAppURL)),
              ),
              onConsoleMessage: (controller, consoleMessage) {
                debugPrint('WA console: ${consoleMessage.message}');
              },
              onReceivedServerTrustAuthRequest: (controller, challenge) async {
                return ServerTrustAuthResponse(
                  action: ServerTrustAuthResponseAction.PROCEED,
                );
              },
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                return NavigationActionPolicy.ALLOW;
              },
              initialSettings: InAppWebViewSettings(
                isInspectable: kDebugMode,
                preferredContentMode: UserPreferredContentMode.DESKTOP,
                userAgent: WhatsAppMetadata.userAgent,
                javaScriptEnabled: true,
                incognito: false,
                cacheEnabled: true,
              ),
              onLoadStop: (controller, url) async {
                if (!url.toString().contains('web.whatsapp.com')) {
                  return;
                }
                await _beginDrago(controller);
              },
              onReceivedError: (controller, request, error) {
                if (mounted) {
                  setState(
                    () => _status = 'Error WebView: ${error.description}',
                  );
                }
              },
              onJsConfirm: (controller, jsConfirmRequest) async =>
                  JsConfirmResponse(action: JsConfirmResponseAction.CONFIRM),
              onJsAlert: (controller, jsAlertRequest) async =>
                  JsAlertResponse(action: JsAlertResponseAction.CONFIRM),
              onJsPrompt: (controller, jsPromptRequest) async =>
                  JsPromptResponse(action: JsPromptResponseAction.CONFIRM),
            ),
          ),
        ],
      ),
    );
  }
}
