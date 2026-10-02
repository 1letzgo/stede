// Wasserstände von PEGELONLINE (WSV) in die Tabelle water_levels übernehmen: 10-Minuten-Mittel.
// Pegel = config.tides.gauge aller Tenants (Langeoog, Spiekeroog …). Alle 10 Minuten per Cron
// `sync-water-levels`; beim ersten Lauf je Pegel die letzten 31 Tage, danach 6 Stunden. Älter als 32 Tage wird gelöscht.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const BUCKET = 10 * 60 * 1000;

async function stations(): Promise<string[]> {
  const { data } = await admin.from("tenants").select("config").not("config->tides", "is", null);
  return [...new Set((data ?? []).map((t) => t.config?.tides?.gauge).filter((g): g is string => typeof g === "string" && g.length > 0))];
}

Deno.serve(async () => {
  const results: Record<string, unknown> = {};
  for (const station of await stations()) {
    try {
      const { count } = await admin.from("water_levels").select("ts", { count: "exact", head: true }).eq("station", station);
      const span = count ? "PT6H" : "P31D";
      const res = await fetch(`https://www.pegelonline.wsv.de/webservices/rest-api/v2/stations/${station}/W/measurements.json?start=${span}`);
      if (!res.ok) throw new Error(`PEGELONLINE HTTP ${res.status}`);
      const items: { timestamp: string; value: number | string }[] = await res.json();
      const buckets = new Map<number, { sum: number; n: number }>();
      for (const it of items) {
        const v = Number(it.value);
        if (!Number.isFinite(v)) continue;
        const key = Math.floor(new Date(it.timestamp).getTime() / BUCKET) * BUCKET;
        const b = buckets.get(key) ?? { sum: 0, n: 0 };
        b.sum += v; b.n += 1; buckets.set(key, b);
      }
      const rows = [...buckets].map(([key, b]) => ({ station, ts: new Date(key).toISOString(), value: Math.round((b.sum / b.n) * 10) / 10 }));
      for (let i = 0; i < rows.length; i += 1000) {
        const { error } = await admin.from("water_levels").upsert(rows.slice(i, i + 1000), { onConflict: "station,ts" });
        if (error) throw error;
      }
      const cutoff = new Date(Date.now() - 32 * 24 * 3600 * 1000).toISOString();
      await admin.from("water_levels").delete().eq("station", station).lt("ts", cutoff);
      results[station] = { rows: rows.length, span };
    } catch (e) {
      results[station] = { error: String(e) };
    }
  }
  return new Response(JSON.stringify(results), { headers: { "Content-Type": "application/json" } });
});
