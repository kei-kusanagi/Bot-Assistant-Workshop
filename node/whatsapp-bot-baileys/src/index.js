import "dotenv/config";
import path from "node:path";
import { promises as fs } from "node:fs";
import { fileURLToPath } from "node:url";
import qrcode from "qrcode-terminal";
import pino from "pino";
import makeWASocket, {
  DisconnectReason,
  fetchLatestBaileysVersion,
  useMultiFileAuthState,
} from "@whiskeysockets/baileys";

const baileysLogger = pino({
  level: process.env.BAILEYS_LOG_LEVEL ?? "warn",
});

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT_DIR = path.resolve(__dirname, "..");
const AUTH_DIR = path.join(ROOT_DIR, ".auth");
const DATA_DIR = path.join(ROOT_DIR, "data");
const DB_FILE = path.join(DATA_DIR, "citas.json");

/** Texto fijo en citas.json (campo _meta): qué es el archivo y qué no contiene. */
const DB_META = {
  descripcion:
    "Agenda local de pruebas del bot Baileys. No sustituye historial clínico ni sistema de producción.",
  que_se_guarda_aqui: [
    "Citas: nombre indicado por el usuario, id de chat WhatsApp (numero normalizado o lid:...), servicio, horario ISO, estado.",
  ],
  que_no_va_en_este_archivo: [
    "Credenciales de WhatsApp, claves de sesión Baileys ni QR: eso está en la carpeta .auth/ (no subir a git).",
    "Contenido de chats completos, multimedia ni contactos: el demo solo persiste lo necesario para la agenda.",
  ],
  sensibilidad:
    "Los datos de agenda pueden ser personales; protege el archivo y no lo compartas públicamente.",
  rutaRelativa: "data/citas.json",
};

const CLINIC_NAME = process.env.CLINIC_NAME || "Consultorio Demo Citas";
const DOCTOR_NUMBERS = new Set(
  (process.env.DOCTOR_NUMBERS || "")
    .split(",")
    .map((item) => {
      const t = (item || "").trim();
      if (t.toLowerCase().startsWith("lid:")) return t.toLowerCase();
      return normalizePhone(t);
    })
    .filter(Boolean)
);

/** @type {Map<string, { step: string, draft?: Record<string, string> }>} */
const sessions = new Map();

const BASE_SLOTS = [
  "2026-04-16T10:00:00",
  "2026-04-16T12:00:00",
  "2026-04-16T17:00:00",
  "2026-04-17T09:30:00",
  "2026-04-17T16:00:00",
  "2026-04-18T11:00:00",
];

const SERVICES = {
  1: "Limpieza dental",
  2: "Revision general",
  3: "Ortodoncia (valoracion)",
};

async function ensureStorage() {
  await fs.mkdir(DATA_DIR, { recursive: true });
  try {
    await fs.access(DB_FILE);
  } catch {
    await writeDB({ appointments: [] });
  }
}

async function readDB() {
  const raw = await fs.readFile(DB_FILE, "utf-8");
  const data = JSON.parse(raw);
  if (!data._meta) {
    data._meta = { ...DB_META, nota: "Meta añadida automaticamente al leer (archivo anterior sin _meta)." };
    await writeDB(data);
  }
  return data;
}

async function writeDB(data) {
  const out = {
    _meta: data._meta ?? DB_META,
    appointments: Array.isArray(data.appointments) ? data.appointments : [],
  };
  await fs.writeFile(DB_FILE, JSON.stringify(out, null, 2), "utf-8");
}

function normalizePhone(input) {
  return (input || "").toString().replace(/\D/g, "");
}

/** Identificador estable por chat (PN o LID). WhatsApp a veces usa `@lid` en lugar del número. */
function chatIdentity(remoteJid) {
  if (!remoteJid) return "";
  const local = remoteJid.split("@")[0];
  if (remoteJid.endsWith("@s.whatsapp.net")) {
    return normalizePhone(local);
  }
  if (remoteJid.endsWith("@lid")) {
    return `lid:${local}`;
  }
  return remoteJid;
}

function isDirectUserChat(remoteJid) {
  if (!remoteJid) return false;
  if (remoteJid.endsWith("@g.us")) return false;
  if (remoteJid.includes("broadcast")) return false;
  return (
    remoteJid.endsWith("@s.whatsapp.net") || remoteJid.endsWith("@lid")
  );
}

function formatSlot(iso) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString("es-MX", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: process.env.TIMEZONE || "America/Mexico_City",
  });
}

function getSession(chatId) {
  if (!sessions.has(chatId)) {
    sessions.set(chatId, { step: "menu", draft: {} });
  }
  return sessions.get(chatId);
}

function resetSession(chatId) {
  sessions.set(chatId, { step: "menu", draft: {} });
}

function buildMainMenu() {
  return (
    `Hola, soy el bot de *${CLINIC_NAME}*.\n\n` +
    "Que deseas hacer?\n" +
    "1) Ver horarios disponibles\n" +
    "2) Agendar cita\n" +
    "3) Ver mis citas\n" +
    "4) Cancelar una cita\n" +
    "0) Menu principal\n\n" +
    "_Demo local: las citas se guardan en archivo JSON._"
  );
}

