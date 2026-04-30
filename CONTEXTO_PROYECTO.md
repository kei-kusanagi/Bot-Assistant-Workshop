# Contexto del proyecto (retomar conversación)

**Última intención documentada:** Plataforma tipo plantilla (white-label) para negocios que trabajan por citas — Flutter (web + móvil, un código) y backend **Supabase**, despliegue por cliente (dominio + proyecto Supabase asociado).

**Documento de propuesta formal:** Ver `PROPUESTA_PLATAFORMA_CITAS.md` en esta misma carpeta (si existe en el repo).

**Nota:** Este archivo **sí se versiona** en Git (desde abr. 2026) para retomar entre máquinas.

---

## Visión del producto

- Mismo **cascón / molde** para muchos clientes (dentistas, terapeutas, psicólogos, etc.).
- Por cliente: identidad, textos, imágenes, servicios, precios publicados (si aplica), horarios de consulta y **horarios de atención por chat**.
- Oferta entendida como **web + app** para pacientes; panel usable también en **tableta** en recepción.

---

## Citas

- Las citas creadas por canales automáticos (web / asistente) pueden empezar en **“por confirmar”**.
- **“Confirmada”** solo por acción **humana** del negocio (recepción / admin según roles).
- Recepción puede **crear o ajustar citas manualmente** para quien agenda por teléfono u otros medios tradicionales.

---

## Pacientes: invitado → registrado

- Flujo sin registro completo: se pide **correo**; se envía información de la cita; en backend queda registro acotado al correo (usuario temporal / invitado — término de implementación pendiente).
- Si después la misma persona **se registra** en la app, se debe poder **fusionar** historial (citas e indicaciones previas ligadas a ese correo) bajo un solo usuario.

---

## Asistente conversacional (no “IA médica”)

- **Base de conocimiento = solo lo publicado/cargado** en el sitio: ubicación, servicios, enlaces (ej. a página de servicios), precios si están cargados con **disclaimer** de que pueden cambiar sin previo aviso.
- Si no hay dato fiable o la pregunta sale del contenido publicado: **no inventar**; ofrecer **llamar al negocio** (u otro canal acordado).
- **No** está centrado en “siempre conviene agendar”; puede orientar como un bot típico de sitio web dentro de ese límite.

---

## Chat con humano

- Solo si: (1) el usuario **lo pide explícitamente**, o (2) el asistente **no resuelve** y **él propone** hablar con alguien.
- Respeta **horarios de chat** configurados por el negocio.
- **Notificación** a usuarios con rol **recepcionista** (app, sesión iniciada).
- Mensaje al visitante: puede **tardar unos minutos** si recepción está ocupada.
- **Escalado:** si no hay respuesta en un **tiempo definible por configuración**, notificar también a **administradores**.
- Objetivo operativo: conversación **ligada al usuario**; desde recepción poder **agendar** en contexto del chat.

---

## Seguimiento al paciente (futuro / fases)

- Mencionado en conversación: listados tipo indicaciones (ej. medicación con recordatorios), actividades, mood tracker — **después** del núcleo; temas legales/salud según jurisdicción no detallados en código aún.

---

## Stack acordado en conversación

- **Flutter:** web + móvil.
- **Supabase:** backend por despliegue de cliente (datos, auth, tiempo real/notificaciones según diseño).
- **Infra mencionada:** ideal **Hetzner** para hosting del bot/servicios cuando salga de local; Supabase puede ser **self-hosted** o en la nube según decisión por cliente.

---

## Entorno local — NanoClaw / Claude Code en Windows + WSL + Rancher Desktop (abr. 2026)

**Objetivo:** instalar/correr **NanoClaw** desde **Ubuntu en WSL2** usando **Rancher Desktop** como runtime Docker en Windows 10.

**Problema inicial:** `bash nanoclaw.sh` fallaba al preparar el sandbox con:

