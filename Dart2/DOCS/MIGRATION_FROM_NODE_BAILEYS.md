# Migracion funcional desde Node/Baileys a Dart2

## Objetivo

El objetivo pedido fue migrar a Dart la parte del bot Node/Baileys que:

- muestra un QR para vincular WhatsApp;
- convierte el WhatsApp vinculado en el bot;
- escucha mensajes entrantes;
- responde automaticamente.

No se migro linea por linea porque Baileys es una libreria Node/TypeScript y no existe un equivalente directo en Dart. Lo que se migro fue el flujo funcional.

## Enfoque anterior descartado: Neonize

El primer intento en `Dart/whatsapp_qr_pairing` uso `neonize` via FFI y una libreria nativa `.dll`.

Ese camino logro:

- cargar la libreria nativa;
- configurar callbacks FFI;
- activar logs Dart;
- preparar respuesta `ping -> pong`.

Pero en esta maquina fallo de forma repetida con:

- `Login event: timeout`;
- sin callback de QR;
- sin linea de "QR recibido".

Conclusión: el problema quedaba antes de entregar el QR al lado Dart, en la cadena Neonize/whatsmeow/native/session/red. Por eso no convenia seguir repitiendo `dart run` con el mismo motor.

## Enfoque nuevo: Dart2 + WhatsApp Web + Puppeteer

Se creo `Dart2/whatsapp_web_puppeteer` con otro motor:

- paquete `whatsapp_bot_flutter`;
- `puppeteer`/Chromium;
- inyeccion WA-JS sobre WhatsApp Web;
- sesion local en `data/whatsapp-session/`;
- cache de Chromium en `.local-chromium/`.

Este enfoque no usa `.dll` ni Neonize. Abre una instancia de Chrome controlada por Dart y usa WhatsApp Web como dispositivo vinculado.

## Equivalencia con el bot Baileys

| Node/Baileys | Dart2/Puppeteer |
| --- | --- |
| `makeWASocket()` | `WhatsappBotFlutter.connect()` |
| QR en terminal | QR en Chrome, consola y `data/last_qr.png` |
| `.auth/` | `data/whatsapp-session/` |
| `messages.upsert` | `WhatsappEvent.chatNewMessage` |
| `sock.sendMessage(...)` | WA-JS `WPP.chat.sendTextMessage(...)` |

## Comportamiento implementado

El bot Dart2 responde:

- `ping` -> `pong`;
- cualquier otro texto -> `Recibido: <texto>`.

El proceso queda vivo hasta `Ctrl+C`. Esto fue importante porque la primera version esperaba `stdin.readLineSync()` y la terminal integrada podia devolver EOF/Enter, dejando Chrome abierto pero el proceso Dart cerrado.

## Soporte para JID `@lid`

Durante la prueba real se recibio:

```text
[RX] 231387386908881@lid: ping
```

El helper `client.chat.sendTextMessage(...)` del paquete asume telefonos normales y convierte valores que no contienen `.us` a `@c.us`. Eso rompe cuando WhatsApp Web entrega un chat como `@lid`.

Solucion aplicada:

- si el destinatario contiene `@`, se manda directo por `client.wpClient.evaluateJs(...)`;
- se llama a `WPP.chat.sendTextMessage(...)` con el identificador crudo (`@lid`, `@c.us`, etc.);
- si no contiene `@`, se conserva el helper normal del paquete.

## Comandos de ejecucion

Desde `Dart2/whatsapp_web_puppeteer`:

```powershell
dart pub get
dart run
```

Variables utiles:

```powershell
# Chrome sin ventana visible; usar QR de consola/archivo.
$env:HEADLESS_CHROME="1"
dart run

# Alternativa al QR: codigo de vinculacion por numero.
$env:WHATSAPP_LINK_PHONE="5215512345678"
dart run

# Stack trace completo si falla el arranque.
$env:DART2_DEBUG_STACK="1"
dart run
```

## Resultado validado

En la prueba de esta sesion:

- el QR se pudo vincular;
- se abrio Chrome con WhatsApp Web;
- la terminal llego a `[conn] connected`;
- se recibio un mensaje real desde otro numero (`[RX] ... ping`);
- tras corregir `@lid`, el usuario confirmo que la respuesta funciono.

Esto cumple el objetivo funcional inicial: tener una migracion a Dart capaz de vincular WhatsApp por QR y responder mensajes.

## Limitaciones

- Sigue siendo un metodo no oficial basado en WhatsApp Web.
- La estabilidad depende de cambios de WhatsApp Web y WA-JS.
- Para producto estable/produccion, Meta Cloud API o un proveedor oficial sigue siendo la opcion mas formal.
- Para pruebas locales y validacion del pedido de "hacerlo en Dart", este enfoque funciono mejor que Neonize en esta maquina.
