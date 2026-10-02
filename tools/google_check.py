#!/usr/bin/env python3
"""OSM-Orte gegen Google Places prüfen — geschlossen? Öffnungszeiten? Für den Skill `new-region-app`.

Aufruf:  GOOGLE_PLACES_API_KEY=… python3 tools/google_check.py <slug> [--apply] [--hours] [--limit=N]
Liest:   tools/out/<slug>/gastronomie.json, gesundheit.json, freizeit.json, fahrradverleih.json
Schreibt: tools/out/<slug>/google-report.json (immer) und mit --apply die JSONs selbst:
  - CLOSED_PERMANENTLY  → Ort fliegt raus
  - CLOSED_TEMPORARILY  → hours = „Derzeit geschlossen“
  - abweichende Zeiten  → nur mit --hours werden Googles Zeiten übernommen, sonst nur im Bericht

Abgleich je Ort per Text Search (Places API New) mit Name + Straße + Ort und Location-Bias 300 m um die
OSM-Koordinate; Treffer zählt nur bei ≤ 150 m Abstand und ähnlichem Namen. Kein Treffer → OSM bleibt.
Antworten landen im Cache tools/out/google-cache.json (Wiederholungen kosten nichts).
"""
import difflib, json, os, re, sys, urllib.request

import osm_content as oc

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "out", "google-cache.json")
URL = "https://places.googleapis.com/v1/places:searchText"
FIELDS = "places.id,places.displayName,places.formattedAddress,places.location,places.businessStatus,places.regularOpeningHours"
FILES = {"gastronomie.json": "places", "gesundheit.json": "places", "freizeit.json": "places", "fahrradverleih.json": "providers"}
DAY = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
ORDER = [1, 2, 3, 4, 5, 6, 0]  # Mo … So

_cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}


def search(query, lat, lon, key):
    ck = f"{query}|{lat:.5f}|{lon:.5f}"
    if ck not in _cache:
        body = {"textQuery": query, "languageCode": "de", "regionCode": "DE", "maxResultCount": 5,
                "locationBias": {"circle": {"center": {"latitude": lat, "longitude": lon}, "radius": 300.0}}}
        req = urllib.request.Request(URL, json.dumps(body).encode(), {"Content-Type": "application/json",
                                     "X-Goog-Api-Key": key, "X-Goog-FieldMask": FIELDS})
        _cache[ck] = json.load(urllib.request.urlopen(req, timeout=30)).get("places", [])
        json.dump(_cache, open(CACHE, "w"))
    return _cache[ck]


def norm(s):
    s = s.lower().replace("ß", "ss")
    s = re.sub(r"\b(restaurant|café|cafe|gaststätte|hotel|bäckerei|apotheke|dr\.?|med\.?|praxis|gmbh|&|und)\b", " ", s)
    return re.sub(r"[^a-z0-9äöü]+", " ", s).strip()


def similar(a, b):
    a, b = norm(a), norm(b)
    return 1.0 if a and (a in b or b in a) else difflib.SequenceMatcher(None, a, b).ratio()


def match(p, town, key):
    lat, lon = p.get("latitude"), p.get("longitude")
    if lat is None:  # Fahrradverleih: Koordinate in der ersten Station
        st = (p.get("stations") or [{}])[0]
        lat, lon, street = st.get("latitude"), st.get("longitude"), st.get("street", "")
    else:
        street = p.get("street", "")
    if lat is None:
        return None
    best = None
    for g in search(" ".join(x for x in (p["name"], street, town) if x), lat, lon, key):
        loc = g.get("location", {})
        d = oc.dist((lat, lon), (loc.get("latitude", 0), loc.get("longitude", 0)))
        s = similar(p["name"], g.get("displayName", {}).get("text", ""))
        if d <= 150 and s >= 0.6 and (best is None or s > best[0]):
            best = (s, d, g)
    return best


