#!/usr/bin/env python3
"""Erzeugt die Inhalte je Ammerland-Gemeinde (09/2026) — wiederverwendbar zum Auffrischen.

Aufruf:  python3 tools/ammerland_data.py [slug ...]      (ohne Angabe: alle fünf neuen Gemeinden)
Ausgabe: tools/out/<slug>/ mit
  gastronomie.json, gesundheit.json, freizeit.json, sehenswuerdigkeiten.json, spielplaetze.json,
  fahrradverleih.json, ehrenamt.json, ausfluege.json   (Schema wie die Westersteder Bundle-Dateien)
  inselkarte.json (Offline-Karte ohne Gebäude), bus-stops.json, abfuhr-strassen.json

Die Arbeit macht `osm_content.py`; neue Regionen laufen über `region_data.py`.
Westerstede (`stede`) behält seine handgepflegten Dateien.
"""
import json, os, sys

from osm_content import *  # noqa: F401,F403

TOWNS = {
    "bad-zwischenahn": {"name": "Bad Zwischenahn", "ort": 2, "bbox": [53.12, 7.88, 53.28, 8.18]},
    "edewecht": {"name": "Edewecht", "ort": 3, "bbox": [53.05, 7.83, 53.18, 8.15]},
    "rastede": {"name": "Rastede", "ort": 4, "bbox": [53.18, 8.10, 53.36, 8.32]},
    "wiefelstede": {"name": "Wiefelstede", "ort": 6, "bbox": [53.17, 8.02, 53.35, 8.21]},
    "apen": {"name": "Apen", "ort": 1, "bbox": [53.15, 7.69, 53.27, 7.88]},
}


def main(slugs):
    root = os.path.join(os.path.dirname(__file__), "..", "Packages", "Stede", "Sources", "StedeCore", "Resources")
    trips = json.load(open(os.path.join(root, "ausfluege.json")))
    defaults = {"bad-zwischenahn": "009006433", "edewecht": "009022853", "rastede": "009075805", "wiefelstede": "009099164", "apen": "009003061"}
    osm = "OpenStreetMap-Mitwirkende (ODbL), Stand 09/2026"
    for s in slugs:
        town = TOWNS[s]
        print("==", town["name"], flush=True)
        dirs = places_for(s, town); save_cache()
        files = {"gastronomie.json": ("gastro", osm), "gesundheit.json": ("health", osm), "freizeit.json": ("leisure", osm),
                 "sehenswuerdigkeiten.json": ("sights", "Orte: " + osm), "spielplaetze.json": ("playgrounds", "OpenStreetMap-Mitwirkende (ODbL), Stand 09/2026")}
        for fname, (d, src) in files.items():
            write(s, fname, {"source": src, "fetchedAt": FETCHED, "places": dirs[d]})
            print(f"  {fname}: {len(dirs[d])}", flush=True)
        bikes = [{"id": p["id"], "name": p["name"], "teaser": p["teaser"], "phone": p.get("phone"), "email": p.get("email"), "website": p.get("website"),
                  "features": p.get("features", ["Fahrradladen"]),
                  "stations": [{"label": town["name"], "street": p.get("street", ""), "latitude": p["latitude"], "longitude": p["longitude"]}]} for p in dirs["bikes"]]
        write(s, "fahrradverleih.json", {"source": osm, "fetchedAt": FETCHED, "providers": bikes})
        print(f"  fahrradverleih.json: {len(bikes)}", flush=True)
        vol = volunteer_for(s); save_cache()
        write(s, "ehrenamt.json", {"source": "Ehrenamtskarte Niedersachsen/Bremen · freiwilligenserver.de (Stand 25.09.2026) · Kartendaten © OpenStreetMap",
                                   "fetchedAt": FETCHED, "places": vol})
        print(f"  ehrenamt.json: {len(vol)}", flush=True)
        write(s, "ausfluege.json", trips)
        write(s, "inselkarte.json", map_for(town)); save_cache()
        print("  inselkarte.json", flush=True)
        stops = bus_stops_for(town, defaults[s]); save_cache()
        write(s, "bus-stops.json", stops)
        print(f"  bus-stops.json: {len(stops['stops'])}", flush=True)
        st = streets_for(town); save_cache()
        write(s, "abfuhr-strassen.json", st)
        print(f"  abfuhr-strassen.json: {len(st['streets'])}", flush=True)


if __name__ == "__main__":
    main(sys.argv[1:] or list(TOWNS))
