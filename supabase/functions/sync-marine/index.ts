// Wind und Seegang je Insel aus den DWD-Seegangsmodellen, die auch marineforecast.bsh.de zeigt
// (CWAM-Küstenmodell: Wind 10 m, Richtung, signifikante Wellenhöhe). Je Tenant mit
// config.marine = {lat, lon} (Seepunkt vor der Insel) eine WMS-GetFeatureInfo-Abfrage über die
// ganze Vorhersage je Größe; Ergebnis in `marine_forecasts`. Stündlich per Cron `sync-marine`,
// die Apps lesen nur die Tabelle.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const BASE = "https://maps.dwd.de/geoserver/dwd";
const LAYERS = {
  wind_speed: "Cwam_reg0013x0008_fd_sl_SP10M",
  wind_direction: "Cwam_reg0013x0008_fd_sl_DD10M",
  wave_height: "Cwam_reg0013x0008_fd_sl_SWH",
} as const;

type Series = Map<string, { value: number; ref: string }>;

/** Zeitraum der aktuellen Vorhersage aus GetCapabilities („start/ende/PT1H“). */
async function extent(layer: string): Promise<[Date, Date]> {
  const res = await fetch(`${BASE}/${layer}/ows?service=WMS&version=1.3.0&request=GetCapabilities`);
  if (!res.ok) throw new Error(`${layer} Capabilities HTTP ${res.status}`);
  const m = /<Dimension name="time"[^>]*>([^<]+)</.exec(await res.text());
  const [start, end] = (m?.[1] ?? "").split("/");
  if (!start || !end) throw new Error(`${layer}: kein Zeitraum`);
  return [new Date(start), new Date(end)];
}

/** Alle Zeitschritte einer Größe am Punkt, von vor zwei Stunden bis zum Ende der Vorhersage. */
async function series(layer: string, lat: number, lon: number): Promise<Series> {
  const [start, end] = await extent(layer);
  const from = new Date(Math.max(start.getTime(), Date.now() - 2 * 3600_000));
  from.setUTCMinutes(0, 0, 0);
  const to = end;
  const d = 0.02;
  const params = new URLSearchParams({
    service: "WMS", version: "1.1.1", request: "GetFeatureInfo", layers: layer, query_layers: layer, srs: "EPSG:4326",
    bbox: `${lon - d},${lat - d},${lon + d},${lat + d}`, width: "5", height: "5", x: "2", y: "2",
    info_format: "application/json", feature_count: "500", time: `${from.toISOString()}/${to.toISOString()}`,
  });
  const res = await fetch(`${BASE}/${layer}/ows?${params}`);
  const text = await res.text();
  if (!res.ok || text.startsWith("<")) throw new Error(`${layer}: ${text.slice(0, 200)}`);
  const json = JSON.parse(text);
  const out: Series = new Map();
  for (const f of json.features ?? []) {
    const p = f.properties ?? {};
    const value = Object.entries(p).find(([k, v]) => k !== "TIME" && k !== "REFERENCE_TIME" && typeof v === "number")?.[1] as number | undefined;
    if (value === undefined || !p.TIME) continue;
    out.set(new Date(p.TIME).toISOString(), { value, ref: p.REFERENCE_TIME });
  }
  return out;
}

Deno.serve(async () => {
  const { data: tenants } = await admin.from("tenants").select("id, slug, config").not("config->marine", "is", null);
  const results: Record<string, unknown> = {};
  for (const t of tenants ?? []) {
    const { lat, lon } = t.config.marine ?? {};
    if (typeof lat !== "number" || typeof lon !== "number") continue;
    const run = await admin.from("job_runs").insert({ job: "sync-marine", tenant_id: t.id }).select("id").single();
    try {
      const [speed, dir, wave] = await Promise.all([
        series(LAYERS.wind_speed, lat, lon), series(LAYERS.wind_direction, lat, lon), series(LAYERS.wave_height, lat, lon),
      ]);
      const rows = [...speed.keys()].sort().map((ts) => ({
        tenant_id: t.id, ts,
        wind_speed: speed.get(ts)?.value ?? null,
        wind_direction: dir.get(ts)?.value ?? null,
        // Werte nahe null heißen: Punkt liegt auf Land/Watt — dann lieber keine Angabe.
        wave_height: (wave.get(ts)?.value ?? 0) > 0.01 ? wave.get(ts)!.value : null,
        reference_time: speed.get(ts)?.ref ?? null,
      }));
      if (!rows.length) throw new Error("keine Vorhersage am Punkt");
      const up = await admin.from("marine_forecasts").upsert(rows, { onConflict: "tenant_id,ts" });
      if (up.error) throw up.error;
      // Alte Stunden wegräumen.
      await admin.from("marine_forecasts").delete().eq("tenant_id", t.id).lt("ts", new Date(Date.now() - 86400_000).toISOString());
      results[t.slug] = { rows: rows.length };
      if (run.data) await admin.from("job_runs").update({ finished_at: new Date().toISOString(), ok: true, rows: rows.length }).eq("id", run.data.id);
    } catch (e) {
      results[t.slug] = { error: String(e) };
      if (run.data) await admin.from("job_runs").update({ finished_at: new Date().toISOString(), ok: false, message: String(e) }).eq("id", run.data.id);
    }
  }
  return new Response(JSON.stringify(results), { headers: { "Content-Type": "application/json" } });
});
