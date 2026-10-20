// Supabase Edge Function: avisos automáticos de reservas.
//
// Se dispara con un Database Webhook de la tabla `reservas` (INSERT y UPDATE):
//   • reserva nueva   → correo de confirmación a la clienta + WhatsApp a María
//   • hora movida     → correo a la clienta con el nuevo día y bloque
//   • hora cancelada  → correo a la clienta
//
// Secrets (Supabase → Edge Functions → Secrets):
//   BREVO_API_KEY      correo con Brevo (gratis, 300 al día, no necesita dominio propio)
//   RESEND_API_KEY     alternativa a Brevo (necesita un dominio verificado)
//   EMAIL_FROM         remitente verificado, por ejemplo monsenails.studio@gmail.com
//   CALLMEBOT_APIKEY   WhatsApp a María con CallMeBot (gratis)
//   MARIA_WHATSAPP     opcional, por defecto +56926108745
// SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY ya vienen incluidas en Supabase.

import { createClient } from "jsr:@supabase/supabase-js@2";

const STUDIO = {
  nombre: "Monse Nails Studio",
  direccion: "Carlos Canut de Bon 2879",
  whatsapp: "+56 9 2610 8745",
};

const env = (k: string) => Deno.env.get(k) ?? "";
const sb = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"));

type Reserva = { id: string; servicio_id: string; clienta_id: string; fecha: string; hora: number; estado: string; precio: number; gratis: boolean };
type Clienta = { nombre: string; apellido: string; correo: string; telefono: string };

const MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];
const DIAS = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"];
const pad = (n: number) => String(n).padStart(2, "0");
const clp = (n: number) => "$" + Math.round(n).toLocaleString("es-CL");
let duracion = 2; // horas por bloque, se lee de la tabla ajustes
const bloque = (h: number) => `${pad(h)}:00 – ${pad(h + duracion)}:00`;
const fechaLarga = (s: string) => {
  const [y, m, d] = s.split("-").map(Number);
  return `${DIAS[new Date(Date.UTC(y, m - 1, d)).getUTCDay()]} ${d} de ${MESES[m - 1]}`;
};
const esc = (s: string) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

Deno.serve(async (req) => {
  const { type, record, old_record } = await req.json() as { type: string; record: Reserva; old_record?: Reserva };
  if (!record?.id) return Response.json({ ok: false, error: "sin reserva" }, { status: 400 });

  const [{ data: servicio }, { data: clienta }, { data: ajustes }] = await Promise.all([
    sb.from("servicios").select("nombre").eq("id", record.servicio_id).single(),
    sb.from("clientas").select("nombre, apellido, correo, telefono").eq("id", record.clienta_id).single(),
    sb.from("ajustes").select("duracion").eq("id", 1).maybeSingle(),
  ]);
  duracion = ajustes?.duracion ?? 2;
  if (!clienta) return Response.json({ ok: false, error: "clienta no encontrada" }, { status: 404 });
  const s = servicio?.nombre ?? "Servicio";
  const c = clienta as Clienta;

  const tareas: Promise<unknown>[] = [];
  if (type === "INSERT") {
    tareas.push(enviarCorreo(c, `Tu hora en ${STUDIO.nombre} está confirmada`, plantilla(c, "¡Tu hora está reservada!", record, s,
      record.gratis ? "Este es tu sexto servicio, así que va por cuenta de la casa." : "")));
    tareas.push(whatsappMaria(
      `Nueva reserva en ${STUDIO.nombre}\n` +
      `• ${s} (${record.gratis ? "GRATIS por fidelidad" : clp(record.precio)})\n` +
      `• ${fechaLarga(record.fecha)}, ${bloque(record.hora)}\n` +
      `• ${c.nombre} ${c.apellido} · ${c.telefono} · ${c.correo}`,
    ));
  } else if (type === "UPDATE" && old_record) {
    if (record.estado === "cancelada" && old_record.estado !== "cancelada") {
      tareas.push(enviarCorreo(c, `Tu hora en ${STUDIO.nombre} fue cancelada`, plantilla(c, "Tu hora fue cancelada", record, s,
        `Si quieres reagendar, escríbele a María por WhatsApp al ${STUDIO.whatsapp}.`)));
    } else if (record.estado === "confirmada" && (record.fecha !== old_record.fecha || record.hora !== old_record.hora)) {
      tareas.push(enviarCorreo(c, `Cambio de hora en ${STUDIO.nombre}`, plantilla(c, "Tu hora cambió", record, s,
        `Antes era el ${fechaLarga(old_record.fecha)}, ${bloque(old_record.hora)}.`)));
    }
  }

  const res = await Promise.allSettled(tareas);
  const errores = res.flatMap((r) => (r.status === "rejected" ? [String(r.reason)] : []));
  if (errores.length) console.error(errores);
  return Response.json({ ok: errores.length === 0, enviados: res.length - errores.length, errores });
});

