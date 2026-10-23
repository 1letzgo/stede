// Live-Fahrten der Fähre (Loog: api.langeoog.de) je Tag in `ferry_days` — die Apps fragen nur
// noch unsere Tabelle, nie die API. Je Tenant mit config.ferry.routes (ohne type: pdf).
// Cron `sync-ferry` alle 5 Minuten für heute und morgen (?from=0&days=2), stündlich für die
// Tage danach (?from=2&days=30). Nur echte Änderungen werden geschrieben.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1";

async function sha(text: string): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  return Array.from(d, (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Kalendertag in Europe/Berlin plus `offset` Tage, als YYYY-MM-DD. */
function berlinDay(offset: number): string {
  const d = new Date(Date.now() + offset * 86400_000);
  return new Intl.DateTimeFormat("sv-SE", { timeZone: "Europe/Berlin" }).format(d);
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const from = Number(url.searchParams.get("from") ?? 0);
  const days = Number(url.searchParams.get("days") ?? 2);
  const { data: tenants } = await admin.from("tenants").select("id, slug, config").not("config->ferry", "is", null);
  const results: Record<string, unknown> = {};
  for (const t of tenants ?? []) {
    const ferry = t.config.ferry ?? {};
    if (ferry.type === "pdf" || !Array.isArray(ferry.routes) || !ferry.routes.length) continue;
    const run = await admin.from("job_runs").insert({ job: "sync-ferry", tenant_id: t.id }).select("id").single();
    let changed = 0, failed = 0;
    for (let offset = from; offset < from + days; offset++) {
      const day = berlinDay(offset);
      try {
        const byId = new Map<number, unknown>();
        for (const route of ferry.routes) {
          const res = await fetch(`https://api.langeoog.de/fahrten/${route}/${day}`, { headers: { "User-Agent": UA }, signal: AbortSignal.timeout(45_000) });
          if (!res.ok) throw new Error(`HTTP ${res.status}`);
          for (const trip of await res.json()) byId.set(trip.fahrtnummer, trip);
        }
        const trips = [...byId.values()].sort((a: any, b: any) => String(a.abfahrt).localeCompare(String(b.abfahrt)));
        const hash = await sha(JSON.stringify(trips));
        const { data: current } = await admin.from("ferry_days").select("sha256").eq("tenant_id", t.id).eq("day", day).maybeSingle();
        if (current?.sha256 === hash) {
          await admin.from("ferry_days").update({ fetched_at: new Date().toISOString() }).eq("tenant_id", t.id).eq("day", day);
          continue;
        }
        const up = await admin.from("ferry_days").upsert({ tenant_id: t.id, day, trips, sha256: hash, fetched_at: new Date().toISOString() }, { onConflict: "tenant_id,day" });
        if (up.error) throw up.error;
        changed++;
      } catch (e) {
        failed++;
        console.error(t.slug, day, String(e));
      }
    }
    // Vergangene Tage behalten wir nur kurz.
    await admin.from("ferry_days").delete().eq("tenant_id", t.id).lt("day", berlinDay(-3));
    results[t.slug] = { changed, failed };
    if (run.data) await admin.from("job_runs").update({ finished_at: new Date().toISOString(), ok: failed === 0, rows: changed, message: failed ? `${failed} Tage fehlgeschlagen` : null }).eq("id", run.data.id);
  }
  return new Response(JSON.stringify(results), { headers: { "Content-Type": "application/json" } });
});
