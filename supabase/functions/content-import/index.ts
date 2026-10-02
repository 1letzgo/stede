// Einmal-Import der Inhalte einer Gemeinde aus `tools/out/<slug>/` (Skill `new-region-app`).
// Wird nur für einen Import deployt — mit eingesetztem Einmal-Token statt __IMPORT_TOKEN__ — und danach
// wieder durch den 410-Stub (`stub.ts`) ersetzt. Liest die Dateien über eine öffentliche URL (Cloudflare
// Quick Tunnel auf tools/out) und schreibt mit der Service-Rolle:
//   places + place_directories (Upsert, verschwundene Orte bekommen deleted_at),
//   Fotos der Orte (`image` = Datei in tools/out/<slug>/images/) → Bucket `content/<slug>/places/<datei>` + image_path,
//   bus_stops (falls bus-stops.json da ist),
//   Bucket `content/<slug>/<name>.json` + content_files (inselkarte, bus-stops, abfuhr-strassen).
// Aufruf: POST /functions/v1/content-import  {"token": "...", "slug": "juist", "base": "https://….trycloudflare.com"}
import { createClient } from "jsr:@supabase/supabase-js@2";

const TOKEN = "__IMPORT_TOKEN__";

const DIRECTORIES: Record<string, string> = {
  "gastronomie.json": "gastro", "gesundheit.json": "health", "freizeit.json": "leisure",
  "sehenswuerdigkeiten.json": "sights", "spielplaetze.json": "playgrounds", "ausfluege.json": "trips",
  "ehrenamt.json": "volunteer",
};
const FILES = ["inselkarte", "bus-stops", "abfuhr-strassen"];

async function sha256(bytes: Uint8Array) {
  const d = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  const { token, slug, base } = await req.json().catch(() => ({}));
  if (TOKEN.startsWith("__") || token !== TOKEN) return new Response("forbidden", { status: 403 });
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: tenant } = await db.from("tenants").select("id").eq("slug", slug).single();
  if (!tenant) return new Response(`unknown tenant ${slug}`, { status: 404 });
  const get = async (name: string) => {
    const r = await fetch(`${base}/${slug}/${name}`);
    return r.ok ? new Uint8Array(await r.arrayBuffer()) : null;
  };
  const report: Record<string, unknown> = {};

  // Orte je Verzeichnis
  const dirs: Array<[string, any]> = [];
  for (const [file, dir] of Object.entries(DIRECTORIES)) {
    const raw = await get(file);
    if (raw) dirs.push([dir, JSON.parse(new TextDecoder().decode(raw))]);
  }
  const bikes = await get("fahrradverleih.json");
  if (bikes) {
    const b = JSON.parse(new TextDecoder().decode(bikes));
    dirs.push(["bikes", { source: b.source, fetchedAt: b.fetchedAt, places: (b.providers ?? []).map((p: any) => ({
      id: p.id, name: p.name, category: "Fahrrad", teaser: p.teaser, phone: p.phone, email: p.email, website: p.website,
      features: p.features, street: p.stations?.[0]?.street, latitude: p.stations?.[0]?.latitude, longitude: p.stations?.[0]?.longitude,
      stations: p.stations?.length > 1 ? p.stations : null, image: p.image, imagePath: p.imagePath, imageCredit: p.imageCredit,
    })) }]);
  }
  for (const [dir, d] of dirs) {
    const places = d.places ?? [];
    if (!places.length) continue;
    await db.from("place_directories").upsert({ tenant_id: tenant.id, directory: dir, source: d.source || "OpenStreetMap", fetched_at: d.fetchedAt, updated_at: new Date().toISOString() });
    for (const p of places) {
      if (!p.image) continue;
      const img = await get(`images/${p.image}`);
      if (!img) continue;
      const path = `${slug}/places/${p.image}`;
      const { error } = await db.storage.from("content").upload(path, img, { contentType: "image/jpeg", upsert: true });
      if (error) return new Response(`upload ${path}: ${error.message}`, { status: 500 });
      p.imagePath = path;
      report["images"] = ((report["images"] as number) ?? 0) + 1;
    }
    const rows = places.map((p: any, i: number) => ({
      tenant_id: tenant.id, directory: dir, external_id: p.id, kind: p.category, name: p.name, teaser: p.teaser ?? null,
      street: p.street ?? null, phone: p.phone ?? null, email: p.email ?? null, website: p.website ?? null, hours: p.hours ?? null,
      rest_day: p.restDay ?? null, season_note: p.seasonNote ?? null, image_credit: p.imageCredit ?? null,
      extra_link_title: p.extraLinkTitle ?? null, extra_link_url: p.extraLinkURL ?? null, features: p.features ?? [],
      lat: p.latitude ?? null, lon: p.longitude ?? null, sort_order: i, stations: p.stations ?? null, image_path: p.imagePath ?? null,
      deleted_at: null, updated_at: new Date().toISOString(),
    }));
    const { error } = await db.from("places").upsert(rows, { onConflict: "tenant_id,directory,external_id" });
    if (error) return new Response(`places ${dir}: ${error.message}`, { status: 500 });
    const ids = rows.map((r: any) => r.external_id);
    await db.from("places").update({ deleted_at: new Date().toISOString(), updated_at: new Date().toISOString() })
      .eq("tenant_id", tenant.id).eq("directory", dir).is("deleted_at", null).not("external_id", "in", `(${ids.map((x: string) => `"${x}"`).join(",")})`);
    report[dir] = rows.length;
  }

  // Haltestellen
  const stopsRaw = await get("bus-stops.json");
  if (stopsRaw) {
    const stops = JSON.parse(new TextDecoder().decode(stopsRaw)).stops ?? [];
    const rows = stops.map((s: any, i: number) => ({ tenant_id: tenant.id, stop_id: s.id, name: s.name, lat: s.latitude, lon: s.longitude, sort_order: i, deleted_at: null, updated_at: new Date().toISOString() }));
    if (rows.length) await db.from("bus_stops").upsert(rows);
    report["bus_stops"] = rows.length;
  }

  // Dateien im Bucket `content`
  for (const name of FILES) {
    const raw = await get(`${name}.json`);
    if (!raw) continue;
    const path = `${slug}/${name}.json`;
    const { error } = await db.storage.from("content").upload(path, raw, { contentType: "application/json", upsert: true });
    if (error) return new Response(`upload ${path}: ${error.message}`, { status: 500 });
    await db.from("content_files").upsert({ tenant_id: tenant.id, name, path, bytes: raw.length, sha256: await sha256(raw), updated_at: new Date().toISOString() });
    report[name] = raw.length;
  }
  return Response.json(report);
});
