// Gezeiten-Vorausberechnung des BSH je Tenant mit config.tides.bshnr (Loog 781P, spoog 779P …).
// Gekürzt wie die Bundle-Datei der App (nur hwnw_prediction: timestamp, height, type, phase),
// abgelegt unter config.tides.path (Standard <slug>/tides-<bshnr>.json); content_files.updated_at
// springt nur bei Änderung. Täglich per Cron `sync-tides`.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1";

async function sha(text: string): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  return Array.from(d, (b) => b.toString(16).padStart(2, "0")).join("");
}

async function stations() {
  const { data } = await admin.from("tenants").select("id, slug, config").not("config->tides", "is", null);
  return (data ?? []).map((t) => {
    const tides = t.config.tides;
    // Ältere Konfiguration ohne bshnr: Nummer aus dem Dateinamen („tides-781P.json“).
    const bshnr = tides.bshnr ?? /tides-(\w+)\.json$/.exec(tides.path ?? "")?.[1];
    return bshnr ? { id: t.id, slug: t.slug, bshnr, path: tides.path ?? `${t.slug}/tides-${bshnr}.json`, name: tides.file ?? "tides" } : null;
  }).filter((s) => s !== null);
}

Deno.serve(async () => {
  const results: Record<string, unknown> = {};
  for (const { id, slug, bshnr, path, name } of await stations()) {
    const run = await admin.from("job_runs").insert({ job: "sync-tides", tenant_id: id }).select("id").single();
    try {
      const res = await fetch(`https://gezeiten.bsh.de/data/DE__${bshnr}_tides.json`, { headers: { "User-Agent": UA } });
      if (!res.ok) throw new Error(`BSH HTTP ${res.status}`);
      const raw = await res.json();
      const years = (raw.years ?? []).map((entry: Record<string, any>) => Object.fromEntries(Object.entries(entry).map(([year, v]) => [year, {
        hwnw_prediction: {
          level: v?.hwnw_prediction?.level,
          data: (v?.hwnw_prediction?.data ?? []).map((e: any) => ({ timestamp: e.timestamp, height: e.height, type: e.type, phase: e.phase })),
        },
      }]))).filter((y: Record<string, any>) => Object.values(y).some((v: any) => v.hwnw_prediction.data.length));
      if (!years.length) throw new Error("keine Vorhersage im BSH-Feed");
      const body = JSON.stringify({ station_name: raw.station_name, bshnr: raw.bshnr, latitude: raw.latitude, longitude: raw.longitude, pegelonline_uuid: raw.pegelonline_uuid, years });
      const hash = await sha(body);
      const { data: current } = await admin.from("content_files").select("sha256").eq("tenant_id", id).eq("name", name).maybeSingle();
      let changed = false;
      if (current?.sha256 !== hash) {
        const up = await admin.storage.from("content").upload(path, new Blob([body], { type: "application/json" }), { upsert: true, contentType: "application/json" });
        if (up.error) throw up.error;
        const row = await admin.from("content_files").upsert({ tenant_id: id, name, path, bytes: body.length, sha256: hash, updated_at: new Date().toISOString() }, { onConflict: "tenant_id,name" });
        if (row.error) throw row.error;
        changed = true;
      }
      const events = years.reduce((n: number, y: Record<string, any>) => n + Object.values(y).reduce((m: number, v: any) => m + v.hwnw_prediction.data.length, 0), 0);
      results[slug] = { events, changed };
      if (run.data) await admin.from("job_runs").update({ finished_at: new Date().toISOString(), ok: true, rows: events, message: changed ? "updated" : "unchanged" }).eq("id", run.data.id);
    } catch (e) {
      results[slug] = { error: String(e) };
      if (run.data) await admin.from("job_runs").update({ finished_at: new Date().toISOString(), ok: false, message: String(e) }).eq("id", run.data.id);
    }
  }
  return new Response(JSON.stringify(results), { headers: { "Content-Type": "application/json" } });
});
