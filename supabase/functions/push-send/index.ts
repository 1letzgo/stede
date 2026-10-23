// push-send: von DB-Triggern (push_dispatch) aufgerufen mit {kind, id[, user_id]}.
// Ermittelt Empfänger und Text selbst aus der Datenbank, beachtet die Einstellungen der
// Empfänger (push_settings), verschickt über APNs (iOS) und merkt sich jeden Anlass in
// push_sent, damit nichts doppelt ankommt. Nur frische Datensätze (≤ 10 min) — ein erneuter
// Aufruf mit alter ID bewirkt nichts.
// Alle Apps (stede, Loog, spoog, wooge): APNs-Topic = push_tokens.app (Bundle-ID); eine Nachricht
// geht nur an Geräte, deren Gemeinde in derselben Region liegt wie die Gruppe.
// Secrets: APNS_KEY (Inhalt der .p8), APNS_KEY_ID, APNS_TEAM_ID.
import { createClient } from "jsr:@supabase/supabase-js@2";

const DEFAULT_TOPIC = "de.letzgo.stede";
const FRESH_MS = 10 * 60 * 1000;

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

type Message = { title: string; body: string; data: Record<string, string>; recipients: string[] };

function fresh(createdAt: string | null | undefined) {
  return !!createdAt && Date.now() - new Date(createdAt).getTime() < FRESH_MS;
}

const when = (iso: string) =>
  new Intl.DateTimeFormat("de-DE", {
    timeZone: "Europe/Berlin", weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit",
  }).format(new Date(iso));

async function activeMembers(communityId: string, except?: string | null) {
  const { data } = await db.from("community_members").select("user_id").eq("community_id", communityId).eq("status", "active");
  return (data ?? []).map((r) => r.user_id as string).filter((u) => u !== except);
}

async function build(kind: string, id: string, userId?: string): Promise<Message | null> {
  if (kind === "join_request" && userId) {
    const { data: m } = await db.from("community_members").select("status, created_at").eq("community_id", id).eq("user_id", userId).maybeSingle();
    if (!m || m.status !== "pending" || !fresh(m.created_at)) return null;
    const { data: c } = await db.from("communities").select("name").eq("id", id).single();
    const { data: p } = await db.from("profiles").select("display_name").eq("user_id", userId).maybeSingle();
    const { data: admins } = await db.from("community_members").select("user_id").eq("community_id", id).eq("status", "active").in("role", ["owner", "admin"]);
    return {
      title: "Neue Beitrittsanfrage",
      body: `${p?.display_name ?? "Jemand"} möchte „${c?.name ?? "deiner Gruppe"}“ beitreten.`,
      data: { type: "join_request", community_id: id },
      recipients: (admins ?? []).map((a) => a.user_id as string),
    };
  }
  if (kind === "community_pending") {
    const { data: c } = await db.from("communities").select("name, tenant_id, status, created_at, created_by").eq("id", id).single();
    if (!c || c.status !== "pending" || !fresh(c.created_at)) return null;
    const { data: admins } = await db.from("tenant_admins").select("user_id").eq("tenant_id", c.tenant_id);
    return {
      title: "Neue Gruppe wartet auf Freigabe",
      body: `„${c.name}“ wurde beantragt.`,
      data: { type: "community_pending", community_id: id },
      recipients: (admins ?? []).map((a) => a.user_id as string).filter((u) => u !== c.created_by),
    };
  }
  if (kind === "event") {
    const { data: e } = await db.from("community_events").select("title, starts_at, community_id, created_by, created_at, cancelled_at").eq("id", id).single();
    if (!e || e.cancelled_at || !fresh(e.created_at)) return null;
    const { data: c } = await db.from("communities").select("name").eq("id", e.community_id).single();
    return {
      title: `Neuer Termin · ${c?.name ?? "Gruppe"}`,
      body: `${e.title} – ${when(e.starts_at)}`,
      data: { type: "event", community_id: e.community_id, event_id: id },
      recipients: await activeMembers(e.community_id, e.created_by),
    };
  }
  if (kind === "poll") {
    const { data: q } = await db.from("community_polls").select("question, community_id, created_by, created_at").eq("id", id).single();
    if (!q || !fresh(q.created_at)) return null;
    const { data: c } = await db.from("communities").select("name").eq("id", q.community_id).single();
    return {
      title: `Neue Umfrage · ${c?.name ?? "Gruppe"}`,
      body: q.question,
      data: { type: "poll", community_id: q.community_id, poll_id: id },
      recipients: await activeMembers(q.community_id, q.created_by),
    };
  }
  return null;
}

