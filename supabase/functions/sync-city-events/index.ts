// Termine der Gemeinden in die Tabelle city_events übernehmen.
// Quelle je Mandant in tenants.config.events_source:
//   {type:"nolis", url}  – Veranstaltungssuche des NOLIS-Managers (Westerstede), Platzhalter {from} {to} {page}
//   {type:"destination_one", experience, city?} – destination.one-Kalender (Ammerland-Touristik u. a.)
//   {type:"langeoog", days?, separate?} – veranstaltung.langeoog.de (Loog), Vorschaubilder in den Bucket content
//   {type:"typo3_list", url, name?} – Kalenderliste der TYPO3-„Distribution“ (spiekeroog.de: ein Jahr auf einer Seite,
//     Karten `listItem` mit data-ident), Bilder verkleinert in den Bucket content
// Zeitraum heute−1 bis +days (Standard 60, je Quelle überschreibbar). Nicht mehr gelistete Termine im Zeitraum bekommen deleted_at.
// Mit tenants.config.events_group: Fotos (verkleinert, mit Credit) nach event-photos/<gruppe>/import/, Westerstede-Detailseiten
// stückweise (Langtext, Foto), danach spiegelt mirror_city_events() die Zeilen als öffentliche Termine in diese Gruppe.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1";

const ENTITIES: Record<string, string> = {
  "&nbsp;": " ", "&amp;": "&", "&euro;": "€", "&shy;": "", "&auml;": "ä", "&ouml;": "ö", "&uuml;": "ü",
  "&Auml;": "Ä", "&Ouml;": "Ö", "&Uuml;": "Ü", "&szlig;": "ß", "&quot;": '"', "&apos;": "'", "&lt;": "<", "&gt;": ">",
  "&bdquo;": "„", "&ldquo;": "“", "&rdquo;": "”", "&ndash;": "–", "&mdash;": "—", "&hellip;": "…",
  "&laquo;": "«", "&raquo;": "»", "&sbquo;": "‚", "&lsquo;": "‘", "&rsquo;": "’", "&deg;": "°",
};