- `Docker not running — attempting to start platform="linux"`
- `Failed to start docker.service: Unit docker.service not found.`
- `ERROR: runtime_not_available`

**Diagnóstico:** no era la contraseña de `sudo`. En WSL no existía `docker.service` como servicio normal de Linux; Docker debía venir del runtime de Rancher Desktop. Además:

- Rancher Desktop primero estaba trabado: la UI abría, pero `rancher-desktop` aparecía `Stopped` en `wsl -l -v`.
- `docker version` en Windows llegó a fallar con `open //./pipe/docker_engine: The system cannot find the file specified`.
- Tras reinstalar Rancher Desktop, el daemon sí levantó, pero Ubuntu no tenía el comando `docker` en PATH.
- El socket correcto expuesto por Rancher para WSL fue: `/mnt/wsl/rancher-desktop/run/docker.sock`.

**Configuración que terminó funcionando en Rancher Desktop:**

- **Container Engine:** `dockerd (moby)`.
- **Kubernetes:** desactivado para esta prueba.
- **WSL Integration:** `Ubuntu` activado.
- Rancher Desktop reinstalado cuando quedó en estado inconsistente.

**Comprobaciones útiles:**

```powershell
wsl -l -v
```

Debe mostrar `rancher-desktop` en `Running`.

```powershell
"C:\Program Files\Rancher Desktop\resources\resources\win32\bin\docker.exe" version
```

Debe mostrar `Client` y `Server`.

En Ubuntu/WSL, con el binario de Rancher:

```bash
DOCKER_HOST=unix:///mnt/wsl/rancher-desktop/run/docker.sock \
  "/mnt/c/Program Files/Rancher Desktop/resources/resources/linux/bin/docker" ps
```

**Ajuste local aplicado en Ubuntu:** se creó un wrapper en:

```bash
~/.local/bin/docker
```

para que `docker` use el binario de Rancher y el socket correcto. También se dejó `~/.local/bin` disponible en el PATH de la shell. La prueba final `docker ps` respondió correctamente desde Ubuntu.

**Resultado con NanoClaw:** al volver a correr:

```bash
cd ~/nanoclaw-v2
bash nanoclaw.sh
```

NanoClaw ya pudo preparar el sandbox. Llegó a:

- `Sandbox ready`
- `OneCLI vault ready`
- pantalla para conectar con Claude.

**Conclusión sobre Claude / Anthropic:** para usar NanoClaw/Claude Code de forma real parece necesario **pagar** o tener credenciales de una cuenta con acceso:

- **Claude Pro/Max**: opción recomendada por NanoClaw si ya existe suscripción.
- **Anthropic API key**: requiere cuenta en Anthropic Console y normalmente método de pago / crédito de uso.
- La cuenta gratuita de Claude puede servir para la web, pero no parece suficiente para conectar NanoClaw si pide suscripción o API key.

**Pendiente / decisión:** preguntar al jefe si ya existe cuenta corporativa de Claude/Anthropic o presupuesto para API key. Técnicamente Docker/Rancher/NanoClaw ya quedaron resueltos; el bloqueo restante es **credencial/costo**.

---

## Avances técnicos — bots WhatsApp (dos enfoques en el repo)

### A) `node/whatsapp-bot-demo` — WhatsApp Cloud API (Meta)

- **Node + Express**, webhook, **ngrok** (o túnel similar) para desarrollo local.
- Documentación paso a paso: `node/docs/tutorial.md`.
- Cuenta Meta de pruebas configurada para seguir iterando.

### B) `node/whatsapp-bot-baileys` — WhatsApp Web (Baileys + QR) — *añadido en esta línea de trabajo*

