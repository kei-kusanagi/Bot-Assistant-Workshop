# Demo: bot de WhatsApp (consultorio terapia simulado)

Sirve para **aprender** el flujo oficial de **WhatsApp Cloud API**: tu celular escribe al número de prueba de Meta y este servidor responde con un menú tipo consultorio (información + simulación de cita “por confirmar”).

No sustituye un producto en producción (tokens, verificación de negocio, plantillas, etc. van aparte).

**Tutorial paso a paso (Meta actual, ngrok, webhook, formato `521…` en México, fallos típicos):** [docs/tutorial.md](docs/tutorial.md). Puedes abrirlo en Obsidian u otro editor Markdown, crear la carpeta `docs/img/`, pegar ahí tus capturas y enlazarlas desde el tutorial con rutas como `![texto](img/archivo.png)`.

## Requisitos

- Cuenta de [Meta for Developers](https://developers.facebook.com/)
- **Node.js** 18+ (en tu máquina ya sirve v22)
- Un túnel **HTTPS** hacia tu PC para que Meta pueda llamar al webhook: [ngrok](https://ngrok.com/) o [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)

## Paso 1 — App y WhatsApp en Meta

1. Entra a [developers.facebook.com](https://developers.facebook.com/) → **Mis apps** → **Crear app** → tipo **Negocio**.
2. En el panel de la app, añade el producto **WhatsApp** (si no está, **Agregar producto**).
3. Ve a **WhatsApp** → **API de prueba** (o *Getting started*).
4. Anota:
   - **Token de acceso temporal** (caduca a las ~24 h; para seguir aprendiendo luego necesitarás un token de larga duración con usuario del sistema).
   - **ID del número de teléfono** (*Phone number ID*) — es un número largo, **no** es el teléfono con prefijo.

## Paso 2 — Tu número como destinatario de prueba

En la misma pantalla de API de prueba, en **“Número de teléfono del destinatario”** / *To*, **añade tu WhatsApp personal** (con código de país, ej. `521...` México). Sin esto, Meta no entregará mensajes a tu móvil en modo prueba.

## Paso 3 — Configurar este proyecto

Desde la raíz del repositorio, entra en la carpeta del demo (`node/whatsapp-bot-demo`):

```bash
cd node/whatsapp-bot-demo
npm install
copy .env.example .env
```

Edita `.env`:

- `WHATSAPP_TOKEN` = token de la consola de Meta.
- `WHATSAPP_PHONE_NUMBER_ID` = el Phone number ID.
- `WEBHOOK_VERIFY_TOKEN` = inventa una cadena secreta (ej. `mi_token_secreto_demo_123`). **La misma** la usarás en Meta.

Arranca el servidor:

```bash
npm start
```

Deberías ver: `Demo escuchando en http://localhost:3000`.

## Paso 4 — Túnel HTTPS

En otra terminal (ejemplo con ngrok):

```bash
ngrok http 3000
```

Copia la URL `https://....ngrok-free.app` (o la que te dé).

## Paso 5 — Webhook en Meta

1. En la app → **WhatsApp** → **Configuración** → sección **Webhook**.
2. **URL de devolución de llamada**: `https://TU_SUBDOMINIO.ngrok-free.app/webhook` (termina en `/webhook`).
3. **Token de verificación**: el mismo valor que `WEBHOOK_VERIFY_TOKEN` en tu `.env`.
4. Guarda y **Verificar y guardar**.
5. Suscríbete al campo **`messages`** (y si Meta lo pide, confirma la suscripción).

Si la verificación falla: mismo token en ambos lados, servidor arrancado, túnel activo, ruta exacta `/webhook`.

## Paso 6 — Probar en el móvil

1. En la consola de Meta, en la sección de prueba, usa **“Enviar mensaje de prueba”** o envía desde tu WhatsApp al **número de prueba** que muestra Meta (el que dice algo como “número de prueba de WhatsApp”).
2. Escribe `hola` o `0` y sigue el menú (1–4, luego flujo *2* → *a/b/c* → *1/2/3*).

## Qué hace el bot (lógica)

- Menú con precios ficticios, “ubicación”, contacto recepción.
- Flujo **2** simula elegir tipo de sesión y un hueco; deja la cita como **pendiente de confirmación** (alineado a la idea de negocio que documentaste).

Todo el estado va en **memoria** (`Map`): si reinicias el servidor, se pierde. Más adelante conectarías **Supabase** en lugar de eso.

## Problemas frecuentes

| Síntoma | Qué revisar |
|--------|----------------|
| Meta no verifica el webhook | Token idéntico, URL https, `/webhook`, servidor y ngrok arriba |
| No te llega nada al móvil | Tu número agregado como destinatario de prueba; escribes **al** número de prueba de Meta |
| Error 401 al enviar respuesta | Token caducado (vuelve a copiar uno nuevo en la consola) |
| ngrok “visit site” interstitial | En pruebas a veces molesta; en Cloudflare Tunnel suele ir más limpio |

## Siguientes pasos reales (fuera de esta demo)

- Token de **larga duración** y app en modo producción.
- **Verificación del negocio** en Meta para mensajes a clientes reales.
- **Plantillas** para recordatorios fuera de la ventana de conversación.
- Webhook con **validación de firma** `X-Hub-Signature-256` (aquí se omitió a propósito para simplificar el aprendizaje).

## OpenClaw

OpenClaw es otra forma de conectar IA a WhatsApp; **esta carpeta no lo usa**: aquí solo hay **Node + Express + API oficial**, para que veas el webhook “crudo” y puedas evolucionar a Supabase cuando quieras.
