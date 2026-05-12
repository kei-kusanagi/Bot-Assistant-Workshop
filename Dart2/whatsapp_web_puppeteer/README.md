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
.\scripts\start_bot.ps1
```

Ese script hace el arranque recomendado para desarrollo local: limpia procesos
residuales de Chrome del bot, crea `.env` desde `.env.example` si falta, revisa
Ollama, ejecuta `dart pub get` y finalmente lanza `dart run`.

Tambien puedes arrancar manualmente:

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

El bot carga automaticamente un archivo `.env` local si existe. Para iniciar,
copia `.env.example` a `.env` y ajusta valores una sola vez:

```powershell
Copy-Item .env.example .env
dart run
```

El archivo `.env` no se sube a Git. Si defines una variable en la terminal, esa
variable tiene prioridad sobre el valor del `.env`.

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

## Memoria local y conocimiento

El bot guarda una memoria local limitada en:

```text
data/store/conversations/
```

Cada usuario se identifica por su JID de WhatsApp (`@lid`, `@c.us`, etc.). Para evitar abuso o archivos enormes:

- solo guarda los ultimos 20 mensajes por usuario;
- cada mensaje guardado se recorta a 1000 caracteres;
- si un mensaje entrante supera 2000 caracteres, no se manda a Ollama y el bot pide un resumen.

Si en pruebas ves que el bot **no pide el nombre** al inicio, suele ser porque en
`data/store/conversations/<jid>.json` ya existe `facts.nombre` de una sesion anterior.
Para simular un **primer contacto limpio**, borra ese archivo o vacia el objeto `facts`
(tambien `nombre_pedido` si lo hubiera) y vuelve a escribir *hola*.

El conocimiento oficial del negocio vive en:

```text
data/business_profile.json
```

Si no existe, el bot lo crea automaticamente con campos vacios. Usa `business_profile.example.json` como referencia para llenarlo. La regla importante es: si un dato no esta en ese perfil, el bot debe evitar inventarlo.

Ese mismo archivo tambien puede incluir `responseTemplates` para respuestas directas editables, por ejemplo ubicacion, horario, servicios o tipo de negocio. El codigo solo detecta la intencion general; el texto de la respuesta sale del JSON.

## Agenda local simulada

El bot puede agendar citas en archivos JSON locales antes de migrar a Supabase:

```text
data/availability.json
data/calendar_events.json
data/appointments.json
data/store/appointment_drafts/
```

Si esos archivos no existen, el bot los crea automaticamente. Los archivos `availability.example.json`, `calendar_events.example.json` y `appointments.example.json` documentan la estructura esperada.

El flujo de agenda corre antes de Ollama: detecta intención de cita, pide solo nombre/servicio/dia/hora faltante, calcula horarios libres desde `availability.json` menos `calendar_events.json`, y guarda la cita como `confirmed` para la prueba local. En producción se puede cambiar el store JSON por Supabase manteniendo el mismo `SchedulingService`.

Tambien puedes escribir cosas como *mis citas* (listar activas), *cancelar mi cita* (pide confirmacion con *si cancelar*) o *reprogramar cita* / *cambiar el horario* (elige cita si hay varias y propone nuevo dia/hora). Los borradores de esos pasos viven en `data/store/appointment_drafts/mgmt_*.json` y **caducan a las 24 horas** si el usuario no termina el flujo, para no interpretar dias despues un "2" o un "no" como parte de una cancelacion vieja.

En una sola linea también puedes: *cancelar cita 2*, *reprogramar cita 2*, o *reprogramar cita 2 martes 4pm* (fecha/hora nueva en el mismo mensaje cuando el parser ya entiende dia y hora).

### Sembrado demo para mayo

Para llenar la agenda local con ocupacion ficticia **lunes a viernes, del 11 al 30
de mayo** (slots de 30 minutos, nivel de ocupacion aleatorio reproducible), ejecuta **desde
esta carpeta**:

```powershell
dart run tool/seed_mayo_calendar.dart
```

Opcionalmente indica año (por defecto **2026**, alineado con el calendario demo del
servicio de agendado):

```powershell
dart run tool/seed_mayo_calendar.dart 2026
```

**Importante:** el script **sobrescribe** `data/appointments.json` y
`data/calendar_events.json`. `data/availability.json` no se modifica.

Cada paciente de prueba del seed lleva siempre el **mismo JID ficticio** (por ejemplo
`paciente_arturo_demo@lid` para Arturo, con más citas que otros por peso estadístico)
para que las listas tipo *mis citas* desde tu WhatsApp **no mezclen** citas de
personajes demo con tu identificador real.

Después de sembrar, puedes preguntar al bot por disponibilidad vaga (“esta semana”, “resto del mes”), refinar por franja (mañana / tarde / noche) o dar día y hora desde el primer mensaje para acotar al instante.

Si no aparece `[RX]`, el bot tiene un respaldo por polling de chats no leidos.
Para ver errores de ese respaldo:

```powershell
$env:DART2_DEBUG_POLLING="1"
dart run
```
