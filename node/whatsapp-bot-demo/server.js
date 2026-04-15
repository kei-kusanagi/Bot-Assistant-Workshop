import "dotenv/config";
import express from "express";

const {
  WHATSAPP_TOKEN,
  WHATSAPP_PHONE_NUMBER_ID,
  WEBHOOK_VERIFY_TOKEN: WEBHOOK_VERIFY_TOKEN_RAW,
  PORT = 3000,
} = process.env;

const WEBHOOK_VERIFY_TOKEN = (WEBHOOK_VERIFY_TOKEN_RAW ?? "").trim();

const GRAPH = "https://graph.facebook.com/v22.0";

/** @type {Map<string, { step: string, service?: string }>} */
const sessions = new Map();

function getSession(from) {
  if (!sessions.has(from)) {
    sessions.set(from, { step: "menu" });
  }
  return sessions.get(from);
}

function resetSession(from) {
  sessions.set(from, { step: "menu" });
}

function buildWelcome() {
  return (
    "Hola, bienvenido/a al *Consultorio Demo Terapia*.\n\n" +
    "Puedo orientarte con información básica y simular el agendado de una cita.\n\n" +
    "Escribe un número:\n" +
    "1) Ver tipos de sesión y precios orientativos\n" +
    "2) Simular agendar cita (elige servicio y día)\n" +
    "3) Ubicación y contacto\n" +
    "4) Hablar con recepción (simulado: te dejo el tel 55-0000-0000)\n" +
    "0) Volver al menú\n\n" +
    "_Aviso: esto es una demo; no sustituye valoración clínica._"
  );
}

function handleMenuChoice(from, text) {
  const t = text.trim();
  const s = getSession(from);
  if (t === "0" || /^menu$/i.test(t) || /^hola$/i.test(t)) {
    resetSession(from);
    return buildWelcome();
  }
  if (t === "1") {
    return (
      "*Tipos de sesión (demo)*\n\n" +
      "• Individual — 50 min — desde $800\n" +
      "• Pareja — 60 min — desde $1,200\n" +
      "• Familiar — 60 min — desde $1,400\n\n" +
      "Los precios son *orientativos* y pueden cambiar.\n\n" +
      "Escribe *2* para simular agendar, o *0* para el menú."
    );
  }
  if (t === "2") {
    s.step = "pick_service";
    return (
      "Simulación de *agenda*.\n\n" +
      "Elige servicio (número):\n" +
      "a) Individual\n" +
      "b) Pareja\n" +
      "c) Familiar\n\n" +
      "Responde con *a*, *b* o *c*. (0 = menú)"
    );
  }
  if (t === "3") {
    return (
      "*Ubicación (demo)*\n" +
      "Av. Ejemplo 123, Col. Demo, CDMX.\n" +
      "Metro más cercano: Línea X.\n\n" +
      "Escribe *0* para el menú."
    );
  }
  if (t === "4") {
    return (
      "Para esta demo, el contacto de recepción es: *55-0000-0000*.\n" +
      "Horario simulado: Lun–Vie 9:00–18:00.\n\n" +
      "*0* = menú."
    );
  }
  return "No reconocí la opción. Escribe *0* para ver el menú.";
}

function handleBooking(from, text) {
  const s = getSession(from);
  const t = text.trim().toLowerCase();
  if (t === "0") {
    resetSession(from);
    return buildWelcome();
  }
  if (s.step === "pick_service") {
    if (!["a", "b", "c"].includes(t)) {
      return "Elige *a*, *b* o *c* para el tipo de sesión. (0 = menú)";
    }
    const labels = { a: "Individual", b: "Pareja", c: "Familiar" };
    s.service = labels[t];
    s.step = "pick_day";
    return (
      `Servicio: *${s.service}*.\n\n` +
      "Elige día propuesto (número):\n" +
      "1) Mañana 10:00\n" +
      "2) Pasado mañana 16:00\n" +
      "3) Próximo lunes 11:30\n\n" +
      "Responde *1*, *2* o *3*. (0 = menú)"
    );
  }
  if (s.step === "pick_day") {
    const slots = {
      1: "Mañana 10:00",
      2: "Pasado mañana 16:00",
      3: "Próximo lunes 11:30",
    };
    if (!slots[t]) {
      return "Elige *1*, *2* o *3* para el horario. (0 = menú)";
    }
    const slot = slots[t];
    const svc = s.service || "Individual";
    resetSession(from);
    return (
      "Listo (simulación).\n\n" +
      `Te dejamos *pendiente de confirmación*:\n` +
      `• ${svc}\n` +
      `• ${slot}\n` +
      `• Consultorio Demo\n\n` +
      "En un producto real, recepción confirmaría la cita por política del negocio.\n\n" +
      "Escribe *0* para volver al menú."
    );
  }
  return buildWelcome();
}

