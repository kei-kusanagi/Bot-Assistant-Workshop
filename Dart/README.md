# Dart (workshop)

## `whatsapp_qr_pairing`

CLI en Dart que reproduce **solo** la parte del prototipo Node/Baileys de **mostrar QR y emparejar** WhatsApp (multi-dispositivo), usando el paquete **neonize** (FFI + librería nativa).

**Windows (DLL en la misma carpeta que `pubspec.yaml`, como en tu setup):**

```powershell
cd whatsapp_qr_pairing
$env:NEONIZE_PATH = (Join-Path $PWD "neonize-windows-amd64.dll")
dart run
```

**Otro SO o ruta distinta:** define `NEONIZE_PATH` con la ruta **absoluta** al `.dll` / `.so` / `.dylib` descargado desde [Neonize releases](https://github.com/krypton-byte/neonize/releases/) (asset correcto, **no** el `.whl` de Python).

- **Diario de pasos / equivalencias:** [docs/MIGRATION_FROM_NODE_BAILEYS.md](docs/MIGRATION_FROM_NODE_BAILEYS.md)
- **Convención de commits (inglés):** [docs/SEMANTIC_COMMITS.md](docs/SEMANTIC_COMMITS.md)
- **Detalle del paquete:** [whatsapp_qr_pairing/README.md](whatsapp_qr_pairing/README.md)
- **Docker + Ollama (servicio auxiliar):** [docker-compose.yml](docker-compose.yml)
