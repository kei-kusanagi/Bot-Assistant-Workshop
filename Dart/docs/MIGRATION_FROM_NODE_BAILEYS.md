# Migración conceptual: Node (Baileys) → Dart (Neonize) — solo QR + emparejamiento

Este documento es el **diario de pasos** que pidió el equipo: qué equivalencias hay, qué se hizo en el repo y qué falta para producción.

---

## Cómo se “siente” igual que en Node (lo que ya probaste)

En **Node + Baileys** hiciste esto, en orden:

1. `npm start` → el proceso arranca.
2. Sale un **QR en la terminal** (o reconecta con `.auth/` guardado).
3. En el móvil: **WhatsApp → Dispositivos vinculados → escanear**.
4. Cuando conecta, el bot puede **recibir mensajes** (en tu demo, menú de citas).

En **Dart + Neonize** es el **mismo ritual de usuario** (pasos 1–3). La diferencia es **por debajo**:

| Qué notas tú | Node (Baileys) | Dart (Neonize) |
|--------------|----------------|----------------|
| Comando para arrancar | `npm start` en `whatsapp-bot-baileys` | `dart run` en `whatsapp_qr_pairing` (con `NEONIZE_PATH` ya definido) |
| Dependencia extra | ninguna (npm trae todo JS) | **archivo `.dll` / `.so`** aparte + variable `NEONIZE_PATH` |
| Dónde vive la sesión | carpeta `.auth/` | `data/neonize.db` + `data/temp/` |
| Qué sale en pantalla | QR ASCII + “Bot conectado…” | QR ASCII + “Conectado a WhatsApp…” |

Este proyecto Dart **solo implementa hasta “conectado”**; el menú de citas sigue siendo el ejemplo Node si quieres comparar “misma cuenta, otro stack”.

### Qué demonios es “Neonize” y por qué hay que descargar algo aparte

Hay **dos cosas distintas** con nombre parecido:

1. **Paquete Dart `neonize` (en pub.dev)**  
   Es solo **código Dart**: tipos, llamadas FFI, helpers. Eso lo instala `dart pub get` **solo**.  
   Ese código **no puede** hablar solo con los servidores de WhatsApp: necesita un **motor compilado** (binario nativo).