- **Enfoque distinto:** sin webhook de Meta ni ngrok; conexión por **QR** (sesión tipo WhatsApp Web).
- **Stack:** `@whiskeysockets/baileys` (actualizado a ^6.7.21), **pino** con `BAILEYS_LOG_LEVEL` (p. ej. `warn` o `silent`) para reducir ruido en consola.
- **Agenda demo:** menú por texto (horarios, agendar, listar, cancelar); comandos `doc …` si se configuran números en `DOCTOR_NUMBERS` (acepta `521…` o `lid:…` para chats con JID `@lid`).
- **Persistencia local:** `data/citas.json` con array `appointments` y objeto **`_meta`** que documenta qué se guarda y qué no.
- **Privacidad rápida:**
  - `citas.json`: datos de agenda (nombre, id de chat, servicio, horario) — datos personales de demo, no subir en repos públicos.
  - **`.auth/`:** sesión Baileys (muy sensible; no compartir; en `.gitignore` del subproyecto).
  - No se guarda contraseña de WhatsApp en JSON; la sesión vive en `.auth/`.
- **Problemas vistos en pruebas:** logs `bad-request` en `init queries`, errores de descifrado al conectar sin enviar mensajes — comportamiento conocido de sincronización; ver `tutorial.md`.
- **Bug corregido en código:** al principio solo se aceptaban chats `...@s.whatsapp.net`; WhatsApp a veces usa **`...@lid`**, y el bot ignoraba todos los mensajes. Ahora se aceptan chats directos PN y LID.
- **Tutorial guiado:** `node/whatsapp-bot-baileys/tutorial.md` (sección “Seguimiento guiado” + problemas frecuentes + tabla de privacidad).

### C) `Dart/whatsapp_qr_pairing` — QR + emparejamiento en Dart (misión reciente)

- **Objetivo del jefe:** traducir a Dart **solo** la funcionalidad equivalente a “mostrar QR y emparejar WhatsApp” (como Baileys en Node), con pasos documentados en Markdown, commits semánticos en inglés, **Ollama** disponible (local o Docker) y **Docker** para el CLI.
- **Implementación:** paquete consola Dart con **`neonize`** (FFI + librería nativa `.dll`/`.so`; variable **`NEONIZE_PATH`** obligatoria). Carga **diferida** del módulo para validar la ruta antes de abrir el `.so`/`.dll`.
- **Documentación de migración / pasos:** `Dart/docs/MIGRATION_FROM_NODE_BAILEYS.md`.
- **Índice carpeta Dart:** `Dart/README.md`.
- **Docker:** `Dart/whatsapp_qr_pairing/Dockerfile` (compila `dart compile exe`); **`Dart/docker-compose.yml`** con servicio **`ollama`** (puerto 11434) y perfil opcional **`whatsapp`** para el contenedor del CLI (requiere montar la librería Neonize en `./neonize`).
- **Commits semánticos (inglés):** el historial de esa misión quedó **reorganizado en commits atómicos** (pedido del jefe). Lista exacta **en orden** (mensajes tal cual en `git log`):
  1. `chore(dart): add whatsapp_qr_pairing package skeleton`
  2. `feat(dart): implement Neonize QR pairing with deferred native load`
  3. `docs(dart): add README for WhatsApp QR pairing CLI`
  4. `build(dart): add Dockerfile for compiled WhatsApp QR CLI`
  5. `docs(dart): add Baileys migration log and Dart workspace index`
  6. `chore(dart): add docker-compose with Ollama sidecar`
  7. `docs(dart): document semantic commit convention and mission history`
- **Commits posteriores (auto-descubrimiento Neonize, abr. 2026):**
  8. `fix(neonize): resolve native library path when NEONIZE_PATH is unset`
  9. `feat(dart): auto-discover Neonize DLL and clarify whatsapp_qr_pairing entry`
