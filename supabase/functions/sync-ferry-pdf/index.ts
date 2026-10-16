// Fester Fährfahrplan aus dem PDF der Reederei (Spiekeroog u. a.), für Tenants mit
// config.ferry.type = "pdf". Lädt das PDF für heute … +pdf_days (Platzhalter {from}/{to} in pdf_url),
// liest es mit pdf.js über die Textpositionen (je Tabellenblock: Datum, „Nach <Insel>“, „Von <Insel>“;
// eine Zeile = Uhrzeit + Schiffskürzel, gehört zum letzten Datum darüber) und legt
// content/<slug>/<file>.json + content_files ab. Täglich per Cron `sync-ferry-pdf`; gearbeitet wird nur,
// wenn der letzte erfolgreiche Lauf älter als refresh_days (Standard 30) ist oder ?force=1.
// layout "siw" (Wangerooge): Jahresfahrplan der SIW, je Seite fünf Blöcke mit Datum „Do, 01.01.“ und den
// Spalten „Harlesiel ab“ / „Wangerooge Bahnhof ab“ (Zeiten „11.00“ untereinander, kein Schiffskürzel);
// pdf_url ohne Platzhalter, Fahrten von heute bis +pdf_days.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import * as pdfjs from "npm:pdfjs-dist@4.10.38/legacy/build/pdf.mjs";
// Worker im selben Thread (kein Web Worker im Edge-Runtime).
await import("npm:pdfjs-dist@4.10.38/legacy/build/pdf.worker.mjs");

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1";

type Trip = { day: string; time: string; toIsland: boolean; vessel: string };

async function parseTimetable(bytes: Uint8Array, start: Date): Promise<Trip[]> {
  const doc = await pdfjs.getDocument({ data: bytes, disableFontFace: true, useSystemFonts: false, isEvalSupported: false }).promise;
  const trips: Trip[] = [];
  for (let p = 1; p <= doc.numPages; p++) {
    const items = (await (await doc.getPage(p)).getTextContent()).items
      .filter((it: any) => it.str?.trim()).map((it: any) => ({ x: it.transform[4], y: it.transform[5], s: it.str.trim() }));
    const heads = items.filter((i) => /^(Nach|Von)\s/.test(i.s)).map((i) => ({ x: i.x, to: i.s.startsWith("Nach") }));
    const dates = items.filter((i) => /^\d{2}\.\d{2}\.$/.test(i.s));
    if (!dates.length) continue;
    const blockXs = [...new Set(dates.map((d) => Math.round(d.x / 20) * 20))].sort((a, b) => a - b);
    const blockOf = (x: number) => blockXs.filter((bx) => bx <= x + 5).pop();
    for (const it of items) {
      for (const m of it.s.matchAll(/(\d{2}):(\d{2})(?:\s+([A-Z]{2,4}\d?))?/g)) {
        const bx = blockOf(it.x);
        if (bx === undefined) continue;
        const date = dates.filter((d) => Math.round(d.x / 20) * 20 === bx && d.y >= it.y - 1).sort((a, b) => a.y - b.y)[0];
        if (!date) continue;
        const head = heads.reduce<{ x: number; to: boolean } | null>((best, h) => (!best || Math.abs(h.x - it.x) < Math.abs(best.x - it.x) ? h : best), null);
        const toIsland = head ? head.to : it.x - date.x < 43;
        const vessel = m[3] ?? items.find((o) => Math.abs(o.y - it.y) < 1.5 && o.x > it.x && o.x - it.x < 30 && /^[A-Z]{2,4}\d?$/.test(o.s))?.s ?? "";
        const [dd, mm] = date.s.split(".").map(Number);
        let year = start.getUTCFullYear();
        if (mm < start.getUTCMonth() + 1 - 6) year += 1; // Jahreswechsel im Zeitraum
        trips.push({ day: `${year}-${String(mm).padStart(2, "0")}-${String(dd).padStart(2, "0")}`, time: `${m[1]}:${m[2]}`, toIsland, vessel });
      }
    }
  }
  const seen = new Set<string>();
  return trips.filter((t) => { const k = `${t.day}|${t.time}|${t.toIsland}|${t.vessel}`; if (seen.has(k)) return false; seen.add(k); return true; })
    .sort((a, b) => (a.day + a.time).localeCompare(b.day + b.time));
}

