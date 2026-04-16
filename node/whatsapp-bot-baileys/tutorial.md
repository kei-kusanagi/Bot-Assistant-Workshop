# Tutorial: bot de WhatsApp con Baileys (QR, local)

Esta guía te lleva **paso a paso** a poner en marcha el bot de la carpeta `whatsapp-bot-baileys`, de forma parecida en espíritu al tutorial de Cloud API en [../docs/tutorial.md](../docs/tutorial.md), pero con un enfoque **distinto**: conexión por **WhatsApp Web** (código QR) y **sin webhook ni ngrok**.

**Qué lograrás:** un proceso **Node** en tu PC que, tras escanear el QR, responde en WhatsApp con un menú de **agenda demo** y guarda las citas en `data/citas.json`.

---

## Seguimiento guiado (con el asistente en Cursor)

Vamos **un paso a la vez** en el chat: el asistente te dice qué hacer; cuando termines, respondes **listo** o pegas el error. Lo que no esté en la guía original (pasos extra, bloqueos, aclaraciones) se va anotando aquí.

**Paso en el que vamos ahora:** *(flujo guiado mínimo cerrado; ver bitácora)*

**Bitácora (pasos extra / incidencias):**

- **Paso 1 (completado):** Carpeta `whatsapp-bot-baileys` correcta; `node -v` → **v22.15.0** (Windows, 15/04/2026). Salida de `dir` incluye `package.json`, `src`, `node_modules`, `tutorial.md`.
- **Nota:** Si ya existe `node_modules` (como en esta sesión), `npm install` sigue siendo recomendable tras clonar o cambiar dependencias; en una máquina “limpia” es obligatorio.
- **Paso 2 (completado):** `npm install` sin incidencias reportadas; creado `.env` desde `.env.example` con `copy .env.example .env`.
- **Paso 3 (completado):** Conexión OK; tras vincular apareció **mucho texto JSON** en consola (`histNotification`, `got history notification`). Es **normal**: Baileys sincroniza datos del historial y, con el logger por defecto, vuelca líneas largas. En el código se configuró **Pino** con nivel por defecto `warn` (`BAILEYS_LOG_LEVEL`) para que la consola sea más legible; añade `BAILEYS_LOG_LEVEL=warn` a tu `.env` si aún no está, reinicia `npm start`.
- **Paso 4 (completado):** Usuario confirmó con `ok` tras ajustar logs y dejar el bot en marcha. Si ya probaste **`hola`** desde **otro** número y viste el menú (1–4), el flujo guiado mínimo está listo. Si el bot no contestó, revisa *Problemas frecuentes*: el número vinculado como “dispositivo” **no** recibe respuestas a sus propios mensajes de prueba.
- **Incidencia:** Tras conectar, consola mostró `bad-request` / `unexpected error in 'init queries'` (nivel 50 en Pino). Documentado en *Problemas frecuentes*; proyecto fijado a Baileys **^6.7.21** para alinear con correcciones recientes.

---

## Requisitos

- **Node.js** 18 o superior
- Teléfono con **WhatsApp** (la cuenta que usarás como “línea del bot” debe poder vincular **WhatsApp Web**)
- Terminal y editor de texto
- (Opcional) Segundo celular o cuenta de prueba para escribirle al número del bot y probar como paciente

---

## Paso 0 — Cómo encajan las piezas

1. **Tu PC:** carpeta `node/whatsapp-bot-baileys`, variables en `.env`, comando `npm start` → el programa se conecta a los servidores de WhatsApp como si fuera **WhatsApp Web**.
2. **QR en terminal:** la primera vez (o si borras la sesión) debes **escanear el código** desde el móvil: *Ajustes → Dispositivos vinculados → Vincular un dispositivo*.
3. **Mensajes:** cuando alguien escribe al **número de WhatsApp que vinculaste al bot**, el script recibe el mensaje y responde por el mismo canal.

**Diferencia clave respecto a `whatsapp-bot-demo` (Meta):** aquí **no** configuras app en Meta ni URL de webhook. El “puente” es la sesión tipo Web del propio WhatsApp.

---

## Paso 1 — Ir a la carpeta del proyecto

En **PowerShell** (ajusta la ruta si tu repo está en otro sitio):

```powershell
cd "c:\Users\admin\Desktop\Proyectos\Bot Assistant Workshop\node\whatsapp-bot-baileys"
```

Comprueba que existen `package.json`, `src\index.js` y `.env.example`.

---

## Paso 2 — Instalar dependencias

```powershell
npm install
```

Debe terminar sin errores. Si cambias de máquina o borras `node_modules`, vuelve a ejecutar este paso.

---

## Paso 3 — Crear el archivo `.env`

Copia el ejemplo:

```powershell
copy .env.example .env
```

Abre `.env` en tu editor. Campos útiles:

| Variable | Qué es |
|----------|--------|
| `CLINIC_NAME` | Nombre que verá el usuario en el saludo del menú. |
| `TIMEZONE` | Zona horaria para mostrar fechas (por defecto `America/Mexico_City`). |
| `DOCTOR_NUMBERS` | Números **solo dígitos**, separados por coma, autorizados a comandos `doc …`. Si lo dejas vacío, nadie tendrá rol doctor en el bot. |

**Formato de número (México, típico en APIs y logs):** suele usarse **`521` + 10 dígitos** del móvil. Ejemplo: si tu celular es `55 1234 5678`, en lista de permitidos a menudo va `5215512345678`. Debe coincidir con cómo WhatsApp identifica al remitente (si un comando doctor “no hace nada”, revisa que el número en `.env` sea exactamente el mismo formato).

Guarda el archivo. Si lo editas con el bot en marcha, **reinicia** `npm start` para que Node vuelva a leer las variables.

---

## Paso 4 — Arrancar el bot

```powershell
npm start
```

**Primera vez (o sin sesión guardada):**

1. En la terminal debería aparecer el texto **“Escanea este QR con WhatsApp”** y un **QR en ASCII**.
2. En el teléfono cuya cuenta actuará como bot: **WhatsApp → Ajustes (o menú ⋮) → Dispositivos vinculados → Vincular un dispositivo**.
3. Escanea el QR.

Cuando la conexión sea correcta, verás algo como **“Bot conectado a WhatsApp Web.”** Deja esa terminal abierta mientras pruebas.

**Sesión guardada:** en la carpeta del proyecto se crea `.auth/` (está en `.gitignore`). Si la borras, tendrás que volver a escanear QR.

---

## Paso 5 — Probar el flujo del “paciente”

Escribe desde **otro WhatsApp** (o desde un segundo número) al **número que vinculaste como bot**.

Prueba en este orden:

1. Escribe **`hola`** o **`0`** → debe aparecer el **menú principal**.
2. **`1`** → horarios disponibles (demo).
3. **`2`** → te pedirá **nombre**, luego **servicio (1–3)**, luego **horario** → al final confirma la cita.
4. **`3`** → lista **tus** citas activas (según el número que escribe).
5. **`4`** → cancelar: elige el **ID** que te mostró en el paso anterior.

Las citas quedan en **`data/citas.json`** (también ignorado por git en `.gitignore` para no subir datos de prueba).

El archivo incluye un objeto **`_meta`** (texto fijo) que explica qué se guarda y qué **no** (por ejemplo, no van ahí las claves de sesión de WhatsApp; esas están en **`.auth/`**).

---

## Paso 6 — (Opcional) Comandos de doctor / recepción

Solo si en `.env` pusiste tu número en **`DOCTOR_NUMBERS`** (mismo formato que en los logs, normalmente `521…` en México).

- **`doc`** → ayuda corta de comandos.
- **`doc agenda hoy`** / **`doc agenda manana`** → citas del día.
- **`doc pendientes`** → listado de citas activas.

---

## Paso 7 — Detener y volver a arrancar

- En la terminal del bot: **Ctrl+C** para detener.
- Para seguir otro día: `npm start` de nuevo. Si existe `.auth/`, **no** debería pedir QR otra vez (salvo que WhatsApp cierre la sesión o borres `.auth/`).

---

## Problemas frecuentes

### El QR no aparece o caduca antes de escanear

Vuelve a lanzar `npm start` para generar QR nuevo. Escanea en cuanto salga; algunos terminales tardan en refrescar.

### “Bot conectado” pero no responde

- Confirma que escribes al **número correcto** (el de la cuenta vinculada al bot).
- El bot ignora mensajes que **él mismo** envía como salida desde el mismo número; prueba desde **otro** número.
- Solo procesa mensajes de **texto** razonablemente parseables; si mandas solo audio/imagen sin texto, puede no reaccionar.
- **WhatsApp y JID `@lid`:** en cuentas nuevas o con más privacidad, los mensajes pueden llegar con identificador `…@lid` en lugar del número `…@s.whatsapp.net`. Versiones antiguas del bot solo aceptaban el segundo formato y **no respondían a nadie**. El código actual acepta **ambos**; si aún no tienes la última versión de `src/index.js`, actualiza el proyecto.

### Logs `PreKeyError` / `failed to decrypt message` con `fromMe: true`

Suelen ser **eco o sincronización** de mensajes enviados desde el mismo teléfono (u otro dispositivo) y no impiden que **otros** chats reciban respuesta. Si solo ves eso pero **desde otro número** el menú funciona, puedes ignorarlos o usar `BAILEYS_LOG_LEVEL=silent`.

### Errores en consola **sin haber enviado ningún mensaje**