- **Commits — diagnóstico timeout sin QR (abr. 2026):** ver lista exacta bajo *Incidente: timeout sin entrega de QR*; resumen: hints en login, logging Dart desde `NEONIZE_LOG_LEVEL`, `DeviceProps` CHROME y documentación de último intento.
- **Guía de convención (inglés):** `Dart/docs/SEMANTIC_COMMITS.md` — prefijos `feat` / `fix` / `docs` / `build` / `chore` y la tabla anterior para explicar al equipo o al jefe cómo se nombraron los commits.
- **Git / push:** si en algún momento se habían subido al remoto **los 3 commits viejos** de Dart (antes de la reorganización), el historial local **diverge**; puede hacer falta **`git push --force-with-lease`** (solo si nadie más depende de esos SHAs) o coordinar. Si **nunca** se subieron esos tres, un `git push` normal alinea el remoto con estos siete commits.
- **Ollama:** instalar desde https://ollama.com o usar el servicio del compose; **aún no** integrado en la lógica del bot (preparación para modelos locales / asistente después).
- **Alcance explícito no portado a Dart en esta misión:** menú de citas, `citas.json`, comandos `doc`, etc. (siguen en Node/Baileys).

#### Incidente: timeout sin entrega de QR (abr. 2026) — *último intento mañana; si no, se deja en paz*

**Síntoma en consola (máquina de desarrollo, tras varios ciclos):** el CLI imprime conexión a DB y `DeviceProps`, logs `[neonize-dart] FINE/INFO` correctos, **no** aparece línea de “QR recibido” ni el bloque “Escanea este QR…”, y el nativo reporta `Login event: timeout` y a veces `Press Ctrl+C to exit` (este último **proviene del binario Go** en el `.dll`, no del Dart del taller). **No es un bucle lógico del código Dart** si el callback FFI del QR nunca se invoca: el fallo queda en **cadena nativa (Neonize/whatsmeow) / red / sesión** antes de generar o entregar el QR.

**Qué ya se probó / instrumentó en repo:**

- Carga de librería sin `NEONIZE_PATH` si el `.dll` está en el directorio de trabajo; logs Dart activables con `NEONIZE_LOG_LEVEL=DEBUG` (p. ej. se ven `Registering callback`, ruta de `neonize.db`, `DeviceProps`).
- `DeviceProps` en el CLI del taller: **`platformType=CHROME`** por defecto (más alineado a “Dispositivos vinculados” que el `SAFARI` implícito de Neonize); se puede forzar con `NEONIZE_DEVICE_PLATFORM=SAFARI|CHROME|EDGE|DESKTOP`.
- Mensaje explícito en `onLogginStatus` (parche en `third_party/neonize`) si el estado contiene `timeout`, y aviso en consola antes de `connect()`.
- Cierre: si tras borrar `data/` y sin `dart.exe` bloqueando archivos el problema continúa, **aparcar** el emparejamiento Neonize en esa máquina y seguir con **Node/Baileys** o **Cloud API** en el producto, sin forzar más el mismo bucle.

**Posible plan “última vuelta” (mañana, checklist):**

1. Cerrar **todos** los `dart.exe` / IDEs que tengan el CLI colgado; borrar **toda** la carpeta `data/` (o al menos `neonize.db` + `temp/`), no solo un archivo a medias.
2. Comprobar **misma red** que permita WhatsApp (sin VPN agresivo, sin proxy corporativo que corte wss, firewall que permita el cliente).
3. Re-descargar el `.dll` del **mismo tag** documentado (p. ej. `0.3.16.post0` en `krypton-byte/neonize` releases) y **sustituir** el archivo local por si el binario estuvo corrupto o mezclado.
4. Probar `NEONIZE_DEVICE_PLATFORM=EDGE` (o vuelta a `SAFARI`) por si el dispositivo simulado importa con la build actual de WhatsApp.
5. **Aislar la máquina:** en el **mismo PC**, arrancar el demo **Node** `whatsapp-bot-baileys` (QR Baileys). Si ahí el QR **sí** sale, el bloqueo es **específico de Neonize/FFI**; si tampoco sale, apunta más a **red/cuenta/entorno**.
6. Si sigue el timeout: **cierre** de la línea Neonize en local para este taller; dejar el código documentado y continuar producto con otra pila aprobada.

