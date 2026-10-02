#!/usr/bin/env python3
"""Inhalte für eine neue Region aus OpenStreetMap — für den Skill `new-region-app`.

Aufruf:  python3 tools/region_data.py <region>        liest tools/regions/<region>.json
Ausgabe: tools/out/<slug>/ je Gemeinde
  gastronomie.json, gesundheit.json, freizeit.json, sehenswuerdigkeiten.json, spielplaetze.json,
  fahrradverleih.json, ausfluege.json (leer oder aus "trips"), inselkarte.json,
  bus-stops.json (nur mit "bus"), abfuhr-strassen.json (nur mit "waste"),
  tenant.json (center/bbox für die Tenant-Konfiguration)

Region-Datei:
{
  "region": "juist", "regionName": "Juist",
  "municipalities": [
    {"slug": "juist", "name": "Juist", "relation": 1234567,      # oder "admin_level": "8" + Name
     "bbox": [S, W, N, E],                                       # optional, sonst aus der OSM-Grenze
     "bus": {"default_stop": "009..."},                          # optional, nur VBN-Gebiet
     "waste": {"ort": 5}}                                         # optional, nur appfuhr (Ammerland)
  ],
  "trips": "pfad/zu/ausfluege.json"                              # optional
}
"""
import datetime, json, os, sys

import osm_content as oc

HERE = os.path.dirname(os.path.abspath(__file__))


def main(region):
    path = os.path.join(HERE, "regions", f"{region}.json")
    cfg = json.load(open(path))
    oc.FETCHED = datetime.date.today().isoformat()
    month = datetime.date.today().strftime("%m/%Y")
    osm = f"OpenStreetMap-Mitwirkende (ODbL), Stand {month} · Öffnungszeiten laut OSM, nicht bestätigt"
    trips = json.load(open(os.path.join(HERE, "..", cfg["trips"]))) if cfg.get("trips") else \
        {"source": "", "fetchedAt": oc.FETCHED, "places": []}
    summary = {}
    for m in cfg["municipalities"]:
        s = m["slug"]
        town = {k: v for k, v in m.items() if k in ("name", "relation", "admin_level", "bbox")}
        print("==", m["name"], flush=True)
        bbox, center = oc.boundary_box(town)
        town.setdefault("bbox", bbox)
        oc.save_cache()

        dirs = oc.places_for(s, town); oc.save_cache()
        files = {"gastronomie.json": ("gastro", osm), "gesundheit.json": ("health", osm), "freizeit.json": ("leisure", osm),
                 "sehenswuerdigkeiten.json": ("sights", "Orte: " + osm), "spielplaetze.json": ("playgrounds", f"OpenStreetMap-Mitwirkende (ODbL), Stand {month}")}
        counts = {}
        for fname, (d, src) in files.items():
            oc.write(s, fname, {"source": src, "fetchedAt": oc.FETCHED, "places": dirs[d]})
            counts[d] = len(dirs[d])
        bikes = [{"id": p["id"], "name": p["name"], "teaser": p["teaser"], "phone": p.get("phone"), "email": p.get("email"), "website": p.get("website"),
                  "features": p.get("features", ["Fahrradladen"]),
                  "stations": [{"label": m["name"], "street": p.get("street", ""), "latitude": p["latitude"], "longitude": p["longitude"]}]} for p in dirs["bikes"]]
        oc.write(s, "fahrradverleih.json", {"source": osm, "fetchedAt": oc.FETCHED, "providers": bikes})
        counts["bikes"] = len(bikes)
        oc.write(s, "ausfluege.json", trips)
        counts["trips"] = len(trips.get("places", []))

        oc.write(s, "inselkarte.json", oc.map_for(town)); oc.save_cache()
        if m.get("bus"):
            stops = oc.bus_stops_for(town, m["bus"]["default_stop"]); oc.save_cache()
            oc.write(s, "bus-stops.json", stops)
            counts["bus-stops"] = len(stops["stops"])
        if m.get("waste"):
            town["ort"] = m["waste"]["ort"]
            st = oc.streets_for(town); oc.save_cache()
            oc.write(s, "abfuhr-strassen.json", st)
            counts["streets"] = len(st["streets"])
        oc.write(s, "tenant.json", {"slug": s, "municipality": m["name"], "region": cfg["region"], "center": center, "bbox": town["bbox"]})
        summary[s] = counts
        print("  " + ", ".join(f"{k}: {v}" for k, v in counts.items()), flush=True)
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(sys.argv[1])