// SIW-Jahresfahrplan: eine Uhrzeit gehört zum Block links von ihr und zum letzten Datum darüber;
// Spalte direkt neben dem Datum = ab Festland, die zweite = ab Insel.
async function parseSiw(bytes: Uint8Array): Promise<Trip[]> {
  const doc = await pdfjs.getDocument({ data: bytes, disableFontFace: true, useSystemFonts: false, isEvalSupported: false }).promise;
  const trips: Trip[] = [];
  for (let p = 1; p <= doc.numPages; p++) {
    const items = (await (await doc.getPage(p)).getTextContent()).items
      .filter((it: any) => it.str?.trim()).map((it: any) => ({ x: it.transform[4], y: it.transform[5], s: it.str.trim() }));
    const year = Number(items.map((i) => i.s.match(/Fahrplan\s+(\d{4})/)?.[1]).find(Boolean));
    const dates = items.filter((i) => /^\d{2}\.\d{2}\.$/.test(i.s));
    if (!year || !dates.length) continue;
    const blockXs = [...new Set(dates.map((d) => Math.round(d.x)))].sort((a, b) => a - b);
    for (const it of items) {
      const m = it.s.match(/^(\d{2})\.(\d{2})$/);
      if (!m) continue;
      const bx = blockXs.filter((x) => x < it.x).pop();
      if (bx === undefined) continue;
      const date = dates.filter((d) => Math.round(d.x) === bx && d.y >= it.y - 1).sort((a, b) => a.y - b.y)[0];
      if (!date) continue;
      const [dd, mm] = date.s.split(".").map(Number);
      trips.push({ day: `${year}-${String(mm).padStart(2, "0")}-${String(dd).padStart(2, "0")}`, time: `${m[1]}:${m[2]}`, toIsland: it.x - date.x < 70, vessel: "" });
    }
  }
  return trips.sort((a, b) => (a.day + a.time).localeCompare(b.day + b.time));
}

async function sha(text: string) {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  return Array.from(d, (b) => b.toString(16).padStart(2, "0")).join("");
}

const iso = (d: Date) => d.toISOString().slice(0, 10);

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const force = url.searchParams.get("force") === "1";
  const only = url.searchParams.get("tenant");
  const { data: tenants } = await admin.from("tenants").select("id, slug, config").not("config->ferry", "is", null);
  const results: Record<string, unknown> = {};
  for (const t of tenants ?? []) {
    const ferry = t.config?.ferry;
    if (ferry?.type !== "pdf" || !ferry.pdf_url || (only && only !== t.slug)) continue;
    const refreshDays = ferry.refresh_days ?? 30;
    if (!force) {
      const { data: last } = await admin.from("job_runs").select("finished_at").eq("job", "sync-ferry-pdf").eq("tenant_id", t.id).eq("ok", true)
        .order("finished_at", { ascending: false }).limit(1).maybeSingle();
      if (last?.finished_at && Date.now() - new Date(last.finished_at).getTime() < refreshDays * 86400_000) { results[t.slug] = "aktuell"; continue; }
    }
    const run = await admin.from("job_runs").insert({ job: "sync-ferry-pdf", tenant_id: t.id }).select("id").single();
    try {
      const start = new Date();
      const end = new Date(start.getTime() + (ferry.pdf_days ?? 90) * 86400_000);
      const pdfUrl = ferry.pdf_url.replaceAll("{from}", iso(start)).replaceAll("{to}", iso(end));
      const res = await fetch(pdfUrl, { headers: { "User-Agent": UA } });
      if (!res.ok || !(res.headers.get("content-type") ?? "").includes("pdf")) throw new Error(`PDF HTTP ${res.status} ${res.headers.get("content-type")}`);
      const bytes = new Uint8Array(await res.arrayBuffer());
      const trips = ferry.layout === "siw"
        ? (await parseSiw(bytes)).filter((x) => x.day >= iso(start) && x.day <= iso(end))
        : await parseTimetable(bytes, start);
      if (trips.length < 10) throw new Error(`nur ${trips.length} Fahrten erkannt — Layout geändert?`);
      const body = JSON.stringify({ source: ferry.source ?? "Fahrplan der Reederei (PDF)", fetched_at: new Date().toISOString(), from: iso(start), to: iso(end), trips });
      const name = ferry.file ?? "ferry";
      const path = `${t.slug}/${name}.json`;
      const hash = await sha(JSON.stringify(trips));
      const { data: current } = await admin.from("content_files").select("sha256").eq("tenant_id", t.id).eq("name", name).maybeSingle();
      const changed = current?.sha256 !== hash;
      if (changed) {
        const up = await admin.storage.from("content").upload(path, new Blob([body], { type: "application/json" }), { upsert: true, contentType: "application/json" });
        if (up.error) throw up.error;
        const row = await admin.from("content_files").upsert({ tenant_id: t.id, name, path, bytes: body.length, sha256: hash, updated_at: new Date().toISOString() }, { onConflict: "tenant_id,name" });
        if (row.error) throw row.error;
      }
      results[t.slug] = { trips: trips.length, days: new Set(trips.map((x) => x.day)).size, changed };
      if (run.data) await admin.from("job_runs").update({ finished_at: new Date().toISOString(), ok: true, rows: trips.length, message: changed ? "updated" : "unchanged" }).eq("id", run.data.id);
    } catch (e) {
      results[t.slug] = { error: String(e) };
      if (run.data) await admin.from("job_runs").update({ finished_at: new Date().toISOString(), ok: false, message: String(e) }).eq("id", run.data.id);
    }
  }
  return Response.json(results);
});