**Commits (inglés) asociados a esta fase (orden sugerido en `git log`):**

1. `fix(neonize): add stderr hints when login status reports timeout`
2. `feat(dart): wire NEONIZE_LOG_LEVEL to Dart root logging in QR CLI`
3. `feat(dart): use CHROME DeviceProps and log pairing metadata for workshop CLI`
4. `docs: document Neonize QR timeout incident and last-resort checklist`

### C2) `Dart2/whatsapp_web_puppeteer` — migración funcional QR a Dart (Puppeteer + WhatsApp Web) — *abr. 2026*

**Motivo:** el camino `Dart/whatsapp_qr_pairing` con **Neonize/FFI** cargaba la `.dll`, pero quedaba en `Login event: timeout` **sin callback de QR**. Para no seguir repitiendo el mismo bucle, se creó una ruta separada **`Dart2/`** con otro motor.

**Enfoque:** Dart puro de consola con **`whatsapp_bot_flutter` + Puppeteer/Chromium + WA-JS**, sin `.dll` Neonize. Abre una instancia de Chrome controlada por Dart, muestra/vincula WhatsApp Web por QR, guarda sesión en `data/whatsapp-session/` y cachea Chromium en `.local-chromium/`.

**Código / docs:**

- Proyecto: `Dart2/whatsapp_web_puppeteer`
- Guía técnica: `Dart2/DOCS/MIGRATION_FROM_NODE_BAILEYS.md`
- Entrada CLI: `Dart2/whatsapp_web_puppeteer/bin/whatsapp_web_puppeteer.dart`

**Resultado validado en sesión:** el QR se vinculó, Chrome abrió WhatsApp Web, la terminal llegó a `[conn] connected`, se recibió un mensaje real desde otro número (`[RX] ...@lid: ping`) y, tras corregir envío a chats `@lid`, el usuario confirmó que **sí respondió**.

**Cambios clave del Dart2:**

- El proceso queda vivo hasta **Ctrl+C** (evita que Chrome quede abierto pero Dart ya no escuche).
- Listener `WhatsappEvent.chatNewMessage`.
- Respuesta demo: **`ping` → `pong`** y resto de texto `Recibido: ...`.
- Fix importante: si el remitente viene como **`@lid`**, no se usa el helper `sendTextMessage` del paquete porque intenta convertirlo a `@c.us`; se manda directo con `WPP.chat.sendTextMessage(...)` usando el identificador crudo.

**Comandos:**

```powershell
cd "c:\Users\admin\Desktop\Proyectos\Bot Assistant Workshop\Dart2\whatsapp_web_puppeteer"
dart pub get
dart run
```

**Conclusión práctica:** esto cumple mejor la intención original del jefe de migrar a Dart la parte de **QR + vincular WhatsApp + responder mensajes**, aunque no es una traducción línea por línea de Baileys (Baileys no existe en Dart). Es una **migración funcional** usando otro motor Dart.

### C3) IA modular tipo NanoClaw aplicada en Dart2 — *abr. 2026*

**Nueva indicación del jefe:** no se trataba de migrar NanoClaw literal, sino de **tomar el enfoque y aplicarlo**: una arquitectura genérica para conectar distintos modelos/proveedores al bot, usando **Dart y su sistema de paquetes**, no npm. Ollama encaja como primer proveedor local; después se podrían agregar OpenAI/Anthropic/etc.

**Implementación inicial en `Dart2/whatsapp_web_puppeteer`:**