Justo al conectar (`Bot conectado a WhatsApp Web.`), WhatsApp puede **empujar datos en cola** (historial, estados, mensajes ya enviados desde el móvil, etc.). Baileys intenta descifrarlos y a veces aparece `failed to decrypt`, `MessageCounterError`, `PreKeyError` o similar, a veces con `fromMe: true` y JID `@lid`. **No significa que el bot esté roto** ni que tú hayas disparado algo: es ruido de sincronización o mensajes duplicados en la capa Signal.

- Si **desde otro número** el bot responde a `hola`, puedes **ignorar** esos logs.
- Para consola casi limpia: en `.env` pon **`BAILEYS_LOG_LEVEL=silent`** (siguen viéndose los `console.log` del propio bot, p. ej. “Bot conectado…”).
- El **`bad-request`** en `init queries` es el tema ya documentado más abajo; también puede salir solo al arrancar.

### Los comandos `doc …` no hacen nada

Tu número no está en `DOCTOR_NUMBERS`, o está en **formato distinto** al que WhatsApp usa internamente. Ajusta `.env`, guarda y **reinicia** el bot.

### Error al instalar o al iniciar

- Versión de Node: `node -v` (debe ser 18+).
- Borrar `node_modules` y reinstalar:  
  `Remove-Item -Recurse -Force node_modules; npm install`

### Tras “Bot conectado…” aparece `bad-request` o `unexpected error in 'init queries'`

Es un fallo **conocido** en Baileys: durante las consultas iniciales a los servidores de WhatsApp, a veces falla el paso `fetchProps` (código **400** / mensaje `bad-request`). **A menudo la conexión sigue siendo usable** y el bot **sí** recibe y envía mensajes.

Qué hacer:

1. **Prueba primero** si desde **otro número** te responde el menú (`hola`). Si funciona, puedes **ignorar** el log o bajar ruido con `BAILEYS_LOG_LEVEL=error` o `silent` en `.env`.
2. Mantén **@whiskeysockets/baileys** actualizado en la rama **6.7.x** reciente (`npm install` en la carpeta del proyecto).
3. Si **no** entran mensajes: cierra el bot, borra la carpeta **`.auth`**, vuelve a ejecutar `npm start` y **escanea el QR** de nuevo (sesión limpia).
4. Contexto upstream: [WhiskeySockets/Baileys — issues sobre init queries / bad-request](https://github.com/WhiskeySockets/Baileys/issues?q=init+queries+bad-request).

### Consideraciones de uso

Este enfoque es útil para **prototipos y pruebas internas**. Para un producto en producción con clientes reales, valorar **WhatsApp Cloud API (Meta)** u otro proveedor oficial por estabilidad, políticas de uso y soporte.

---

## Privacidad: qué es sensible y dónde

| Ubicación | Qué contiene | Sensibilidad |
|-----------|----------------|--------------|
| `data/citas.json` | Nombre escrito por el paciente, identificador de chat (`521…` o `lid:…`), servicio, horario, estado de la cita. | Datos personales de **agenda**; no compartas el archivo ni lo subas a repos públicos. |
| `.auth/` | Credenciales de la sesión tipo Web de WhatsApp (equivalente a “estar vinculado”). | **Muy alta**. Quien copie esta carpeta podría intentar usar la sesión. Manténla solo en tu PC, no en repos ni backups públicos. |
| `.env` | Solo variables de configuración del bot (nombre, zona horaria, etc.). | Baja si no pones secretos; no incluye contraseña de WhatsApp. |

**No** se guarda en `citas.json` el historial de chats completo, contraseñas ni el contenido de mensajes salvo lo que el flujo de agenda pide explícitamente (p. ej. nombre).

---

## Referencia rápida de rutas en el repo

| Elemento | Ubicación |
|----------|-----------|
| Código del bot | `node/whatsapp-bot-baileys/src/index.js` |
| Variables | `node/whatsapp-bot-baileys/.env` |
| Citas (local) | `node/whatsapp-bot-baileys/data/citas.json` |
| Sesión Web (local, no subir a git) | `node/whatsapp-bot-baileys/.auth/` |
| Resumen corto | `node/whatsapp-bot-baileys/README.md` |

---

## Relación con el otro tutorial (Meta + ngrok)

| | `whatsapp-bot-demo` (Meta) | `whatsapp-bot-baileys` (este) |
|--|---------------------------|------------------------------|
| Entrada de mensajes | Webhook HTTPS (ngrok en local) | Conexión tipo WhatsApp Web (QR) |
| Cuenta | App Meta + número de prueba / negocio | Tu WhatsApp vinculado como “dispositivo” |
| Ideal para | Alinear con producción Cloud API | Iterar flujo de conversación y agenda en local |

Cuando añadamos pasos nuevos (Supabase, recordatorios, despliegue en Hetzner, etc.), conviene **seguir ampliando este mismo archivo** bajo nuevas secciones numeradas.
