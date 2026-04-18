# Dart (workshop)

## `whatsapp_qr_pairing`

CLI en Dart que reproduce **solo** la parte del prototipo Node/Baileys de **mostrar QR y emparejar** WhatsApp (multi-dispositivo), usando el paquete **neonize** (FFI + librería nativa).

```bash
cd whatsapp_qr_pairing
# Definir NEONIZE_PATH al .dll / .so de Neonize, luego:
dart run
```

- **Diario de pasos / equivalencias:** [docs/MIGRATION_FROM_NODE_BAILEYS.md](docs/MIGRATION_FROM_NODE_BAILEYS.md)
- **Detalle del paquete:** [whatsapp_qr_pairing/README.md](whatsapp_qr_pairing/README.md)
- **Docker + Ollama (servicio auxiliar):** [docker-compose.yml](docker-compose.yml)