- `lib/ai/ai_provider.dart`: contrato abstracto `AIProvider` con `Future<String> generateResponse(String prompt)`.
- `lib/ai/providers/ollama_provider.dart`: proveedor HTTP contra **Ollama local** (`http://localhost:11434`, endpoint `/api/generate`, `stream: false`).
- `lib/ai/ai_service.dart`: capa que recibe un `AIProvider`, construye un prompt de sistema simple para asistente de citas y expone `getResponse(message)`.
- `bin/whatsapp_web_puppeteer.dart`: reemplaza la respuesta fija `ping -> pong` / `Recibido: ...` por respuesta generada desde `AIService`.
- Respaldo de recepción: además de `WhatsappEvent.chatNewMessage`, se agregó **polling cada 3s** de chats no leídos porque en una corrida WhatsApp quedó `[conn] connected` pero no emitió `[RX]` al llegar un mensaje. Si el respaldo detecta mensajes, imprime `[RX/poll]`.

**Configuración por entorno:**

```powershell
$env:OLLAMA_BASE_URL="http://localhost:11434"
$env:OLLAMA_MODEL="llama3.2:3b"
dart run
```

**Doc técnica:** `Dart2/DOCS/AI_ADAPTER_ARCHITECTURE.md`.

**Validación parcial:** `ollama pull llama3.2:3b` descargó el modelo y el bot conectó a WhatsApp (`[conn] connected`). En la primera prueba de IA no apareció `[RX]`, por lo que se agregó el respaldo por polling. Siguiente validación: reiniciar el bot y confirmar que al enviar mensaje aparece `[RX]` o `[RX/poll]`, y que la respuesta sale de Ollama.

### D) `Flutter/whatsapp_wa_drago` — Drago (whatsapp-web.js + InAppWebView) — *exploración abr. 2026*

**Motivo:** probar la ruta “Dart obligatorio + UI” con el paquete **`drago_whatsapp_flutter`** (WPP inyectado en un WebView), como alternativa al CLI **Neonize**.

**Qué se implementó (código en repo):**

- App Flutter mínima: botón **Conectar (QR)**, flujo **headless** (`DragoWhatsappFlutter.connect`) en plataformas no Windows / no web, y en **Windows de escritorio** y **navegador** pantalla con **`connectWithInAppBrowser`** + `InAppWebView` (archivo `lib/drago_embedded_wa_page.dart` antes `windows_…`).
- **`path_provider` + `sessionPath`:** evitar `userDataFolder` nulo con `saveSession: true` en Windows (riesgo de crash nativo al crear WebView2).
- **`third_party/flutter_inappwebview_windows`:** copia del paquete pub **0.6.0** con **un parche C++** en `custom_platform_view.cc` (rama fallback: `webview_` → `view`; el .pub en esa versión no compilaba con pixel-buffer).
- **`windows/CMakeLists.txt` de la app:** `FLUTTER_WEBVIEW_WINDOWS_USE_TEXTURE_FALLBACK=ON` para no usar texturas D3D (en varias GPU/driver el motor Flutter se cae; “Lost connection to device”).
- **`dependency_overrides`:** ruta al `third_party` anterior + fijar **`flutter_inappwebview_platform_interface: 1.3.0+1`** (un `pub get` con override git a `master` había subido una beta incompatible con `flutter_inappwebview` 6.1.5).
- **Web (`flutter create --platforms=web`):** Meta **no permite** cargar `web.whatsapp.com` en un **iframe** desde `localhost` (política de seguridad / `X-Frame-Options`); el error “rechazó la conexión” es **esperado**. Pantalla informativa + **`url_launcher`** para abrir WA en otra pestaña (solo uso manual; **no** conecta el bot).
- **Import condicional:** `headless_connect_io.dart` / `headless_connect_stub.dart` — el headless usa `dart:io` y carpeta de sesión; en **web** no aplica.
- **`analysis_options.yaml`:** excluir `third_party/**` del analyzer.

**Resultado en la máquina de pruebas (documentar expectativas):**