async function getAvailableSlots() {
  const db = await readDB();
  const booked = new Set(
    db.appointments.filter((a) => a.status === "booked").map((a) => a.slot)
  );
  return BASE_SLOTS.filter((slot) => !booked.has(slot));
}

function parseTextMessage(msg) {
  const text =
    msg.message?.conversation ||
    msg.message?.extendedTextMessage?.text ||
    msg.message?.imageMessage?.caption ||
    "";
  return (text || "").trim();
}

function isDoctor(chatId) {
  return DOCTOR_NUMBERS.has(chatId);
}

function buildDoctorHelp() {
  return (
    "Comandos de doctor:\n" +
    "- *doc agenda hoy*\n" +
    "- *doc agenda manana*\n" +
    "- *doc pendientes*"
  );
}

function nextAppointmentId(appointments) {
  const values = appointments
    .map((a) => Number(a.id))
    .filter((value) => Number.isFinite(value));
  return String(values.length ? Math.max(...values) + 1 : 1);
}

async function handleDoctorCommand(chatId, text) {
  const lower = text.toLowerCase();
  if (!isDoctor(chatId)) return null;

  if (!lower.startsWith("doc")) {
    return null;
  }

  const db = await readDB();
  if (lower === "doc pendientes") {
    const pending = db.appointments.filter((a) => a.status === "booked");
    if (!pending.length) return "No hay citas activas.";
    const lines = pending
      .slice(0, 20)
      .map(
        (a) =>
          `#${a.id} - ${a.patientName} - ${formatSlot(a.slot)} - ${a.service} - ${a.patientPhone}`
      );
    return `Citas activas (${pending.length}):\n${lines.join("\n")}`;
  }

  const now = new Date();
  const targetDay = lower.includes("manana")
    ? new Date(now.getTime() + 24 * 60 * 60 * 1000)
    : now;
  const dayStart = new Date(targetDay);
  dayStart.setHours(0, 0, 0, 0);
  const dayEnd = new Date(targetDay);
  dayEnd.setHours(23, 59, 59, 999);

  const list = db.appointments
    .filter((a) => {
      if (a.status !== "booked") return false;
      const dt = new Date(a.slot);
      return dt >= dayStart && dt <= dayEnd;
    })
    .sort((a, b) => a.slot.localeCompare(b.slot));

  const title = lower.includes("manana")
    ? "Agenda de manana"
    : "Agenda de hoy";

  if (!list.length) return `${title}: sin citas.`;
  return `${title}:\n${list
    .map((a) => `#${a.id} ${formatSlot(a.slot)} - ${a.patientName} (${a.service})`)
    .join("\n")}`;
}

async function handleMenu(chatId, text) {
  const s = getSession(chatId);
  if (!text || text === "0" || /^hola$/i.test(text) || /^menu$/i.test(text)) {
    resetSession(chatId);
    return buildMainMenu();
  }

  if (text === "1") {
    const slots = await getAvailableSlots();
    if (!slots.length) return "No hay horarios disponibles por ahora.";
    return `Horarios disponibles:\n${slots
      .slice(0, 10)
      .map((slot, idx) => `${idx + 1}) ${formatSlot(slot)}`)
      .join("\n")}\n\nEscribe *2* para agendar.`;
  }

  if (text === "2") {
    s.step = "ask_name";
    s.draft = {};
    return "Perfecto. Cual es tu nombre completo?";
  }

  if (text === "3") {
    const db = await readDB();
    const mine = db.appointments
      .filter((a) => a.patientPhone === chatId && a.status === "booked")
      .sort((a, b) => a.slot.localeCompare(b.slot));
    if (!mine.length) return "No tienes citas activas.";
    return `Tus citas:\n${mine
      .map((a) => `#${a.id} - ${formatSlot(a.slot)} - ${a.service}`)
      .join("\n")}`;
  }

  if (text === "4") {
    const db = await readDB();
    const mine = db.appointments.filter(
      (a) => a.patientPhone === chatId && a.status === "booked"
    );
    if (!mine.length) return "No tienes citas que cancelar.";
    s.step = "cancel_pick_id";
    return `Escribe el ID de la cita a cancelar:\n${mine
      .map((a) => `#${a.id} - ${formatSlot(a.slot)} - ${a.service}`)
      .join("\n")}`;
  }

  return "No entendi la opcion. Escribe *0* para ver el menu.";
}

async function handleFlow(chatId, text) {
  const s = getSession(chatId);
  const t = (text || "").trim();
  if (t === "0") {
    resetSession(chatId);
    return buildMainMenu();
  }

  if (s.step === "ask_name") {
    if (t.length < 3) return "Escribe un nombre valido (minimo 3 caracteres).";
    s.draft.patientName = t;
    s.step = "ask_service";
    return (
      "Elige servicio:\n" +
      "1) Limpieza dental\n" +
      "2) Revision general\n" +
      "3) Ortodoncia (valoracion)"
    );
  }

  if (s.step === "ask_service") {
    if (!SERVICES[t]) return "Selecciona 1, 2 o 3 para el servicio.";
    s.draft.service = SERVICES[t];
    const slots = await getAvailableSlots();
    if (!slots.length) {
      resetSession(chatId);
      return "No hay horarios libres por ahora. Intenta mas tarde.";
    }
    s.draft.available = slots.slice(0, 5);
    s.step = "ask_slot";
    return `Horarios disponibles:\n${s.draft.available
      .map((slot, idx) => `${idx + 1}) ${formatSlot(slot)}`)
      .join("\n")}\n\nResponde con el numero del horario.`;
  }

  if (s.step === "ask_slot") {
    const idx = Number(t) - 1;
    const slot = s.draft.available?.[idx];
    if (!slot) return "Selecciona un horario valido de la lista.";

    const db = await readDB();
    const alreadyBooked = db.appointments.some(
      (a) => a.slot === slot && a.status === "booked"
    );
    if (alreadyBooked) {
      resetSession(chatId);
      return "Ese horario se aparto hace un momento. Escribe *2* para intentar otro.";
    }

    const item = {
      id: nextAppointmentId(db.appointments),
      patientPhone: chatId,
      patientName: s.draft.patientName,
      service: s.draft.service,
      slot,
      status: "booked",
      createdAt: new Date().toISOString(),
    };
    db.appointments.push(item);
    await writeDB(db);
    resetSession(chatId);
    return (
      "Tu cita quedo registrada:\n" +
      `#${item.id} - ${item.service}\n` +
      `${formatSlot(item.slot)}\n\n` +
      "Escribe *3* para ver tus citas."
    );
  }

  if (s.step === "cancel_pick_id") {
    const id = t.replace("#", "");
    const db = await readDB();
    const appointment = db.appointments.find(
      (a) => a.id === id && a.patientPhone === chatId && a.status === "booked"
    );
    if (!appointment) return "No encontre una cita activa con ese ID.";
    appointment.status = "cancelled";
    appointment.cancelledAt = new Date().toISOString();
    await writeDB(db);
    resetSession(chatId);
    return `Listo. La cita #${id} fue cancelada.`;
  }

  resetSession(chatId);
  return buildMainMenu();
}

