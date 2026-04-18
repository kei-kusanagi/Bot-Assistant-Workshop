# Migración conceptual: Node (Baileys) → Dart (Neonize) — solo QR + emparejamiento

Este documento es el **diario de pasos** que pidió el equipo: qué equivalencias hay, qué se hizo en el repo y qué falta para producción.

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