function replyTextForMessage(from, body) {
  const raw = (body || "").trim();
  const s = getSession(from);
  if (!raw) {
    return buildWelcome();
  }
  if (s.step === "menu") {
    return handleMenuChoice(from, raw);
  }
  return handleBooking(from, raw);
}

async function sendWhatsAppText(to, body) {
  if (!WHATSAPP_TOKEN || !WHATSAPP_PHONE_NUMBER_ID) {
    console.error("[demo] Faltan WHATSAPP_TOKEN o WHATSAPP_PHONE_NUMBER_ID en .env");
    return;
  }
  const url = `${GRAPH}/${WHATSAPP_PHONE_NUMBER_ID}/messages`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${WHATSAPP_TOKEN}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      messaging_product: "whatsapp",
      to,
      type: "text",
      text: { preview_url: false, body },
    }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    console.error("[whatsapp] Error al enviar:", res.status, data);
  }
}

const app = express();

app.use(express.json());

app.get("/", (_req, res) => {
  res.type("html").send(
    "<p>Servidor del demo de WhatsApp activo. La ruta del webhook es <code>/webhook</code>.</p>"
  );
});

// Verificación del webhook (Meta llama GET con hub.*)
app.get("/webhook", (req, res) => {
  const mode = req.query["hub.mode"];
  const rawVerify = req.query["hub.verify_token"];
  const token = (Array.isArray(rawVerify) ? rawVerify[0] : rawVerify ?? "")
    .toString()
    .trim();
  const challenge = req.query["hub.challenge"];

  if (mode === "subscribe" && token && token === WEBHOOK_VERIFY_TOKEN) {
    console.log("[webhook] Verificación OK");
    return res.status(200).send(challenge);
  }
  console.warn("[webhook] Verificación fallida", {
    mode,
    hasEnvToken: Boolean(WEBHOOK_VERIFY_TOKEN),
    tokenMatch: token === WEBHOOK_VERIFY_TOKEN,
    envTokenLen: WEBHOOK_VERIFY_TOKEN.length,
    queryTokenLen: token.length,
  });
  return res.sendStatus(403);
});

app.post("/webhook", async (req, res) => {
  res.sendStatus(200);
  try {
    const body = req.body;
    const entries = body?.entry || [];
    for (const entry of entries) {
      const changes = entry?.changes || [];
      for (const change of changes) {
        const value = change?.value;
        const messages = value?.messages;
        if (!messages?.length) continue;
        for (const msg of messages) {
          if (msg.type !== "text") {
            const from = msg.from;
            await sendWhatsAppText(
              from,
              "Por ahora solo entiendo mensajes de *texto*. Escribe *0* para el menú."
            );
            continue;
          }
          const from = msg.from;
          const text = msg.text?.body || "";
          console.log("[msg]", from, JSON.stringify(text));
          const answer = replyTextForMessage(from, text);
          await sendWhatsAppText(from, answer);
        }
      }
    }
  } catch (e) {
    console.error("[webhook]", e);
  }
});

app.listen(PORT, () => {
  console.log(`Demo escuchando en http://localhost:${PORT}`);
  console.log(`Webhook (para Meta): https://TU_TUNEL.ngrok-free.app/webhook`);
  if (!WHATSAPP_TOKEN || !WHATSAPP_PHONE_NUMBER_ID) {
    console.warn("Configura .env (copia desde .env.example)");
  }
});