async function enviarCorreo(c: Clienta, asunto: string, html: string) {
  const from = env("EMAIL_FROM");
  if (env("BREVO_API_KEY")) {
    const r = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: { "api-key": env("BREVO_API_KEY"), "content-type": "application/json" },
      body: JSON.stringify({ sender: { name: STUDIO.nombre, email: from }, to: [{ email: c.correo, name: `${c.nombre} ${c.apellido}` }], subject: asunto, htmlContent: html }),
    });
    if (!r.ok) throw new Error("Brevo: " + await r.text());
  } else if (env("RESEND_API_KEY")) {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { authorization: "Bearer " + env("RESEND_API_KEY"), "content-type": "application/json" },
      body: JSON.stringify({ from: `${STUDIO.nombre} <${from}>`, to: [c.correo], subject: asunto, html }),
    });
    if (!r.ok) throw new Error("Resend: " + await r.text());
  } else {
    throw new Error("Falta BREVO_API_KEY o RESEND_API_KEY");
  }
}

async function whatsappMaria(texto: string) {
  if (!env("CALLMEBOT_APIKEY")) throw new Error("Falta CALLMEBOT_APIKEY");
  const phone = env("MARIA_WHATSAPP") || "+56926108745";
  const url = `https://api.callmebot.com/whatsapp.php?phone=${encodeURIComponent(phone)}&text=${encodeURIComponent(texto)}&apikey=${encodeURIComponent(env("CALLMEBOT_APIKEY"))}`;
  const r = await fetch(url);
  const body = await r.text();
  if (!r.ok || /error/i.test(body)) throw new Error("CallMeBot: " + body.slice(0, 200));
}

function plantilla(c: Clienta, titulo: string, r: Reserva, servicio: string, nota: string) {
  const fila = (k: string, v: string) =>
    `<tr><td style="padding:6px 0;color:#9A7A8D;font-size:12px;letter-spacing:.12em;text-transform:uppercase">${k}</td><td style="padding:6px 0 6px 18px;color:#3A1730">${v}</td></tr>`;
  return `<!doctype html><html><body style="margin:0;background:#F7EDF1;font-family:Jost,'Avenir Next','Segoe UI',Arial,sans-serif">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F7EDF1;padding:28px 12px"><tr><td align="center">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#FDFAF8;border-radius:18px;overflow:hidden">
      <tr><td style="background:#4B1E3F;padding:22px 28px;color:#FDFAF8;letter-spacing:.32em;font-size:18px">MONSE<div style="font-size:10px;letter-spacing:.42em;color:#E9CFD9;margin-top:4px">NAILS STUDIO</div></td></tr>
      <tr><td style="padding:28px">
        <p style="margin:0 0 6px;color:#A8738F;font-size:13px;letter-spacing:.2em;text-transform:uppercase">Hola, ${esc(c.nombre)}</p>
        <h1 style="margin:0 0 18px;font-family:'Cormorant Garamond',Georgia,serif;font-weight:400;font-size:30px;color:#4B1E3F">${esc(titulo)}</h1>
        <table role="presentation" cellpadding="0" cellspacing="0" style="font-size:15px">
          ${fila("Servicio", esc(servicio))}
          ${fila("Día", fechaLarga(r.fecha))}
          ${fila("Bloque", bloque(r.hora))}
          ${fila("Precio", r.gratis ? "Gratis por fidelidad" : clp(r.precio))}
          ${fila("Dirección", STUDIO.direccion)}
        </table>
        ${nota ? `<p style="margin:18px 0 0;padding:12px 14px;background:#F7EDF1;border-radius:12px;color:#6E4A62;font-size:14px">${esc(nota)}</p>` : ""}
        <p style="margin:22px 0 0;color:#6E4A62;font-size:14px">¿Necesitas cambiar tu hora? Escríbele a María por WhatsApp al <b>${STUDIO.whatsapp}</b>.</p>
      </td></tr>
    </table>
  </td></tr></table></body></html>`;
}