function strip(html: string): string {
  let t = html.replace(/<[^>]+>/g, " ");
  for (const [k, v] of Object.entries(ENTITIES)) t = t.split(k).join(v);
  t = t.replace(/&#(x?)([0-9a-fA-F]+);/g, (_, hex, num) => String.fromCodePoint(parseInt(num, hex ? 16 : 10)));
  return t.replace(/\s+/g, " ").trim();
}

/** Wie strip, aber Absätze und Zeilenumbrüche bleiben erhalten. */
function text(html: string): string {
  const marked = html.replace(/<br\s*\/?>/gi, "\n").replace(/<\/(p|div|li|h\d)>/gi, "\n");
  return marked.split("\n").map(strip).join("\n").replace(/\n{3,}/g, "\n\n").trim();
}

function berlinOffset(y: number, mo: number, d: number): string {
  // Sommerzeit: letzter Sonntag März 01:00 UTC bis letzter Sonntag Oktober 01:00 UTC.
  const lastSunday = (m: number) => { const dt = new Date(Date.UTC(y, m + 1, 0)); return dt.getUTCDate() - dt.getUTCDay(); };
  const date = Date.UTC(y, mo - 1, d, 12);
  const start = Date.UTC(y, 2, lastSunday(2), 1), end = Date.UTC(y, 9, lastSunday(9), 1);
  return date >= start && date < end ? "+02:00" : "+01:00";
}

interface Row {
  external_id: string; title: string; day: string; starts_at: string | null; ends_at: string | null; summary: string;
  location: string | null; organizer: string | null; category: string | null; series_note: string | null; detail_url: string | null;
  meeting_point?: string | null; registration?: string | null; price?: string | null; sold_out?: boolean; image_path?: string | null;
  description?: string | null; image_credit?: string | null; source_name?: string | null;
  /** Nur intern: Bild der Quelle, wird vor dem Upsert in image_path umgesetzt. */
  media?: { id: string; url: string } | null;
}

const BASE = Deno.env.get("SUPABASE_URL")!;
const PHOTOS = "event-photos";
const IMAGE_BUDGET = 40;   // neue Fotos je Gemeinde und Lauf
const DETAIL_BUDGET = 40;  // Westerstede-Detailseiten je Lauf

async function importedImages(group: string): Promise<Set<string>> {
  const names = new Set<string>();
  for (let offset = 0; offset < 20000; offset += 1000) {
    const { data } = await admin.storage.from(PHOTOS).list(`${group}/import`, { limit: 1000, offset });
    for (const f of data ?? []) names.add(f.name);
    if (!data || data.length < 1000) break;
  }
  return names;
}

/** Original laden, einmal über die Bildtransformation auf 1280 px verkleinern (WebP — ohne den Accept-Header käme
 *  bei PNG-Vorlagen wieder ein PNG mit über 1 MB zurück), nur die kleine Fassung behalten. */
async function importResized(group: string, name: string, url: string): Promise<boolean> {
  const tmp = `${group}/import/tmp-${name}`;
  try {
    const res = await fetch(url, { headers: { "User-Agent": UA } });
    if (!res.ok) return false;
    const bytes = new Uint8Array(await res.arrayBuffer());
    if (bytes.length < 500 || bytes.length > 24_000_000) return false;
    const up = await admin.storage.from(PHOTOS).upload(tmp, bytes, { contentType: res.headers.get("content-type") ?? "image/jpeg", upsert: true });
    if (up.error) return false;
    const small = await fetch(`${BASE}/storage/v1/render/image/public/${PHOTOS}/${tmp}?width=1280&quality=75&resize=contain`,
      { headers: { Accept: "image/webp" } });
    if (!small.ok) return false;
    const out = new Uint8Array(await small.arrayBuffer());
    const fin = await admin.storage.from(PHOTOS).upload(`${group}/import/${name}`, out, { contentType: small.headers.get("content-type") ?? "image/webp", upsert: true });
    return !fin.error;
  } catch { return false; } finally {
    await admin.storage.from(PHOTOS).remove([tmp]);
  }
}

async function pool<T>(items: T[], size: number, fn: (t: T) => Promise<void>) {
  for (let i = 0; i < items.length; i += size) await Promise.all(items.slice(i, i + size).map(fn));
}

/** destination.one-Fotos: vorhandene übernehmen, bis zum Budget neue laden. */
async function attachImages(group: string, rows: Row[]) {
  const known = await importedImages(group);
  // Erste Fassung lag als .jpg (teils PNG, über 1 MB) — weg damit, die .webp ersetzt sie. Dazu liegengebliebene
  // Originale (tmp-), falls das Löschen in einem früheren Lauf nicht durchging.
  const legacy = [...known].filter((n) => (n.startsWith("d1-") && n.endsWith(".jpg")) || n.startsWith("tmp-"));
  for (let i = 0; i < legacy.length; i += 100) await admin.storage.from(PHOTOS).remove(legacy.slice(i, i + 100).map((n) => `${group}/import/${n}`));
  const missing = new Map<string, string>();
  for (const r of rows) {
    if (r.media && !known.has(`d1-${r.media.id}.webp`)) missing.set(r.media.id, r.media.url);
  }
  await pool([...missing].slice(0, IMAGE_BUDGET), 4, async ([id, url]) => {
    if (await importResized(group, `d1-${id}.webp`, url)) known.add(`d1-${id}.webp`);
  });
  for (const r of rows) {
    if (r.media === undefined) continue;
    const name = r.media ? `d1-${r.media.id}.webp` : null;
    r.image_path = name && known.has(name) ? `${group}/import/${name}` : null;
    if (!r.image_path) r.image_credit = null;
  }
}

/** Westerstede: Langtext und Foto stehen nur auf der Detailseite — je Lauf ein Stück davon. */
async function fetchNolisDetails(tenantID: string, group: string): Promise<number> {
  const { data } = await admin.from("city_events").select("id, detail_url").eq("tenant_id", tenantID).is("deleted_at", null)
    .is("detail_fetched_at", null).not("detail_url", "is", null).gte("day", iso(new Date())).order("day").limit(DETAIL_BUDGET);
  const known = await importedImages(group);
  let done = 0;
  await pool(data ?? [], 5, async (row) => {
    try {
      const res = await fetch(row.detail_url, { headers: { "User-Agent": UA } });
      if (!res.ok) return;
      const html = await res.text();
      const description = text(html.match(/<div class="langbeschreibung">([\s\S]*?)<\/div>/)?.[1] ?? "") || null;
      const hash = html.match(/<div class="images"[\s\S]*?\/static\/images\/termine\/bild-([0-9a-f]+)-\d+\.webp/)?.[1];
      let image: string | null = null;
      if (hash) {
        const name = `nolis-${hash}.webp`;
        if (!known.has(name)) {
          // Fassung -60 ist 860 px breit — groß genug, ohne Umweg über die Transformation.
          const img = await fetch(`https://www.westerstede.de/static/images/termine/bild-${hash}-60.webp`, { headers: { "User-Agent": UA } });
          if (img.ok) {
            const up = await admin.storage.from(PHOTOS).upload(`${group}/import/${name}`, new Uint8Array(await img.arrayBuffer()), { contentType: "image/webp", upsert: true });
            if (!up.error) known.add(name);
          }
        }
        if (known.has(name)) image = `${group}/import/${name}`;
      }
      await admin.from("city_events").update({ description, image_path: image, image_credit: image ? "Foto: westerstede.de" : null,
        detail_fetched_at: new Date().toISOString() }).eq("id", row.id);
      done++;
    } catch { /* nächster Lauf */ }
  });
  return done;
}

function iso(d: Date): string { return d.toISOString().slice(0, 10); }

// MARK: NOLIS (Westerstede)

function field(name: string, block: string): string | null {
  const m = block.match(new RegExp(`<div class="${name}">[\\s\\S]*?<span class="feldinhalt">([\\s\\S]*?)</div>`));
  if (!m) return null;
  const inner = m[1].replace(/<br\s*\/?>/g, ", ").replace(/<a class="link_navigator[\s\S]*?<\/a>/g, " ");
  const t = strip(inner).replace(/(\s*,\s*)+/g, ", ").replace(", Deutschland", "").replace(/^[,\s]+|[,\s]+$/g, "");
  return t || null;
}

function parseNolis(html: string): Row[] {
  const rows: Row[] = [];
  for (const block of html.split('<a name="terminanker_').slice(1)) {
    const id = block.match(/^(\d+)"/)?.[1]; if (!id) continue;
    const title = strip(block.match(/<span class="bezeichnung">([\s\S]*?)<\/span>/)?.[1] ?? ""); if (!title) continue;
    const detail = block.match(/href="(https:\/\/www\.westerstede\.de\/regional\/veranstaltungen\/[^"?]+\.html)[^"]*"\s+title="Detailseite"/)?.[1] ?? null;
    const dateBlock = block.match(/<span class="datum">([\s\S]*?)(?=<div class="|<\/div>)/)?.[1] ?? "";
    const series = dateBlock.match(/<img[^>]*title="([^"]*)"/)?.[1] ?? null;
    const dateText = strip(dateBlock);
    const dates = [...dateText.matchAll(/(\d{2})\.(\d{2})\.(\d{4})/g)];
    const clocks = [...dateText.matchAll(/(\d{1,2}):(\d{2})/g)];
    if (!dates.length) continue;
    const [, dd, mm, yyyy] = dates[0];
    const day = `${yyyy}-${mm}-${dd}`;
    const off = berlinOffset(+yyyy, +mm, +dd);
    const startClock = clocks[0], endClock = clocks[1];
    const starts = startClock ? `${day}T${startClock[1].padStart(2, "0")}:${startClock[2]}:00${off}` : null;
    const ends = startClock && endClock ? `${day}T${endClock[1].padStart(2, "0")}:${endClock[2]}:00${off}` : null;
    const summary = strip(block.match(/<div class="kurzbeschreibung">([\s\S]*?)<\/div>/)?.[1] ?? "");
    const category = strip(block.match(/<div class="rubriken">\s*Rubrik:\s*([\s\S]*?)(?:<br|<\/div>)/)?.[1] ?? "") || null;
    rows.push({ external_id: id, title, day, starts_at: starts, ends_at: ends, summary, location: field("veranstaltungsort", block), organizer: field("veranstalter", block), category, series_note: series ? strip(series) : null, detail_url: detail, source_name: "westerstede.de" });
  }
  return rows;
}

async function fetchNolis(template: string, from: Date, to: Date): Promise<Row[]> {
  const rows: Row[] = [];
  for (let page = 1; page <= 40; page++) {
    const url = template.replace("{from}", iso(from)).replace("{to}", iso(to)).replace("{page}", String(page));
    const res = await fetch(url, { headers: { "User-Agent": UA } });
    if (!res.ok) throw new Error(`HTTP ${res.status} on page ${page}`);
    const html = await res.text();
    rows.push(...parseNolis(html));
    const total = Number(html.match(/Seite \d+ von (\d+)/)?.[1] ?? "1");
    if (page >= total) break;
  }
  return rows;
}

// MARK: destination.one (Ammerland-Touristik, Edewecht)

const WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const dmy = (d: Date) => `${String(d.getUTCDate()).padStart(2, "0")}.${String(d.getUTCMonth() + 1).padStart(2, "0")}.${d.getUTCFullYear()}`;

// Uhrzeit "HH:MM" aus einem ISO-Zeitstempel mit Offset (lokale Zeit bleibt erhalten).
const clock = (s?: string) => s?.match(/T(\d{2}:\d{2})/)?.[1] ?? null;
const dayOf = (s: string) => s.slice(0, 10);

function stamp(day: string, hm: string | null): string | null {
  if (!hm) return null;
  const [y, m, d] = day.split("-").map(Number);
  return `${day}T${hm}:00${berlinOffset(y, m, d)}`;
}

/** Löst die Zeitfenster (einmalig, täglich, wöchentlich bis repeatUntil) in einzelne Tage im Zeitraum auf. */
function occurrences(intervals: any[], from: string, to: string): { day: string; start: string | null; end: string | null }[] {
  const out: { day: string; start: string | null; end: string | null }[] = [];
  for (const iv of intervals ?? []) {
    if (!iv?.start) continue;
    const first = dayOf(iv.start);
    // 00:00 bis 00:00/23:59 heißt ganztägig — dann ohne Uhrzeit.
    const rawStart = clock(iv.start), rawEnd = clock(iv.end);
    const allDay = rawStart === "00:00" && (!rawEnd || rawEnd === "00:00" || rawEnd === "23:59");
    const startHm = allDay ? null : rawStart, endHm = allDay ? null : rawEnd;
    const until = iv.repeatUntil ? dayOf(iv.repeatUntil) : first;
    const freq = iv.freq as string | undefined;
    if (!freq) {
      // Mehrtägig ohne Wiederholung: jeder Tag bis zum Ende; Uhrzeit nur am ersten Tag.
      const last = iv.end ? dayOf(iv.end) : first;
      for (let d = new Date(first + "T12:00:00Z"); iso(d) <= last && iso(d) <= to; d.setUTCDate(d.getUTCDate() + 1)) {
        const day = iso(d); if (day < from) continue;
        out.push({ day, start: day === first ? stamp(day, startHm) : null, end: day === first && last === first ? stamp(day, endHm) : null });
      }
      continue;
    }
    const step = Math.max(1, Number(iv.interval ?? 1));
    const days: string[] = (iv.weekdays ?? []).filter((w: string) => WEEKDAYS.includes(w));
    for (let d = new Date(first + "T12:00:00Z"), n = 0; iso(d) <= until && iso(d) <= to; d.setUTCDate(d.getUTCDate() + 1), n++) {
      const day = iso(d); if (day < from) continue;
      const wd = WEEKDAYS[d.getUTCDay()];
      let hit = false;
      if (freq === "Daily") hit = n % step === 0;
      else if (freq === "Weekly") hit = (days.length ? days.includes(wd) : wd === WEEKDAYS[new Date(first + "T12:00:00Z").getUTCDay()]) && Math.floor(n / 7) % step === 0;
      else if (freq === "Monthly") hit = d.getUTCDate() === new Date(first + "T12:00:00Z").getUTCDate();
      else if (freq === "Yearly") hit = day.slice(5) === first.slice(5);
      if (hit) out.push({ day, start: stamp(day, startHm), end: stamp(day, endHm) });
    }
  }
  return out;
}

const D1_NAMES: Record<string, string> = { "ammerland-touristik": "Ammerland-Touristik", "edewecht": "Gemeinde Edewecht" };

async function fetchDestinationOne(src: { experience: string; city?: string; name?: string }, from: Date, to: Date): Promise<Row[]> {
  const sourceName = src.name ?? D1_NAMES[src.experience] ?? "destination.one";
  const rows: Row[] = [];
  const q = src.city ? `&q=${encodeURIComponent(`city:"${src.city}"`)}` : "";
  for (let offset = 0; offset < 5000; offset += 500) {
    const url = `https://meta.et4.de/rest.ashx/search/?experience=${encodeURIComponent(src.experience)}&type=Event&template=ET2014A.json&limit=500&offset=${offset}${q}&startdate=${dmy(from)}&enddate=${dmy(to)}`;
    const res = await fetch(url, { headers: { "User-Agent": UA } });
    if (!res.ok) throw new Error(`HTTP ${res.status} destination.one`);
    const data = await res.json();
    if (data.status && data.status !== "OK") throw new Error(`destination.one ${data.status}`);
    const items: any[] = data.items ?? [];
    for (const it of items) {
      if (src.city && it.city && it.city !== src.city) continue;
      const texts: any[] = it.texts ?? [];
      const teaser = texts.find((t) => t.rel === "teaser" && t.type === "text/plain")?.value
        ?? strip(texts.find((t) => t.rel === "teaser")?.value ?? "")
        ?? "";
      const details = texts.find((t) => t.rel === "details" && t.type === "text/plain")?.value ?? strip(texts.find((t) => t.rel === "details")?.value ?? "");
      const summary = (teaser || details || "").replace(/\s+/g, " ").trim().slice(0, 400);
      const location = [it.name, it.street, it.city && it.city !== src.city ? it.city : null].filter(Boolean).join(", ") || null;
      const longText = (texts.find((t) => t.rel === "details" && t.type === "text/plain")?.value as string | undefined)?.trim()
        || text(texts.find((t) => t.rel === "details")?.value ?? "");
      const description = [teaser && teaser !== longText ? String(teaser).trim() : null, longText || null].filter(Boolean).join("\n\n").slice(0, 4000) || null;
      const photo = (it.media_objects ?? []).find((m: any) => m.rel === "default" && String(m.type ?? "").startsWith("image/") && m.url);
      const media = photo ? { id: String(photo.id ?? photo.url).replace(/[^\w-]/g, ""), url: String(photo.url) } : null;
      const author = photo?.source ? String(photo.source).trim() : null;
      const credit = photo ? `Foto: ${author ?? sourceName}${photo.license ? ` (${photo.license})` : ""}${author ? ` · ${sourceName}` : ""}` : null;
      for (const o of occurrences(it.timeIntervals, iso(from), iso(to))) {
        rows.push({ external_id: `d1-${it.id}`, title: strip(it.title ?? ""), day: o.day, starts_at: o.start, ends_at: o.end, summary, location,
          // Veranstalter steht bei destination.one unter addresses (rel "organizer"), `company` ist meist leer.
          organizer: strip((it.addresses ?? []).find((a: any) => a.rel === "organizer")?.name ?? "") || it.company || null,
          category: (it.categories ?? [])[0] ?? null, series_note: null,
          detail_url: it.web || (it.media_objects ?? []).find((m: any) => m.rel === "canonical")?.url || null,
          description, source_name: sourceName, media, image_credit: credit });
      }
    }
    if (items.length < 500 || offset + items.length >= (data.overallcount ?? 0)) break;
  }
  return rows.filter((r) => r.title);
}

// MARK: veranstaltung.langeoog.de (Loog)

const LANGEOOG = "https://veranstaltung.langeoog.de/api/veranstaltung/";

async function langeoogPage(from: Date, to: Date, page: number): Promise<string> {
  const url = `${LANGEOOG}?veranstaltungen&p=${page}&veranstaltung_von=${iso(from)}&veranstaltung_bis=${iso(to)}`;
  const res = await fetch(url, { headers: { "User-Agent": UA } });
  if (!res.ok) throw new Error(`HTTP ${res.status} langeoog page ${page}`);
  const bytes = new Uint8Array(await res.arrayBuffer());
  try { return new TextDecoder("utf-8", { fatal: true }).decode(bytes); } catch { return new TextDecoder("iso-8859-1").decode(bytes); }
}

async function sha(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return Array.from(digest.slice(0, 12), (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Vorschaubild (base64 im HTML) einmalig als Datei ablegen; Name = Hash, also unveränderlich. */
async function storeImage(slug: string, base64: string, known: Set<string>): Promise<string | null> {
  try {
    const bytes = Uint8Array.from(atob(base64.replace(/\s+/g, "")), (c) => c.charCodeAt(0));
    if (bytes.length < 200) return null;
    const name = `${await sha(bytes)}.jpg`;
    const path = `${slug}/events/${name}`;
    if (!known.has(name)) {
      const { error } = await admin.storage.from("content").upload(path, bytes, { contentType: "image/jpeg", upsert: false });
      if (error && !/exists|Duplicate/i.test(error.message)) return null;
      known.add(name);
    }
    return path;
  } catch { return null; }
}

async function knownImages(slug: string): Promise<Set<string>> {
  const names = new Set<string>();
  for (let offset = 0; offset < 20000; offset += 1000) {
    const { data } = await admin.storage.from("content").list(`${slug}/events`, { limit: 1000, offset });
    for (const f of data ?? []) names.add(f.name);
    if (!data || data.length < 1000) break;
  }
  return names;
}

async function fetchLangeoog(slug: string, from: Date, to: Date): Promise<Row[]> {
  const first = await langeoogPage(from, to, 1);
  const total = Math.max(1, ...[...first.matchAll(/veranstaltungen&(?:amp;)?p=(\d+)/g)].map((m) => Number(m[1])));
  const pages = [first];
  // Weitere Seiten in kleinen Gruppen parallel; ausgewertet wird in Reihenfolge,
  // weil die Datums-Überschrift einer Seite für die Blöcke der nächsten weitergilt.
  for (let p = 2; p <= Math.min(total, 150); p += 6) {
    const batch = [];
    for (let q = p; q < p + 6 && q <= Math.min(total, 150); q++) batch.push(langeoogPage(from, to, q));
    pages.push(...await Promise.all(batch));
  }
  const known = await knownImages(slug);
  const rows: Row[] = [];
  let day: string | null = null;
  for (const html of pages) {
    // Überschriften („Sonntag, den 27.09.2026“) und Termin-Blöcke in Dokumentreihenfolge.
    const tokens = [...html.matchAll(/alert-success alert-block">\s*[^<]*?(\d{2})\.(\d{2})\.(\d{4})|row-fluid veranstaltung/g)];
    for (let i = 0; i < tokens.length; i++) {
      const t = tokens[i];
      if (t[1]) { day = `${t[3]}-${t[2]}-${t[1]}`; continue; }
      if (!day) continue;
      const block = html.slice(t.index! + t[0].length, i + 1 < tokens.length ? tokens[i + 1].index : undefined);
      const id = block.match(/termin=(\d+)/)?.[1]; if (!id) continue;
      const heading = block.match(/>(\d{1,2}:\d{2} Uhr - [^<]+)<\/a>/)?.[1] ?? block.match(/>([^<]{3,80})<\/a><\/b>/)?.[1];
      if (!heading) continue;
      const timed = strip(heading).match(/^(\d{1,2}):(\d{2}) Uhr - (.+)$/);
      const title = timed ? timed[3].trim() : strip(heading);
      const [y, m, d] = day.split("-").map(Number);
      const starts = timed ? `${day}T${timed[1].padStart(2, "0")}:${timed[2]}:00${berlinOffset(y, m, d)}` : null;
      const paragraphs = [...block.matchAll(/<p>([\s\S]*?)<\/p>/g)].map((p) => strip(p[1])).filter((p) => p && !/ausgebucht/i.test(p));
      const info = strip(block.match(/vernstaltung-info[^>]*>([\s\S]*?)<\/div>/)?.[1] ?? "");
      const value = (prefix: string) => info.split("|").map((s) => s.trim()).find((s) => s.startsWith(prefix))?.slice(prefix.length).trim() || null;
      const image = block.match(/src="data:image\/[a-zA-Z]+;base64,([^"]+)"/)?.[1];
      const meeting = value("Treffpunkt:");
      rows.push({
        external_id: id, title, day, starts_at: starts, ends_at: null, summary: paragraphs.join(" "),
        location: meeting, organizer: null, category: null, series_note: null,
        detail_url: `${LANGEOOG}?page=details&termin=${id}`,
        meeting_point: meeting, registration: value("Anmeldung:"), price: value("Preise ab:"),
        sold_out: /ausgebucht/i.test(block), image_path: image ? await storeImage(slug, image, known) : null,
      });
    }
  }
  return rows;
}

// MARK: TYPO3-„Distribution“-Kalender (spiekeroog.de)

const SPK_IMAGE_BUDGET = 60; // neue Bilder je Lauf (viele Termine teilen sich ein Bild)

/** Kalenderliste mit allen Terminen eines Jahres auf einer Seite: <article class="listItem" data-ident="eventdate_<id>">. */
async function fetchTypo3List(slug: string, src: { url: string; name?: string }, from: Date, to: Date): Promise<Row[]> {
  const res = await fetch(src.url, { headers: { "User-Agent": UA } });
  if (!res.ok) throw new Error(`HTTP ${res.status} ${src.url}`);
  const html = await res.text();
  const sourceName = src.name ?? new URL(src.url).hostname.replace(/^www\./, "");
  const known = await knownImages(slug);
  let budget = SPK_IMAGE_BUDGET;
  const rows: Row[] = [];
  const blocks = html.split('<article class="listItem').slice(1);
  for (const block of blocks) {
    const id = block.match(/data-ident="eventdate_(\d+)"/)?.[1]; if (!id) continue;
    const title = strip(block.match(/listItem__body__headline">([\s\S]*?)<\/h3>/)?.[1] ?? ""); if (!title) continue;
    const date = block.match(/data--date">(\d{2})\.(\d{2})\.(\d{4})/); if (!date) continue;
    const day = `${date[3]}-${date[2]}-${date[1]}`;
    if (day < iso(from) || day > iso(to)) continue;
    const times = [...(block.match(/data--time">([^<]*)</)?.[1] ?? "").matchAll(/(\d{1,2}):(\d{2})/g)];
    const [y, m, d] = day.split("-").map(Number);
    const at = (t?: RegExpMatchArray) => t ? `${day}T${t[1].padStart(2, "0")}:${t[2]}:00${berlinOffset(y, m, d)}` : null;
    const location = strip(block.match(/data--location">([\s\S]*?)<\/p>/)?.[1] ?? "") || null;
    const price = strip(block.match(/data--price">([\s\S]*?)<\/p>/)?.[1] ?? "") || null;
    // Langfassung steht im Span für große Bildschirme (data-hidden-ty), die Kurzfassung endet mit „…“.
    const summary = strip(block.match(/<span data-hidden-ty>([\s\S]*?)<\/span>/)?.[1] ?? block.match(/listItem__body__text">([\s\S]*?)<\/p>/)?.[1] ?? "");
    const link = block.match(/href="([^"]+)"[^>]*class="listItem__link"/)?.[1] ?? null;
    const booking = /Jetzt buchen/.test(block);
    // Bild über den Bild-Proxy der Seite in passender Größe (Quelle: srcset für schmale Bildschirme, 580×384).
    const img = block.match(/<source srcset="([^"]+)" media="\(min-width: 0px\)">/)?.[1]
      ?? block.match(/<img class="listItem__image"[^>]*src="([^"]+)"/)?.[1];
    let image_path: string | null = null;
    if (img) {
      const key = img.split("/").pop() ?? img; // base64 der Original-URL — gleiche Vorlage, gleiche Datei
      const name = `t3-${await sha(new TextEncoder().encode(key))}.jpg`;
      if (!known.has(name) && budget > 0) {
        budget--;
        try {
          const r = await fetch(img, { headers: { "User-Agent": UA, Accept: "image/jpeg,image/*" } });
          if (r.ok) {
            const bytes = new Uint8Array(await r.arrayBuffer());
            const { error } = await admin.storage.from("content").upload(`${slug}/events/${name}`, bytes,
              { contentType: r.headers.get("content-type") ?? "image/jpeg", upsert: true });
            if (!error) known.add(name);
          }
        } catch { /* nächster Lauf */ }
      }
      if (known.has(name)) image_path = `${slug}/events/${name}`;
    }
    rows.push({
      external_id: `t3-${id}`, title, day, starts_at: at(times[0]), ends_at: at(times[1]), summary,
      location, organizer: null, category: null, series_note: null, detail_url: link,
      meeting_point: location, registration: booking ? "Online buchbar" : null, price,
      sold_out: /listItem--soldOut/.test(block), image_path, source_name: sourceName,
    });
  }
  return rows;
}

// MARK: Detailseiten der Inselquellen (Veranstalter, Langtext, Kategorie)

const SOURCE_DETAIL_BUDGET = 60; // Seiten je Lauf

interface SourceDetail { organizer: string | null; description: string | null; category: string | null }

function parseLangeoogDetail(html: string): SourceDetail {
  const organizer = strip(html.match(/<label>Veranstalter:\s*<\/label>\s*<\/div>\s*<div class="span7">\s*<label>([\s\S]*?)<\/label>/)?.[1] ?? "");
  const body = html.match(/<div class="span12">\s*((?:<p>[\s\S]*?<\/p>\s*)+)<\/div>/)?.[1] ?? "";
  return { organizer: organizer && organizer !== "-" ? organizer : null, description: text(body) || null, category: null };
}

function parseTypo3Detail(html: string): SourceDetail {
  const organizer = strip(html.match(/<strong>Veranstalter[^<:]*:<\/strong>\s*([^<]+)/)?.[1] ?? "");
  const category = strip(html.match(/infoBlock__category__item">([^<]+)</)?.[1] ?? "");
  const body = (html.match(/<div class="baseArticle__text">([\s\S]*?)<\/div>/)?.[1] ?? "").replace(/<h2[\s\S]*?<\/h2>/, "");
  return { organizer: organizer && organizer !== "-" ? organizer : null, description: text(body) || null, category: category || null };
}

/** Langeoog (eine Seite je Termin) und spiekeroog.de (eine Seite je Reihe): Details stückweise nachladen.
 *  Gleiche Seite bzw. — bei Langeoog — gleicher Titel teilen Veranstalter und Text. */
async function fetchSourceDetails(tenantID: string, type: string): Promise<number> {
  const { data } = await admin.from("city_events").select("detail_url, title").eq("tenant_id", tenantID).is("deleted_at", null)
    .is("detail_fetched_at", null).not("detail_url", "is", null).gte("day", iso(new Date())).order("day").limit(1000);
  const pages = new Map<string, string>();
  const titles = new Set<string>();
  for (const r of data ?? []) {
    if (pages.size >= SOURCE_DETAIL_BUDGET) break;
    if (type === "langeoog" && titles.has(r.title)) continue;
    if (!pages.has(r.detail_url)) { pages.set(r.detail_url, r.title); titles.add(r.title); }
  }
  let done = 0;
  await pool([...pages], 6, async ([url, title]) => {
    try {
      const res = await fetch(url, { headers: { "User-Agent": UA } });
      if (!res.ok) return;
      const html = await res.text();
      const d = type === "langeoog" ? parseLangeoogDetail(html) : parseTypo3Detail(html);
      const patch: Record<string, unknown> = { organizer: d.organizer, description: d.description, detail_fetched_at: new Date().toISOString() };
      if (d.category) patch.category = d.category;
      await admin.from("city_events").update(patch).eq("tenant_id", tenantID).eq("detail_url", url);
      if (type === "langeoog") {
        await admin.from("city_events").update(patch).eq("tenant_id", tenantID).eq("title", title).is("detail_fetched_at", null);
      }
      done++;
    } catch { /* nächster Lauf */ }
  });
  return done;
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const days = Number(url.searchParams.get("days") ?? "60");
  const only = url.searchParams.get("tenant");
  const { data: tenants, error } = await admin.from("tenants").select("id, slug, config");
  if (error) return new Response(error.message, { status: 500 });
  const results: Record<string, unknown> = {};
  for (const tenant of tenants ?? []) {
    if (only && tenant.slug !== only) continue;
    const cfg = (tenant.config ?? {}) as any;
    const source = cfg.events_source ?? (cfg.events_search_url ? { type: "nolis", url: cfg.events_search_url } : null);
    if (!source) continue;
    // Langeoog braucht viele Seiten — eigener Cron-Aufruf mit ?tenant=loog.
    if (!only && source.separate) continue;
    const run = await admin.from("job_runs").insert({ job: "sync-city-events", tenant_id: tenant.id }).select("id").single();
    try {
      const from = new Date(); from.setUTCDate(from.getUTCDate() - 1);
      const to = new Date(); to.setUTCDate(to.getUTCDate() + Math.min(days, Number(source.days ?? days)));
      const rows = source.type === "destination_one" ? await fetchDestinationOne(source, from, to)
        : source.type === "langeoog" ? await fetchLangeoog(tenant.slug, from, to)
        : source.type === "typo3_list" ? await fetchTypo3List(tenant.slug, source, from, to)
        : await fetchNolis(source.url, from, to);
      const group: string | undefined = cfg.events_group;
      if (group && source.type === "destination_one") await attachImages(group, rows);
      const seen = new Map<string, Row>();
      for (const r of rows) seen.set(`${r.external_id}|${r.day}`, r);
      // Langeoog und spiekeroog.de liefern Veranstalter und Kategorie erst über die Detailseite — die Liste
      // darf sie nicht stündlich wieder leeren.
      const detailed = source.type === "langeoog" || source.type === "typo3_list";
      const unique = [...seen.values()].map(({ media: _m, ...r }) => {
        const row: Record<string, unknown> = { ...r, tenant_id: tenant.id, deleted_at: null };
        if (detailed) { delete row.organizer; delete row.category; }
        return row;
      });
      for (let i = 0; i < unique.length; i += 200) {
        const { error: upErr } = await admin.from("city_events").upsert(unique.slice(i, i + 200), { onConflict: "tenant_id,external_id,day" });
        if (upErr) throw upErr;
      }
      const { data: existing } = await admin.from("city_events").select("id, external_id, day")
        .eq("tenant_id", tenant.id).is("deleted_at", null).gte("day", iso(from)).lte("day", iso(to));
      const gone = (existing ?? []).filter((e) => !seen.has(`${e.external_id}|${e.day}`)).map((e) => e.id);
      for (let i = 0; i < gone.length; i += 200) {
        await admin.from("city_events").update({ deleted_at: new Date().toISOString() }).in("id", gone.slice(i, i + 200));
      }
      let details = 0, mirror: unknown = null;
      if (detailed) details = await fetchSourceDetails(tenant.id, source.type);
      if (group) {
        if (source.type === "nolis") details = await fetchNolisDetails(tenant.id, group);
        const m = await admin.rpc("mirror_city_events", { p_tenant: tenant.id });
        mirror = m.error ? { error: m.error.message } : m.data;
      }
      results[tenant.slug] = { upserted: unique.length, removed: gone.length, details, mirror };
      if (run.data) await admin.from("job_runs").update({ finished_at: new Date().toISOString(), ok: true, rows: unique.length, message: `removed ${gone.length}` }).eq("id", run.data.id);
    } catch (e) {
      results[tenant.slug] = { error: String(e) };
      if (run.data) await admin.from("job_runs").update({ finished_at: new Date().toISOString(), ok: false, message: String(e) }).eq("id", run.data.id);
    }
  }
  return new Response(JSON.stringify(results), { headers: { "Content-Type": "application/json" } });
});
