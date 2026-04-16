# Bot WhatsApp alternativo (Baileys + QR)

**Tutorial paso a paso (instalación, QR, `.env`, pruebas, fallos típicos):** [tutorial.md](tutorial.md)

Este prototipo levanta un bot de WhatsApp de forma distinta al de Meta Cloud API:

- **Sin webhook de Meta ni ngrok**.
- Conexion por **WhatsApp Web** usando QR (Baileys).
- Persistencia local de citas en `data/citas.json`.

> Uso recomendado: pruebas internas de flujo y producto.  
> Para produccion normalmente conviene API oficial (Meta o BSP) por cumplimiento y estabilidad.

## 1) Instalacion

```powershell
cd "c:\Users\admin\Desktop\Proyectos\Bot Assistant Workshop\node\whatsapp-bot-baileys"
npm install
copy .env.example .env
```

## 2) Configuracion opcional

Edita `.env`:

- `CLINIC_NAME`: nombre del consultorio.
- `DOCTOR_NUMBERS`: autorizados para comandos `doc …` (digitos `521…` o `lid:…` si tu chat usa JID `@lid`).
  - Ejemplo: `5215512345678,lid:89537468494034`

## 3) Ejecutar

```powershell
npm start
```

En primer inicio aparecera un QR en terminal:

1. Abre WhatsApp en el telefono.
2. Ve a **Dispositivos vinculados**.
3. Escanea el QR.

## 4) Flujo del paciente

- `hola` o `0`: menu principal.
- `1`: horarios disponibles.
- `2`: agendar cita (nombre -> servicio -> horario).
- `3`: ver mis citas.
- `4`: cancelar cita por ID.

## 5) Flujo de doctor/recepcion (si numero autorizado)

- `doc`: ver ayuda de comandos.
- `doc agenda hoy`
- `doc agenda manana`
- `doc pendientes`

## 6) Donde se guardan las citas

Se guardan en:

- `data/citas.json` (archivo local, facil de inspeccionar)

Esto permite hacer pruebas rapidas. Despues se puede migrar a Supabase sin cambiar la logica conversacional base.

## 7) Siguientes pasos sugeridos

1. Migrar `data/citas.json` a Supabase (`appointments`, `patients`, `providers`).
2. Agregar recordatorios por cron/job.
3. Agregar pagos (link de pago y webhook de confirmacion).
4. Definir despliegue:
   - local para desarrollo
   - Hetzner para ambiente continuo