async function replyFor(chatId, text) {
  const doctorReply = await handleDoctorCommand(chatId, text);
  if (doctorReply) return doctorReply;
  if (isDoctor(chatId) && /^doc$/i.test(text.trim())) {
    return buildDoctorHelp();
  }
  const s = getSession(chatId);
  if (s.step === "menu") return handleMenu(chatId, text);
  return handleFlow(chatId, text);
}

async function start() {
  await ensureStorage();
  await fs.mkdir(AUTH_DIR, { recursive: true });
  const { state, saveCreds } = await useMultiFileAuthState(AUTH_DIR);
  const { version } = await fetchLatestBaileysVersion();

  const sock = makeWASocket({
    version,
    auth: state,
    printQRInTerminal: false,
    syncFullHistory: false,
    logger: baileysLogger,
  });

  sock.ev.on("creds.update", saveCreds);
  sock.ev.on("connection.update", (update) => {
    if (update.qr) {
      console.log("Escanea este QR con WhatsApp:");
      qrcode.generate(update.qr, { small: true });
    }
    if (update.connection === "open") {
      console.log("Bot conectado a WhatsApp Web.");
    }
    if (update.connection === "close") {
      const shouldReconnect =
        update.lastDisconnect?.error?.output?.statusCode !==
        DisconnectReason.loggedOut;
      console.log("Conexion cerrada.", { shouldReconnect });
      if (shouldReconnect) {
        start().catch((err) => {
          console.error("Error al reconectar:", err);
        });
      }
    }
  });

  sock.ev.on("messages.upsert", async ({ messages, type }) => {
    if (type !== "notify") return;
    for (const msg of messages) {
      if (!msg.message || msg.key.fromMe) continue;
      const remoteJid = msg.key.remoteJid;
      if (!remoteJid || !isDirectUserChat(remoteJid)) continue;
      const chatId = chatIdentity(remoteJid);
      if (!chatId) continue;
      const incoming = parseTextMessage(msg);
      if (!incoming) continue;
      if (process.env.DEBUG_MESSAGES === "1") {
        console.log("[msg]", remoteJid, "chatId=", chatId, incoming.slice(0, 100));
      }

      try {
        const reply = await replyFor(chatId, incoming);
        await sock.sendMessage(remoteJid, { text: reply });
      } catch (err) {
        console.error("Error procesando mensaje:", err);
        await sock.sendMessage(remoteJid, {
          text: "Tuvimos un error temporal. Intenta de nuevo en un momento.",
        });
      }
    }
  });

  console.log(`Bot local listo: ${CLINIC_NAME}`);
  console.log("Si es primer inicio, aparecera QR en esta terminal.");
  console.log(
    "Para comandos internos de doctor, configura DOCTOR_NUMBERS en .env.example/.env"
  );
}

start().catch((err) => {
  console.error("No se pudo iniciar el bot:", err);
  process.exit(1);
});