// Einstellungen der Empfänger (push_settings; ohne Zeile ist alles an):
// Anlass ausgeschaltet oder Gruppe stummgeschaltet → keine Nachricht.
const settingFor: Record<string, "events" | "polls" | "admin"> = {
  event: "events", poll: "polls", join_request: "admin", community_pending: "admin",
};
async function applySettings(kind: string, msg: Message) {
  const field = settingFor[kind];
  if (!field || msg.recipients.length === 0) return;
  const { data } = await db.from("push_settings").select("user_id, events, polls, admin, muted_communities").in("user_id", msg.recipients);
  const off = new Set((data ?? []).filter((s) =>
    s[field] === false || (kind !== "community_pending" && ((s.muted_communities ?? []) as string[]).includes(msg.data.community_id))
  ).map((s) => s.user_id as string));
  msg.recipients = msg.recipients.filter((u) => !off.has(u));
}

/** Region der Gruppe (über ihre Heimatgemeinde) — eine Loog-Gruppe meldet sich nicht in stede. */
async function communityRegion(communityId: string): Promise<string | null> {
  const { data: c } = await db.from("communities").select("tenant_id").eq("id", communityId).maybeSingle();
  if (!c?.tenant_id) return null;
  const { data: t } = await db.from("tenants").select("region").eq("id", c.tenant_id).maybeSingle();
  return (t?.region as string) ?? null;
}

// APNs-Token (JWT, ES256), bis zu 50 min wiederverwendbar; gilt für alle Apps des Teams.
let cachedJwt: { token: string; at: number } | null = null;
async function apnsJwt(): Promise<string> {
  if (cachedJwt && Date.now() - cachedJwt.at < 50 * 60 * 1000) return cachedJwt.token;
  const pem = Deno.env.get("APNS_KEY")!.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (ch) => ch.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
  const enc = (obj: unknown) => b64(new TextEncoder().encode(JSON.stringify(obj)));
  const head = enc({ alg: "ES256", kid: Deno.env.get("APNS_KEY_ID") });
  const claims = enc({ iss: Deno.env.get("APNS_TEAM_ID"), iat: Math.floor(Date.now() / 1000) });
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${head}.${claims}`)));
  cachedJwt = { token: `${head}.${claims}.${b64(sig)}`, at: Date.now() };
  return cachedJwt.token;
}

async function sendApns(token: string, environment: string, topic: string, msg: Message) {
  const host = environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const res = await fetch(`https://${host}/3/device/${token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await apnsJwt()}`,
      "apns-topic": topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify({ aps: { alert: { title: msg.title, body: msg.body }, sound: "default" }, ...msg.data }),
  });
  if (res.ok) return "ok";
  const reason = (await res.json().catch(() => ({})))?.reason ?? String(res.status);
  // Abgemeldete oder falsche Tokens entfernen.
  if (res.status === 410 || ["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"].includes(reason)) {
    await db.from("push_tokens").delete().eq("token", token);
  }
  return reason;
}

Deno.serve(async (req) => {
  const { kind, id, user_id } = await req.json().catch(() => ({}));
  if (!kind || !id) return new Response("kind und id fehlen", { status: 400 });
  if (!Deno.env.get("APNS_KEY") || !Deno.env.get("APNS_KEY_ID") || !Deno.env.get("APNS_TEAM_ID")) {
    return new Response("APNs nicht konfiguriert", { status: 503 });
  }
  const msg = await build(kind, id, user_id);
  if (msg) await applySettings(kind, msg);
  if (!msg || msg.recipients.length === 0) return Response.json({ sent: 0, skipped: true });

  // Einmal je Anlass — ein zweiter Aufruf scheitert am Primärschlüssel.
  const key = user_id ? `${kind}:${id}:${user_id}` : `${kind}:${id}`;
  const { error: dup } = await db.from("push_sent").insert({ key, recipients: msg.recipients.length });
  if (dup) return Response.json({ sent: 0, duplicate: true });

  const region = await communityRegion(msg.data.community_id);
  const { data: tokens } = await db.from("push_tokens").select("token, environment, app, tenants(region)").eq("platform", "ios").in("user_id", msg.recipients);
  const matching = (tokens ?? []).filter((t) => {
    const tokenRegion = (t.tenants as { region?: string } | null)?.region ?? null;
    // Alte stede-Tokens ohne Gemeinde gelten als Ammerland.
    return !region || (tokenRegion ?? (t.app === DEFAULT_TOPIC ? "ammerland" : null)) === region;
  });
  const results = await Promise.all(matching.map((t) =>
    sendApns(t.token, t.environment, (t.app as string) || DEFAULT_TOPIC, msg).catch((e) => String(e))
  ));
  return Response.json({ sent: results.filter((r) => r === "ok").length, results });
});