- **Windows `.exe`:** al conectar, el proceso aún podía **cerrarse** (crash nativo WebView2/texture) aun con sesión y fallback; **Chrome** (`flutter run -d chrome`) no crashea la app pero **no puede** embeber WhatsApp; abrir otra pestaña = WhatsApp normal, **sin** Drago/WPP inyectado — **no** hay respuestas automáticas desde esta app.
- **Conclusión de producto:** para **bot real en Dart** con estabilidad, priorizar el **CLI Neonize** (u otra pila no basada en este WebView embebido en Windows) frente a esta UI Flutter Drago, salvo un entorno donde el WebView embebido sea estable.

**Comandos útiles (desde el subproyecto):**

- Escritorio Windows: `flutter run -d windows`
- Navegador: `flutter run -d chrome`

**Commits (inglés) asociados a este bloque (orden cronológico):**

1. `fix(dart): honor NEONIZE_LOG_LEVEL in vendored neonize client`
2. `docs: track CONTEXTO_PROYECTO and document Flutter Drago WebView limits`
3. `feat(flutter): add whatsapp_wa_drago Drago sample and patch Windows inappwebview`

---

## Retomar la siguiente sesión — empieza aquí (abril 2026)

**Estado al cierre de hoy (sesión en curso):** el demo Dart **arranca, carga el `.dll` y registra logs**; en al menos un entorno de prueba el flujo de **emparejamiento vía QR no completó** (`Login event: timeout` **sin** callback de QR). Ver *Incidente: timeout sin entrega de QR* en la sección Dart. Queda **reintentar** con el checklist allí; si no hay QR estable, **aparcar** Neonize en esa máquina y seguir con Baileys/Cloud API.

### Qué hicimos en esta ronda (resumen operativo)

1. **Dart / Flutter en PATH**  
   El `dart` del sistema a veces apuntaba a `C:\tools\dart-sdk` (**2.19**). La solución fue priorizar `C:\src\flutter\bin` en el PATH y/o fijar en Cursor (SDK) `dart.sdkPath` y `dart.flutterSdkPath` hacia el Flutter del usuario (p. ej. `C:\src\flutter\…`). **La terminal integrada de Cursor** puede mostrar otra versión de Dart que PowerShell suelto: conviene comprobar `where.exe dart` y `dart --version` **en la misma ventana** que usarás.

2. **Crashes nativos (`fatal error: fault` / `gobytes: length out of range`)**  
   No era mala suerte del `.dll` solo: el export C **`Neonize(...)`** en la librería Go incluye un callback **`logCb`** entre el callback de eventos y el buffer de subscripciones. El `neonize` de **pub.dev 1.0.0** **no** pasaba ese argumento; los parámetros quedaban desalineados y el binario reventaba.  
   **Arreglo en repo:** copia local **`Dart/third_party/neonize`** (parche mínimo en `lib/src/ffi/bindings.dart` + `lib/src/client.dart`) y en `Dart/whatsapp_qr_pairing/pubspec.yaml` **`dependency_overrides`** a esa ruta.  
   - Commit de referencia: `fix(dart): vendor neonize with logCb FFI to match native Neonize()`.

3. **DLL**  
   Se recomienda el **`neonize-windows-amd64.dll`** alineado con un release reciente (p. ej. tag **`0.3.16.post0`** en `krypton-byte/neonize` releases), no un archivo arbitrario. Sigue yendo **junto al `pubspec.yaml`**, y por **`.gitignore`** no se sube a Git.

4. **QR “invisible” en consola / sin malla**  
   `qrTerminal` de Neonize usa **ANSI** (fondos de color). Además, `QrCode(4,…)` no cabe para la **cadena larga** de pairing: hay que usar **`QrCode.fromData`** (tamaño automático) para el ASCII.  
   - Commits: `fix(dart): show QR as…` y ajuste posterior a `fromData` en el mismo `neonize_pairing.dart`.

