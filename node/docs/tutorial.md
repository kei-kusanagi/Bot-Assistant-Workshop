# Tutorial: bot de WhatsApp (demo en local)

Esta guía amplía el [README del proyecto](../README.md) con un recorrido **paso a paso**, alineado a la interfaz actual de **Meta for Developers** y a los problemas habituales en local (webhook, ngrok, números en México).

**Qué lograrás:** tu celular escribe al **número de prueba** de WhatsApp Cloud API y un servidor **Node + Express** en tu PC responde con el menú del demo (`whatsapp-bot-demo`).

---

## Requisitos

- Cuenta en [Meta for Developers](https://developers.facebook.com/)
- **Node.js** 18 o superior
- Editor de texto y terminal
- **Ngrok** (u otro túnel HTTPS, p. ej. Cloudflare Tunnel) y cuenta gratuita en ngrok

---

## Paso 0 — Cómo encajan las piezas

1. **Meta:** app con producto/caso de uso **WhatsApp**, token de acceso, **Phone number ID**, lista de **números permitidos** en modo prueba y **webhook** apuntando a una URL **HTTPS** pública.
2. **Tu PC:** carpeta `node/whatsapp-bot-demo`, variables en `.env`, comando `npm start` → el servidor escucha en `http://localhost:PORT` (por defecto **3000**) y expone **`/webhook`**.
3. **Túnel (ngrok):** Meta no puede llamar a `localhost`. Ngrok te da una URL `https://…` que **reenvía** el tráfico a tu puerto local.

Flujo resumido: escribes al número de prueba → Meta envía un **POST** a tu `https://…/webhook` → tu código procesa y **responde** por la API de Graph usando el token y el Phone number ID.

---

## Paso 1 — Crear la app y el caso de uso WhatsApp en Meta

1. Entra a [developers.facebook.com](https://developers.facebook.com/) → **Mis apps** → **Crear app**.

![[Pasted image 20260414192711.png]]

2. En **“Agregar casos de uso”**, en el filtro lateral elige **“Mensajes comerciales”** y marca **“Conectarte con los clientes a través de WhatsApp”**. No elijas Messenger u Instagram para este tutorial.

![[Pasted image 20260414192918.png]]

2. Sigue el asistente. En **Negocio**, si dice que no hay portfolio comercial, usa **“crea uno nuevo”**, rellena nombre y contacto, y crea el portfolio.
3. Si aparece verificación del negocio, para esta demo puedes pulsar **“Verificar más tarde”**.
4. En **Requisitos**, si dice que no hay requisitos identificados, es normal; continúa hasta el **resumen** y crea la app.
5. En el **panel** de la app puede salir un modal de bienvenida (“Hacer el recorrido”): puedes cerrarlo con la **X** para ir más directo.

**Nota sobre el menú:** en apps nuevas a veces **no** aparece el botón clásico **“Agregar producto”**. Si ya elegiste el caso de uso WhatsApp al crear la app, entra por **“Personalizar el caso de uso … WhatsApp”** (flecha en el panel) o por **Casos de uso** en el menú lateral.

---

## Paso 2 — Inicio rápido y “Configuración de la API”

1. Menú lateral: **Conectar en WhatsApp** → **Inicio rápido** (si existe).
2. Pulsa **“Empezar a usar la API”** (o equivalente) hasta llegar a **Configuración de la API** (`API Setup` / *Getting started*).
3. En esa pantalla tendrás, entre otras cosas:
   - **Generar token de acceso** (a veces abre OAuth: elige la cuenta de prueba **Test WhatsApp Business Account**, **Continuar** → **Guardar** → **De acuerdo**).
   - **Identificador de número de teléfono** (*Phone number ID*): número largo; **no** es el `+1 555…` del desplegable “De”.
   - **De / Para:** número de prueba desde el que “habla” Meta y destinatario(s) de prueba.

![[Pasted image 20260414193311.png]]

Anota **token** y **Phone number ID** en un lugar seguro (no los subas a repositorios ni los pegues en chats públicos).

---

## Paso 3 — Lista “Para (To)” y formato del número (México)

En **Paso 1** de “Enviar y recibir mensajes”, el campo **“Para (To)”** define qué números pueden recibir mensajes del **número de prueba** en modo sandbox (suele haber un máximo, p. ej. 5).

- Debes **añadir tu WhatsApp personal** y **seleccionarlo** en el desplegable.

![[Pasted image 20260414193518.png]]

- **México (móvil):** en la API el identificador suele ir como **`521` + 10 dígitos** (el **`1`** va **después de `52`**, no “al final” del número). Si en Meta solo registras **`52` + 10 dígitos** sin ese **`1`**, puede no coincidir con el `from` que envía el webhook y obtendrás error al responder (véase *Problemas frecuentes*).
- 
![[Pasted image 20260414193634.png]]

- Si tienes dos entradas en la lista (`+52 55…` y `+52 1 55…`), deja la que coincida con lo que ves en los logs del servidor junto a `[msg]` (solo dígitos, sin `+`).


---

## Paso 4 — Archivo `.env` en tu PC

Ruta del demo: `node/whatsapp-bot-demo/`.

1. Copia el ejemplo: en PowerShell, desde esa carpeta:  
   `copy .env.example .env`
2. Edita `.env`:
   - **`WHATSAPP_TOKEN`** = token de acceso de Meta.
   - **`WHATSAPP_PHONE_NUMBER_ID`** = el *Phone number ID* (no el `+1 555…` del “De”).
   - **`WEBHOOK_VERIFY_TOKEN`** = una cadena secreta inventada por ti; **la misma** irá en el panel de Meta al configurar el webhook.
   - **`PORT`** = `3000` si no cambias nada.

Guarda el archivo. Si lo editas después, **reinicia** `npm start` para que Node vuelva a leer las variables.

---

## Paso 5 — Servidor local

```powershell
cd "ruta\al\repo\node\whatsapp-bot-demo"
npm install
npm start
```

Deberías ver: `Demo escuchando en http://localhost:3000`. **Deja esta terminal abierta.**

![[Pasted image 20260414193802.png]]

---

## Paso 6 — Ngrok (qué hace y por qué hace falta)

Meta necesita una URL **HTTPS** en internet. Tu app está en **localhost**; **ngrok** abre un túnel y te da algo como `https://TU_SUBDOMINIO.ngrok-free.app` → `http://localhost:3000`.

1. Crea cuenta en ngrok si te lo pide y configura el **authtoken** según su documentación.
2. En **otra** terminal:  
   `ngrok http 3000`
3. Copia la URL **https** que muestre **Forwarding** (no cierres ngrok mientras pruebas).

![[Pasted image 20260414194522.png]]

**Plan gratuito / “trial”:** es habitual; la URL **cambia** al reiniciar ngrok. Si cambia, debes **actualizar la URL del webhook en Meta** (misma ruta `/webhook`).

![[Pasted image 20260414193959.png]]
---

## Paso 7 — Webhook en Meta

1. En la app: **Conectar en WhatsApp** → **Configuración** (o la sección de **Webhook**).

![[Pasted image 20260414194145.png]]

2. **URL de devolución de llamada:**  
   `https://TU_SUBDOMINIO.ngrok-free.app/webhook`  
   (sustituye por tu URL; debe terminar en **`/webhook`**.)
3. **Token de verificación:** exactamente igual a **`WEBHOOK_VERIFY_TOKEN`** en `.env`.
4. **“Adjunta un certificado de cliente…”:** déjalo **apagado** para este demo.

![[Pasted image 20260414194232.png]]

2. **Verificar y guardar** con `npm start` y ngrok **en ejecución**.

Luego, en **Campos del webhook**, suscríbete al campo **`messages`**. Para este proyecto **no hace falta** activar el resto de campos.

![[Pasted image 20260414194318.png]]

---

## Paso 8 — Probar en el móvil

1. Con `npm start` y ngrok activos, webhook verificado y **`messages`** suscrito.
2. En WhatsApp, abre chat con el **número de prueba** que muestra Meta (p. ej. `+1 555…`).
3. Escribe **`hola`** o **`0`**. Deberías recibir el menú del *Consultorio Demo Terapia*.

Si el webhook recibe pero la respuesta falla, revisa la sección de error **131030** más abajo.

![[Pasted image 20260414191739.png]]

---

## Qué función tiene ngrok (resumen)

Sin ngrok (o sin otro túnel / servidor público), Meta **no puede** llegar a `http://localhost:3000/webhook`. Ngrok **publica temporalmente** tu PC para desarrollo. En **producción** suele usarse un servidor con HTTPS propio y ahí ngrok ya no es necesario.

---

## Problemas frecuentes

### Meta: “No se pudo validar la URL…” y en ngrok `GET /webhook 403`

El demo responde **403** si el **token de verificación** no coincide con `WEBHOOK_VERIFY_TOKEN` del `.env` (espacios, trocitos distintos, o no reiniciaste el servidor tras cambiar `.env`). Unifica el texto en Meta y en `.env`, reinicia `npm start` y vuelve a **Verificar y guardar**.

### Error al enviar respuesta: `(#131030) Recipient phone number not in allowed list`

Tu número **no está** en la lista de destinatarios permitidos del modo prueba, o está en **formato distinto** al que Meta usa en el mensaje entrante. Corrige la entrada en **“Para (To)”** (en México suele hacer falta la variante **`521…`**). Vuelve a enviar `hola` tras guardar.

### No llega nada al móvil

Comprueba que escribes **al número de prueba** de Meta y que tu número está en **Para** y en la lista permitida.

### Token caducado (401 u otros errores al enviar)

Los tokens temporales caducan (aprox. 24 h). Genera uno nuevo en la consola y actualiza `WHATSAPP_TOKEN` en `.env`.

### Seguridad

- No subas **`.env`** a git (el demo ya lo ignora en `.gitignore`).
- Si un token de acceso se expuso, **revócalo o genera otro** en Meta y actualiza `.env`.

---

## Referencia rápida de rutas en el repo

| Elemento        | Ubicación                          |
|-----------------|------------------------------------|
| Código del bot  | `node/whatsapp-bot-demo/server.js` |
| Variables       | `node/whatsapp-bot-demo/.env`      |
| Resumen oficial | `node/README.md`                   |

---
