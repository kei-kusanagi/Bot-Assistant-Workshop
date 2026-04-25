# Dart2 / WhatsApp Web Puppeteer

Segundo intento de migracion a Dart del bot QR de `node/whatsapp-bot-baileys`,
pero con un enfoque distinto a Neonize:

- **No usa `.dll` Neonize**.
- Usa `whatsapp_bot_flutter`, `puppeteer` y WhatsApp Web.
- Abre/descarga Chromium y muestra el QR como WhatsApp Web.
- Al vincular la cuenta, escucha mensajes y responde:
  - `ping` -> `pong`
  - cualquier texto -> `Recibido: ...`

> Nota: sigue siendo un metodo no oficial basado en WhatsApp Web. Para pruebas
> usa un numero que puedas arriesgar; para produccion estable conviene Meta
> Cloud API o un proveedor oficial.

## Ejecutar

Desde esta carpeta:

```powershell
dart pub get
dart run
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
```

## Siguiente prueba manual

1. Ejecuta `dart run`.
2. Escanea QR y espera `[conn] connected`.
3. Desde **otro numero**, escribe `ping` al WhatsApp vinculado.
4. Debe responder `pong`.

Si aparece una ventana de Chrome ya logueada por la sesion anterior, no deberia
pedir QR otra vez; borra `data/whatsapp-session/` si necesitas iniciar limpio.
