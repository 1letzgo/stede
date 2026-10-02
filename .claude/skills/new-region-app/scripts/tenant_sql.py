#!/usr/bin/env python3
"""Tenants einer Region: SQL für die Migration ausgeben und die Bundle-Datei `tenants.json`
(iOS StedeCore/Resources + Android-Kopie) ergänzen.

Aufruf: python3 tenant_sql.py <region> [--dry-run]
Braucht tools/out/<slug>/tenant.json aus `tools/region_data.py` (center, bbox).
Das SQL schreibt in Produktion — es wird nur ausgegeben; ausführen per Supabase-MCP `apply_migration`
erst nach Bestätigung.
"""
import json, sys

import spec as S

# Backend-Schlüssel (snake_case) → Schlüssel im Bundle (TenantConfig, camelCase)
BUNDLE_KEYS = {"default_station": "defaultStation", "waste_town_id": "wasteTownID", "bus_default_stop": "busDefaultStop", "air_station": "airStation"}


def tenants(spec):
    enabled, places = S.features(spec)
    feats = {k: True for k in enabled}
    feats["places"] = sorted(places)
    out = []
    for m in spec["municipalities"]:
        t = json.load(open(S.path("tools", "out", m["slug"], "tenant.json")))
        config = {"center": m.get("center", t["center"]), "bbox": m.get("bbox", t["bbox"]), "features": feats}
        for key in ("notes", "external"):
            if spec.get(key): config[key] = spec[key]
        config.update(m.get("config", {}))
        out.append({"slug": m["slug"], "name": spec["brand"]["appName"], "municipality": m["name"], "region": spec["region"], "config": config})
    return out


def sql(rows):
    lines = [f"-- Region {rows[0]['region']}: Tenants mit Bausteinen (Skill new-region-app)."]
    for r in rows:
        cfg = json.dumps(r["config"], ensure_ascii=False).replace("'", "''")
        lines.append(
            "insert into tenants (slug, name, municipality, region, center_lat, center_lon, config) values "
            f"('{r['slug']}', '{r['name']}', '{r['municipality']}', '{r['region']}', {r['config']['center'][0]}, {r['config']['center'][1]}, '{cfg}'::jsonb)\n"
            "  on conflict (slug) do update set name = excluded.name, municipality = excluded.municipality, region = excluded.region,\n"
            "  center_lat = excluded.center_lat, center_lon = excluded.center_lon, config = tenants.config || excluded.config, updated_at = now();")
    return "\n".join(lines) + "\n"


def bundle(rows, dry):
    ios = S.path("Packages", "Stede", "Sources", "StedeCore", "Resources", "tenants.json")
    data = [t for t in json.load(open(ios)) if t["slug"] not in {r["slug"] for r in rows}]
    for r in rows:
        e = {"slug": r["slug"], "municipality": r["municipality"], "region": r["region"]}
        for k, v in r["config"].items():
            if k == "events_source" or k == "events_group" or k == "events_search_url":
                continue  # nur für den Server
            e[BUNDLE_KEYS.get(k, k)] = v
        data.append(e)
    text = json.dumps(data, ensure_ascii=False, indent=1)
    S.write_if_changed(ios, text, dry)
    S.write_if_changed(S.path("android", "app", "src", "main", "assets", "tenants.json"), text, dry)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        raise SystemExit(__doc__)
    spec = S.load(args[0])
    rows = tenants(spec)
    print(sql(rows))
    bundle(rows, "--dry-run" in sys.argv)
