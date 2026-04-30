# Dart2 / WhatsApp Web Puppeteer

Segundo intento de migracion a Dart del bot QR de `node/whatsapp-bot-baileys`,
pero con un enfoque distinto a Neonize:

- **No usa `.dll` Neonize**.
- Usa `whatsapp_bot_flutter`, `puppeteer` y WhatsApp Web.
- Abre/descarga Chromium y muestra el QR como WhatsApp Web.
- Al vincular la cuenta, escucha mensajes y responde usando un servicio de IA.
- La IA se conecta por defecto a **Ollama local** (`http://localhost:11434`).

> Nota: sigue siendo un metodo no oficial basado en WhatsApp Web. Para pruebas
> usa un numero que puedas arriesgar; para produccion estable conviene Meta
> Cloud API o un proveedor oficial.

## Ejecutar

Desde esta carpeta:

```powershell
dart pub get
dart run
```

Antes de usar respuestas con IA, asegúrate de tener Ollama corriendo y un modelo instalado:

```powershell
ollama pull llama3.2:3b
```

La primera vez puede tardar porque descarga Chromium en `.local-chromium/`.
Cuando abra la ventana de Chrome, escanea el QR con:

**WhatsApp > Dispositivos vinculados > Vincular un dispositivo**

Tambien se intenta guardar el ultimo QR en `data/last_qr.png`.

## Variables utiles

```powershell
# Chrome sin ventana visible; usa QR de consola/archivo.
$env:HEADLESS_CHROME="1"
dart run

# Alternativa al QR: vincular con codigo por numero.
$env:WHATSAPP_LINK_PHONE="5215512345678"
dart run

# Ver stack trace completo si falla el arranque.
$env:DART2_DEBUG_STACK="1"
dart run

# Cambiar modelo/base URL de Ollama.
$env:OLLAMA_BASE_URL="http://localhost:11434"
$env:OLLAMA_MODEL="qwen2.5:3b"
dart run
```

## Siguiente prueba manual

1. Ejecuta `dart run`.
2. Escanea QR y espera `[conn] connected`.
3. Desde **otro numero**, escribe un mensaje al WhatsApp vinculado.
4. Debe aparecer `[RX]` o `[RX/poll]` en terminal y responder con texto generado por Ollama.

Si aparece una ventana de Chrome ya logueada por la sesion anterior, no deberia
pedir QR otra vez; borra `data/whatsapp-session/` si necesitas iniciar limpio.

## Arquitectura IA

La capa de IA esta documentada en:

`../DOCS/AI_ADAPTER_ARCHITECTURE.md`

Resumen:

- `lib/ai/ai_provider.dart`: contrato generico.
- `lib/ai/providers/ollama_provider.dart`: proveedor local via HTTP.
- `lib/ai/ai_service.dart`: servicio que usa el bot.

Si no aparece `[RX]`, el bot tiene un respaldo por polling de chats no leidos.
Para ver errores de ese respaldo:

```powershell
$env:DART2_DEBUG_POLLING="1"
dart run
```