def hhmm(t):
    h, m = t.get("hour", 0), t.get("minute", 0)
    return f"{h}" if m == 0 else f"{h}:{m:02d}"


def hours_from(oh):
    """Google-Perioden → „Mo-Fr 9–18 Uhr · Sa 9–13 Uhr“ wie die OSM-Zeiten in der App."""
    periods = (oh or {}).get("periods") or []
    if not periods:
        return None
    if len(periods) == 1 and "close" not in periods[0]:
        return "Rund um die Uhr geöffnet"
    days = {d: [] for d in range(7)}
    for pr in periods:
        o, c = pr["open"], pr.get("close", {"hour": 0, "minute": 0})
        days[o["day"]].append(f"{hhmm(o)}–{hhmm(c)}")
    parts, i = [], 0
    while i < 7:
        d = ORDER[i]
        j = i
        while j + 1 < 7 and days[ORDER[j + 1]] == days[d]:
            j += 1
        if days[d]:
            span = DAY[d] if i == j else f"{DAY[d]}-{DAY[ORDER[j]]}"
            parts.append(f"{span} {', '.join(days[d])} Uhr")
        i = j + 1
    return " · ".join(parts) or None


def main(slug, apply=False, take_hours=False, limit=None):
    key = os.environ.get("GOOGLE_PLACES_API_KEY")
    if not key:
        raise SystemExit("GOOGLE_PLACES_API_KEY fehlt (Places API (New) im Google-Cloud-Projekt aktivieren).")
    folder = os.path.join(HERE, "out", slug)
    tenant = json.load(open(os.path.join(folder, "tenant.json")))
    town = tenant.get("municipality", slug)
    report = {"closed": [], "temporarily": [], "hours": [], "unmatched": [], "checked": 0}
    for fname, listkey in FILES.items():
        path = os.path.join(folder, fname)
        if not os.path.exists(path):
            continue
        data = json.load(open(path))
        keep = []
        for p in data.get(listkey, []):
            if limit is not None and report["checked"] >= limit:
                keep.append(p); continue
            report["checked"] += 1
            m = match(p, town, key)
            if not m:
                report["unmatched"].append({"file": fname, "id": p["id"], "name": p["name"]})
                keep.append(p); continue
            g = m[2]
            entry = {"file": fname, "id": p["id"], "name": p["name"], "google": g.get("displayName", {}).get("text"),
                     "address": g.get("formattedAddress"), "distance": round(m[1])}
            status = g.get("businessStatus")
            if status == "CLOSED_PERMANENTLY":
                report["closed"].append(entry)
                continue  # nicht übernehmen
            if status == "CLOSED_TEMPORARILY":
                report["temporarily"].append(entry)
                p["hours"] = "Derzeit geschlossen"
            elif "places" == listkey:
                gh = hours_from(g.get("regularOpeningHours"))
                if gh and gh != p.get("hours"):
                    report["hours"].append({**entry, "osm": p.get("hours"), "googleHours": gh})
                    if take_hours:
                        p["hours"] = gh
            keep.append(p)
        if apply:
            data[listkey] = keep
            oc.write(slug, fname, data)
    json.dump(report, open(os.path.join(folder, "google-report.json"), "w"), ensure_ascii=False, indent=1)
    print(f"{slug}: {report['checked']} geprüft · {len(report['closed'])} dauerhaft geschlossen · "
          f"{len(report['temporarily'])} vorübergehend geschlossen · {len(report['hours'])} Zeiten abweichend · "
          f"{len(report['unmatched'])} ohne Treffer" + ("" if apply else " (Probelauf, --apply schreibt)"))
    for e in report["closed"]:
        print(f"  ✕ {e['name']} ({e['file']}) = {e['google']}, {e['address']}")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        raise SystemExit(__doc__)
    lim = next((int(a.split("=")[1]) for a in sys.argv if a.startswith("--limit=")), None)
    main(args[0], apply="--apply" in sys.argv, take_hours="--hours" in sys.argv, limit=lim)