2. **Librería nativa Neonize (el `.dll` / `.so`)**  
   Es un **archivo binario** generado por el proyecto **[neonize en GitHub](https://github.com/krypton-byte/neonize)** (por debajo, lógica tipo **whatsmeow** / Go).  
   Ahí está el protocolo pesado (cifrado, sesión, etc.), igual que Baileys trae su stack dentro de `node_modules`, pero en el ecosistema Neonize **no** lo empaquetan dentro del paquete Dart de pub: **tú** descargas el `.dll` y se lo indicas con **`NEONIZE_PATH`**.

**Por qué no ves `.dll` a simple vista en GitHub:** en cada release hay **muchos** archivos (Linux, macOS, Android, varias versiones de Windows, wheels de Python…). La página a veces muestra solo unos cuantos y el resto está tras **“Show all 25 assets”** (o similar). Ahí **sí** están los `.dll`.

**Qué archivo bajar en Windows (PC normal 64 bits):**

- Nombre típico: **`neonize-windows-amd64.dll`**
- Si tu Windows es muy antiguo o 32 bits: **`neonize-windows-386.dll`**
- ARM (Surface X, etc.): **`neonize-windows-arm64.dll`**

En el **último release** al momento de revisar la API de GitHub, el enlace directo de ejemplo para amd64 era (el número de versión **cambia** con el tiempo; si falla, entra a *Releases* y copia el URL del mismo nombre en el release más nuevo):

https://github.com/krypton-byte/neonize/releases/download/0.3.16.post0/neonize-windows-amd64.dll

Guárdalo donde quieras, por ejemplo `C:\libs\neonize-windows-amd64.dll`.

### Paso A.1 — Descargar la DLL (Windows)

1. Abre https://github.com/krypton-byte/neonize/releases/
2. Entra al **release más reciente**.
3. Desplázate a **Assets** y pulsa **“Show all … assets”** si no ves la lista completa.
4. Descarga **`neonize-windows-amd64.dll`** (o la variante que corresponda a tu CPU).

**No uses el archivo `.whl` (rueda de Python)**  
Si al pulsar “Windows” o un enlace parecido te sale algo como `neonize-…-py310-none-win_amd64.whl` (“Archivo WHL”), eso es para **instalar Neonize en Python con pip**, **no** sirve para nuestro proyecto Dart. Cierra esa descarga y en la **misma lista de Assets** busca el que termina en **`.dll`**, nombre **`neonize-windows-amd64.dll`**.

### Paso A.2 — Ejecutar el CLI del repo

```powershell
cd "c:\Users\admin\Desktop\Proyectos\Bot Assistant Workshop\Dart\whatsapp_qr_pairing"
$env:NEONIZE_PATH="C:\libs\neonize-windows-amd64.dll"
dart run
```

(Sustituye por la ruta real donde guardaste el `.dll`.)

4. Escanea el QR como hiciste con Baileys. Cuando veas **“Conectado a WhatsApp…”**, pulsa **Enter** en la terminal para desconectar (así está escrito el demo).

Si falla al cargar, copia el **mensaje de error completo** de la terminal (o dime qué versión de Windows / 32 o 64 bits usas).

### Estado en el taller (referencia)

- En el PC de desarrollo el `.dll` quedó colocado en **`Dart/whatsapp_qr_pairing/neonize-windows-amd64.dll`** junto al `pubspec.yaml`.
- Ese archivo **no** se sube a Git: el `.gitignore` del paquete incluye `neonize-*.dll` para no versionar binarios ni sesiones.

---

## Paso 0 — Alcance (qué se tradujo y qué no)

| En Node (`whatsapp-bot-baileys`) | En Dart (`whatsapp_qr_pairing`) |
|----------------------------------|-----------------------------------|
| `@whiskeysockets/baileys` + Node | Paquete **`neonize`** (FFI a librería nativa Neonize / ecosistema Go) |
| `makeWASocket` + `useMultiFileAuthState` | `NewAClient` + `Config(databasePath, tempPath)` |
| Callback de QR (`qrcode-terminal`) | `client.qr(...)` + `qrTerminal()` de neonize |
| Carpeta `.auth/` (credenciales Baileys) | Base **`neonize.db`** + temp bajo `data/` (misma sensibilidad: sesión de WhatsApp) |
| Menú de citas, `citas.json`, etc. | **Fuera de alcance** de esta misión: solo **QR y conexión** |

**Motivo técnico:** no existe un “Baileys oficial” en Dart. La opción cercana es **Neonize** (documentado como inestable / no producción en pub.dev).

---

## Paso 1 — Crear paquete Dart consola

- Comando: `dart create -t console whatsapp_qr_pairing` dentro de `Dart/`.
- Resultado: `pubspec.yaml`, `bin/`, `lib/`, `test/`.

---

## Paso 2 — Dependencia Neonize

- Añadido `neonize: ^1.0.0` en `pubspec.yaml`.
- `dart pub get` descarga el **wrapper Dart**; la **librería nativa** (.dll / .so) es **obligatoria aparte** y se indica con **`NEONIZE_PATH`**.

---

## Paso 3 — Carga diferida (deferred import)

- **Problema:** al importar `neonize` de forma normal, `bindings.dart` ejecuta `DynamicLibrary.open` al cargar el módulo, **antes** de poder comprobar variables de entorno.
- **Solución:** `import '.../neonize_pairing.dart' deferred as pairing;` en `bin/whatsapp_qr_pairing.dart`, comprobar `NEONIZE_PATH` y existencia del archivo, luego `await pairing.loadLibrary()` y `pairing.runQrPairing(...)`.

---

## Paso 4 — Lógica de emparejamiento (`lib/neonize_pairing.dart`)

1. Crear `data/` y `data/temp/`.
2. Instanciar `NewAClient` con `databasePath` → `data/neonize.db`.
3. Registrar `client.qr` → imprime QR en terminal con `qrTerminal`.
4. Registrar `client.on<Connected>` → mensaje de éxito.
5. `client.connect()` → inicia el stack nativo.
6. Esperar Enter en stdin → `disconnect()` (cierre ordenado para pruebas).

Equivalente flujo Baileys: conectar → mostrar QR → evento “open” → mantener proceso vivo.

---

## Paso 5 — Ollama (instrucciones de entorno)

- **Ollama** no forma parte del binario Dart en esta fase; sirve para **modelos locales** (p. ej. asistente de código o RAG después).
- **Instalación local:** https://ollama.com — descargar el instalador para Windows / usar paquete en Linux.
- **Docker:** servicio `ollama` en `Dart/docker-compose.yml` (imagen `ollama/ollama`), puerto **11434**. El CLI Dart **no** llama a Ollama todavía; queda listo para integraciones futuras.

---

## Paso 6 — Dockerizar el CLI

- `Dockerfile` en `whatsapp_qr_pairing/`: compila con `dart compile exe`, imagen runtime Debian slim.
- La imagen **espera** que montes la librería nativa en la ruta definida por `NEONIZE_PATH` (no se redistribuye desde GitHub sin un asset estable en el momento de escribir esto).

---

## Paso 7 — Commits semánticos (inglés)

Convención usada en el repo:

- `feat(dart): …` — código o paquete nuevo.
- `docs(dart): …` — este markdown y READMEs.
- `chore(dart): …` — Docker, compose, gitignore de artefactos.

---

## Checklist para quien continúe mañana

- [ ] Obtener `.dll` / `.so` Neonize compatible y probar `dart run` con `NEONIZE_PATH`.
- [ ] Confirmar que el QR escanea y llega el evento `Connected`.
- [ ] Decidir si la agenda (`citas.json`) se reimplementa en Dart o se deja en Node/Meta.
- [ ] Si se usa Ollama: definir prompt/seguridad y **no** mezclar datos clínicos sin cumplimiento.

---

*Última actualización del documento: sesión de migración Dart / misión “QR + Docker + Ollama”.*