5. **Crash: “Cannot invoke native callback outside an isolate”** (tras `Login event: timeout`, etc.)  
   Los callbacks FFI estaban con **`NativeCallable.isolateLocal`**; el binario Go los llama **desde otro hilo** → el VM aborta. **Arreglo** en `Dart/third_party/neonize` (`lib/src/client.dart`): **`NativeCallable.listener`**; en `event.dart` **copia** de bytes en `rawEmit` antes de parsear, porque con `listener` el handler corre **asíncrono** y el puntero C podría invalidarse. Se guardan referencias a los callables y se hace **`close()`** en `disconnect()`.

6. **Funcionalidad del CLI** (ya en código)  
   Tras conectar, `on<Message>` hace eco: **`ping` → `pong`**, resto de texto `Recibido: …` (mismo espíritu que el menú mínimo en Node). Hace falta **probarlo** con otro móvil/cuenta.

7. **Sesión / datos locales**  
   Se borró `data/` al depurar; al volver a emparejar se regenera `data/neonize.db` y `data/temp/`.

### Neonize en esta máquina (configuración típica)

- **`neonize-windows-amd64.dll`** en `Dart/whatsapp_qr_pairing\` (no en Git).  
- **No** usar `.whl` (Python) para el cliente Dart.  
- **Arranque (PowerShell) desde el paquete:**

```powershell
cd "c:\Users\admin\Desktop\Proyectos\Bot Assistant Workshop\Dart\whatsapp_qr_pairing"
dart pub get
$env:NEONIZE_PATH = (Join-Path $PWD "neonize-windows-amd64.dll")
dart run
```

- Tras conectar, **Enter** en la terminal = desconectar y salir.

### Continuamos mañana justo aquí (siguiente paso inmediato)

1. Mismo `cd` y bloque de arriba (con `dart pub get` si alguien clonó el repo o cambió rama).  
2. Escanear el QR con **WhatsApp → Dispositivos vinculados**.  
3. Ver en consola **“Conectado a WhatsApp (sesion lista).”** (y, si aplica, logs `fine` del `logCb`).  
4. Desde **otro** número, enviar **texto** al número vinculado: probar `ping` y un mensaje normal; debería verse `[RX] …` y la respuesta automática.  
5. **Enter** para desconectar.  
6. Si todo OK: `git status` y **`git push`** de los commits nuevos (vendor + fix QR + anteriores según tengas en local).  
7. Línea de producto: **Ollama** aún no cableado al bot Dart; **Docker/compose** sigue documentado; siguiente iteración posible: menú de citas / Supabase, o seguir con **Meta Cloud API** en Node.

### Git — recordatorio

- Puede faltar `git push` con los commits recientes. Los overrides y `third_party/neonize` **sí** están en el historial (carpeta grande a propósito).

**Commits añadidos en esta fase (además de docs viejos de la lista anterior):** incluyen al menos `feat(dart): handle incoming text and reply via Neonize`, el fix de **vendor + logCb**, y el fix de **QR ASCII + cadena**; ver `git log --oneline -15` para la lista exacta en tu árbol.

**Recordatorio de contexto de producto (sin cambio):** migrar QR a Dart acerca el stack a **Flutter**; **Ollama** y **Docker** son preparación futura. Menú de citas completo sigue en **Node/Baileys** o **Cloud API** según prioridad.

---

## Próximos pasos sugeridos (cuando se retome)

- Migrar citas de `citas.json` a **Supabase** (tablas por diseñar).
- Recordatorios y pagos (fuera del alcance actual de los demos).
- Despliegue continuo en **Hetzner** cuando toque salir de local.

---

## Temas no cerrados en conversación (producto)

- Política de calendario mientras una cita está **“por confirmar”** (¿bloquea hueco o sigue libre?).
- Tiempos concretos de **escalado** de notificaciones y textos UX exactos.
- Modelo de datos detallado (tablas Supabase, merge invitado→registrado).
- Alcance legal / términos para datos de salud si el seguimiento al paciente crece.

---

*Archivo de contexto para continuidad entre sesiones; no sustituye documentación formal frente a stakeholders.*
