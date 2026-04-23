# whatsapp_wa_drago

**Misma meta (WhatsApp en Dart), otra pila:** no usa Neonize/FFI ni whatsmeow. Usa **[drago_whatsapp_flutter](https://pub.dev/packages/drago_whatsapp_flutter)** (WPPConnect / wa-js dentro de un WebView), lo mas parecido a abrir WhatsApp Web en un Chrome embebido.

## Requisitos

- Flutter (mismo SDK que ya usas).
- En **Windows**:
  - **NuGet CLI** en el `PATH` (obligatorio para compilar `flutter_inappwebview_windows`). Si el build dice `NUGET-NOTFOUND` o *Nuget is not installed*:
    - `winget install --id Microsoft.NuGet -e`  
      o descarga [nuget.exe](https://dist.nuget.org/win-x86-commandline/latest/nuget.exe), colócala en una carpeta (p. ej. `C:\Tools`) y añade esa carpeta al **PATH**; **cierra y abre** la terminal y comprueba con `nuget`.
  - [WebView2](https://developer.microsoft.com/microsoft-edge/webview2/) runtime (suele venir con Edge).

## Ejecutar

```powershell
cd "ruta\al\repo\Flutter\whatsapp_wa_drago"
flutter pub get
flutter run -d windows
```

Pulsa **Conectar (QR)**; cuando salga la imagen, escanea desde el movil (**Ajustes > Dispositivos vinculados**).

## Por que esta ruta si Neonize da `Login event: timeout`

El timeout de whatsmeow suele indicar **corte de socket** o **sin evento `code`** antes de tiempo. Eso depende de red, IP, version del binario Go, etc. Drago evita esa capa: inyecta JS en la **misma** experiencia que el navegador.

## Neonize (CLI) — depuracion extra

Si sigues probando `Dart/whatsapp_qr_pairing`, en PowerShell:

```powershell
$env:NEONIZE_LOG_LEVEL = "DEBUG"
$env:NEONIZE_PATH = (Join-Path $PWD "neonize-windows-amd64.dll")
dart run
```

Asi el motor nativo imprime mas detalle sobre desconexion/emparejamiento.
