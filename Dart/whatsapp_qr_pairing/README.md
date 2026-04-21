# whatsapp_qr_pairing

Dart CLI: **QR + emparejamiento WhatsApp** (misma intención que `node/whatsapp-bot-baileys`, distinta implementación).

## Requisitos

- Dart SDK **^3.11** (o el rango del `pubspec.yaml`).
- Librería nativa **Neonize** para tu SO (`.dll` Windows, `.so` Linux, `.dylib` macOS) y variable **`NEONIZE_PATH`** con la ruta absoluta al archivo.

Ver pasos y contexto en [../docs/MIGRATION_FROM_NODE_BAILEYS.md](../docs/MIGRATION_FROM_NODE_BAILEYS.md).

## Ejecutar (local)

**Si guardaste `neonize-windows-amd64.dll` en esta misma carpeta** (recomendado para pruebas):

```powershell
cd "ruta\al\repo\Dart\whatsapp_qr_pairing"
$env:NEONIZE_PATH = (Join-Path $PWD "neonize-windows-amd64.dll")
dart run
```

**Si el `.dll` está en otra carpeta**, usa la ruta absoluta:

```powershell
$env:NEONIZE_PATH="C:\ruta\completa\neonize-windows-amd64.dll"
dart run
```

Escanea el QR en WhatsApp → **Dispositivos vinculados**. Tras conectar, pulsa **Enter** en la terminal para desconectar.

## Datos locales

- `data/neonize.db` — sesión (sensible, no subir a repositorios públicos).
- `data/temp/` — temporales del cliente.

## Docker

Desde `Dart/whatsapp_qr_pairing/`:

```bash
docker build -t whatsapp-qr-dart .
```

Monta el binario nativo y define `NEONIZE_PATH` en runtime (por ejemplo con volumen en `docker-compose.yml` del directorio padre).

## Estado del paquete `neonize`

Pub.dev indica desarrollo activo y **no listo para producción**. Úsalo como laboratorio alineado a la misión del jefe (traducción de flujo + Docker + Ollama preparado).
