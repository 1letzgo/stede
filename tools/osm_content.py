#!/usr/bin/env python3
"""OSM-Inhalte für eine Gemeinde — Bibliothek für `ammerland_data.py` (Ammerland, 09/2026) und
`region_data.py` (neue Regionen, Skill `new-region-app`).

Eine Gemeinde ist ein dict: {"name", "bbox": [S, W, N, E], optional "relation" (OSM-Relations-ID der Grenze),
"admin_level" (Standard 8), "ort" (appfuhr-Ort, nur Ammerland)}.
Erzeugt Orte (`places_for`), Offline-Karte (`map_for`), VBN-Haltestellen (`bus_stops_for`),
appfuhr-Straßen (`streets_for`), Ehrenamtskarte Ammerland (`volunteer_for`).

Quellen: OpenStreetMap (Overpass, Nominatim für fehlende Straßen und Adressen), VBN-Haltestellensuche,
appfuhr.de (Straßen/Abschnitte), Ehrenamtskarte-PDF des Landkreises (von Hand übertragen).
"""
import json, math, os, re, sys, time, unicodedata, urllib.parse, urllib.request

UA = "stede-app/1.0 (goletz@gmail.com)"
OUT = os.path.join(os.path.dirname(__file__), "out")
CACHE = os.path.join(os.path.dirname(__file__), "out", "cache.json")
FETCHED = "2026-09-26"

# ---------------------------------------------------------------- Netz

_cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
_last = {}


def get(url, data=None, pause=0.0, host_key=None, raw=False):
    key = url + ("|" + data if data else "")
    if key in _cache:
        return _cache[key]
    if host_key and pause:
        wait = pause - (time.time() - _last.get(host_key, 0))
        if wait > 0:
            time.sleep(wait)
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, data=data.encode() if data else None, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=180) as r:
                body = r.read().decode("utf-8", "replace")
            break
        except Exception as e:  # Overpass ist gelegentlich überlastet
            if attempt == 3:
                raise
            time.sleep(10 * (attempt + 1))
    if host_key:
        _last[host_key] = time.time()
    _cache[key] = body
    return body


def save_cache():
    os.makedirs(OUT, exist_ok=True)
    json.dump(_cache, open(CACHE, "w"))


def overpass(q):
    return json.loads(get("https://overpass-api.de/api/interpreter", data="data=" + urllib.parse.quote(q), pause=2, host_key="overpass"))["elements"]


def nominatim(path, **params):
    params["format"] = "jsonv2"
    return json.loads(get("https://nominatim.openstreetmap.org/" + path + "?" + urllib.parse.urlencode(params), pause=1.1, host_key="nominatim"))

# ---------------------------------------------------------------- Hilfen


def area_clause(town):
    """Overpass-Gebiet der Gemeinde: per Relations-ID oder Verwaltungsgrenze mit Namen."""
    if town.get("relation"):
        return f'area(id:{3600000000 + int(town["relation"])})->.a;'
    return f'area["boundary"="administrative"]["admin_level"="{town.get("admin_level", "8")}"]["name"="{town["name"]}"]->.a;'


def boundary_box(town):
    """[S, W, N, E] und Mittelpunkt [lat, lon] der Gemeindegrenze aus OSM."""
    sel = f'relation({town["relation"]})' if town.get("relation") else \
        f'relation["boundary"="administrative"]["admin_level"="{town.get("admin_level", "8")}"]["name"="{town["name"]}"]'
    els = overpass(f"[out:json][timeout:60];{sel};out bb;")
    if not els:
        raise SystemExit(f"Keine Grenze für {town['name']} gefunden — Relation-ID angeben.")
    b = els[0]["bounds"]
    bbox = [round(b["minlat"], 3), round(b["minlon"], 3), round(b["maxlat"], 3), round(b["maxlon"], 3)]
    return bbox, [round((bbox[0] + bbox[2]) / 2, 5), round((bbox[1] + bbox[3]) / 2, 5)]


def slug(s):
    s = s.lower().replace("ß", "ss").replace("ä", "ae").replace("ö", "oe").replace("ü", "ue")
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")[:60]


def dist(a, b):
    return math.hypot((a[0] - b[0]) * 111000, (a[1] - b[1]) * 67000)


DAYS = {"Mo": "Mo", "Tu": "Di", "We": "Mi", "Th": "Do", "Fr": "Fr", "Sa": "Sa", "Su": "So", "PH": "Feiertag", "off": "geschlossen", "closed": "geschlossen"}


def hours_de(oh):
    if not oh:
        return None
    return re.sub(r"\b(Mo|Tu|We|Th|Fr|Sa|Su|PH|off|closed)\b", lambda m: DAYS[m.group(1)], oh).replace(";", ",")


CUISINE = {"italian": "italienische Küche", "pizza": "Pizza", "greek": "griechische Küche", "german": "deutsche Küche", "regional": "regionale Küche",
           "chinese": "chinesische Küche", "asian": "asiatische Küche", "turkish": "türkische Küche", "kebab": "Döner", "burger": "Burger",
           "indian": "indische Küche", "vietnamese": "vietnamesische Küche", "thai": "thailändische Küche", "sushi": "Sushi", "japanese": "japanische Küche",
           "steak_house": "Steaks", "fish": "Fisch", "seafood": "Fisch", "mexican": "mexikanische Küche", "spanish": "spanische Küche",
           "croatian": "kroatische Küche", "balkan": "Balkanküche", "ice_cream": "Eis", "coffee_shop": "Kaffee", "cake": "Kuchen", "sandwich": "Snacks"}


def cuisine_text(tags):
    parts = [CUISINE[c.strip()] for c in (tags.get("cuisine") or "").split(";") if c.strip() in CUISINE]
    return " – " + ", ".join(dict.fromkeys(parts)) if parts else ""

# ---------------------------------------------------------------- Einordnung


def classify(t):
    """(Verzeichnis, Art) oder None."""
    a, s, h, l, tour, hist = t.get("amenity"), t.get("shop"), t.get("healthcare"), t.get("leisure"), t.get("tourism"), t.get("historic")
    if t.get("access") in ("private", "no"):
        return None
    if a == "restaurant": return ("gastro", "Restaurant")
    if a == "cafe": return ("gastro", "Café")
    if a == "ice_cream": return ("gastro", "Eiscafé")
    if a == "fast_food": return ("gastro", "Imbiss")
    if a in ("bar", "pub", "biergarten"): return ("gastro", "Bar")
    if s == "bakery": return ("gastro", "Bäckerei")
    if s == "chemist": return ("gastro", "Drogerie")
    if s == "bicycle": return ("bikes", "Fahrrad")
    if s in ("supermarket", "convenience", "kiosk", "florist", "garden_centre", "books", "farm", "butcher", "greengrocer", "deli", "beverages", "department_store"):
        return ("gastro", "Einkaufen")
    if a == "pharmacy" or h == "pharmacy": return ("health", "Apotheke")
    if a == "dentist" or h == "dentist": return ("health", "Zahnarzt")
    if a in ("hospital", "clinic") or h in ("hospital", "clinic"): return ("health", "Klinik")
    if a == "veterinary": return ("health", "Tierarzt")
    if a == "doctors" or h == "doctor":
        spec = (t.get("healthcare:speciality") or "general").split(";")[0]
        return ("health", "Allgemeinmedizin" if spec in ("general", "general_practitioner", "family_medicine", "internal") else "Facharzt")
    if h in ("physiotherapist", "occupational_therapist", "speech_therapist", "psychotherapist", "podiatrist", "nurse", "rehabilitation", "counselling"):
        return ("health", "Therapie & Pflege")
    if l in ("swimming_pool", "water_park") or (a == "public_bath"): return ("leisure", "Bad")
    if re.search(r"Schul|Turnhalle|Schützen|Schieß|Königreichssaal|Gedenk|Ehrenmal|Kriegerdenkmal|^Privat|hügel", t.get("name") or ""):
        return None
    if hist == "archaeological_site":
        return None
    if l in ("sports_centre", "stadium", "sports_hall") and ("swimming" in (t.get("sport") or "") or re.search(r"bad\b|Bad$|Hallenbad|Freibad|Wellenbad", t.get("name") or "")):
        return ("leisure", "Bad")
    if l in ("sports_centre", "stadium", "horse_riding", "fitness_centre", "golf_course", "ice_rink", "sports_hall"): return ("leisure", "Sport")
    if l in ("miniature_golf", "trampoline_park", "escape_game") or tour in ("zoo", "theme_park"): return ("leisure", "Spiel & Familie")
    if a in ("library", "theatre", "arts_centre", "cinema") or tour in ("museum", "gallery"): return ("leisure", "Kultur")
    if l == "playground": return ("playgrounds", "Spielplatz")
    if l == "pitch" and "skateboard" in (t.get("sport") or ""): return ("playgrounds", "Skaterplatz")
    if tour in ("attraction", "viewpoint") or hist in ("castle", "manor", "windmill", "watermill", "church", "monument", "archaeological_site", "building") \
            or t.get("man_made") == "windmill" or (a == "place_of_worship" and t.get("religion") == "christian") or l in ("park", "garden"):
        return ("sights", "Sehenswürdigkeiten")
    return None


def sight_word(t):
    if t.get("historic") == "castle": return "Schloss"
    if t.get("historic") == "manor": return "Gutshof"
    if t.get("historic") in ("windmill", "watermill") or t.get("man_made") == "windmill": return "Mühle"
    if t.get("amenity") == "place_of_worship" or t.get("historic") == "church": return "Kirche"
    if t.get("tourism") == "viewpoint": return "Aussichtspunkt"
    if t.get("leisure") == "garden": return "Garten"
    if t.get("leisure") == "park": return "Park"
    if t.get("historic") == "monument": return "Denkmal"
    if t.get("historic") == "archaeological_site": return "Bodendenkmal"
    return "Ausflugsziel"


KIND_WORD = {"Allgemeinmedizin": "Hausarztpraxis", "Facharzt": "Facharztpraxis", "Zahnarzt": "Zahnarztpraxis", "Klinik": "Klinik",
             "Therapie & Pflege": "Praxis", "Tierarzt": "Tierarztpraxis", "Bad": "Bad", "Sport": "Sportstätte", "Spiel & Familie": "Freizeitangebot",
             "Kultur": "Kulturort", "Einkaufen": "Geschäft", "Bäckerei": "Bäckerei", "Drogerie": "Drogerie", "Imbiss": "Imbiss", "Bar": "Kneipe/Bar",
             "Café": "Café", "Eiscafé": "Eiscafé", "Restaurant": "Restaurant", "Apotheke": "Apotheke"}

# ---------------------------------------------------------------- Orte


def street_of(tags, lat, lon):
    if tags.get("addr:street"):
        return (tags["addr:street"] + " " + tags.get("addr:housenumber", "")).strip()
    try:
        r = nominatim("reverse", lat=lat, lon=lon, zoom=17, addressdetails=1)
        adr = r.get("address", {})
        road = adr.get("road") or adr.get("pedestrian") or adr.get("footway")
        return ((road or "") + " " + adr.get("house_number", "")).strip() or None
    except Exception:
        return None


def district_of(tags, town):
    for k in ("addr:suburb", "addr:hamlet", "addr:place"):
        if tags.get(k) and tags[k] != town:
            return f"{town}-{tags[k]}"
    return town


def places_for(slug_, town):
    q = f"""[out:json][timeout:180];
{area_clause(town)}
(
  nwr["amenity"~"^(restaurant|cafe|ice_cream|fast_food|bar|pub|biergarten|pharmacy|doctors|dentist|hospital|clinic|veterinary|library|theatre|arts_centre|cinema|place_of_worship|public_bath)$"]["name"](area.a);
  nwr["shop"~"^(bakery|supermarket|convenience|kiosk|florist|garden_centre|books|farm|chemist|butcher|greengrocer|deli|beverages|bicycle|department_store)$"]["name"](area.a);
  nwr["healthcare"]["name"](area.a);
  nwr["leisure"~"^(swimming_pool|water_park|sports_centre|stadium|miniature_golf|park|garden|horse_riding|ice_rink|fitness_centre|golf_course|trampoline_park|sports_hall)$"]["name"](area.a);
  nwr["leisure"="playground"](area.a);
  nwr["leisure"="pitch"]["sport"~"skateboard"](area.a);
  nwr["tourism"~"^(attraction|museum|viewpoint|zoo|theme_park|gallery)$"]["name"](area.a);
  nwr["historic"~"^(castle|manor|monument|church|windmill|watermill|archaeological_site)$"]["name"](area.a);
  nwr["man_made"="windmill"]["name"](area.a);
);
out center tags;"""
    els = overpass(q)
    dirs = {k: [] for k in ("gastro", "health", "leisure", "sights", "playgrounds", "bikes")}
    for e in els:
        t = e.get("tags", {})
        c = classify(t)
        if not c:
            continue
        d, kind = c
        lat = e.get("lat") or e.get("center", {}).get("lat")
        lon = e.get("lon") or e.get("center", {}).get("lon")
        if lat is None:
            continue
        name = (t.get("name") or "").strip(" '\"") or None
        if d == "playgrounds" and not name:
            name = None  # später aus der Straße
        if d != "playgrounds" and not name:
            continue
        # private Gärten/kleine Parks ohne Namen sind schon raus; Kirchen nur mit Namen
        dirs[d].append({"tags": t, "kind": kind, "name": name, "lat": round(lat, 6), "lon": round(lon, 6)})

    result = {}
    for d, items in dirs.items():
        places, ids = [], set()
        for it in items:
            # Dubletten (gleicher Name, <150 m) zusammenlegen
            # Flächen (Parks, Golfplätze) stehen oft mehrfach in OSM — gleicher Name im Umkreis von 1,5 km
            if it["name"] and any(p["name"] == it["name"] and dist((p["latitude"], p["longitude"]), (it["lat"], it["lon"])) < 1500 for p in places):
                continue
            t = it["tags"]
            street = street_of(t, it["lat"], it["lon"])
            name = it["name"] or (f"Spielplatz {street.split(' ')[0]}" if street else "Spielplatz")
            base = slug(name) or "ort"
            pid, n = base, 2
            while pid in ids:
                pid, n = f"{base}-{n}", n + 1
            ids.add(pid)
            ort = district_of(t, town["name"])
            kind = it["kind"]
            if d == "sights":
                teaser = t.get("description") or f"{sight_word(t)} in {ort}."
            elif d == "playgrounds":
                teaser = "Skaterplatz in " + ort + "." if kind == "Skaterplatz" else "Öffentlicher Spielplatz in " + ort + "."
            else:
                teaser = f"{KIND_WORD.get(kind, kind)} in {ort}{cuisine_text(t) if d == 'gastro' else ''}."
            p = {"id": pid, "name": name, "category": kind, "teaser": teaser}
            if street: p["street"] = street
            phone = t.get("phone") or t.get("contact:phone")
            if phone: p["phone"] = phone.split(";")[0].strip()
            mail = t.get("email") or t.get("contact:email")
            if mail: p["email"] = mail.split(";")[0].strip()
            web = t.get("website") or t.get("contact:website")
            if web: p["website"] = web.split(";")[0].strip()
            oh = hours_de(t.get("opening_hours"))
            if oh and d in ("gastro", "health", "leisure"):
                p["hours"] = oh
            p["latitude"], p["longitude"] = it["lat"], it["lon"]
            if d == "bikes":
                p["features"] = ["Fahrradladen"] + (["Verleih"] if t.get("service:bicycle:rental") == "yes" else []) + \
                                (["Werkstatt"] if t.get("service:bicycle:repair") == "yes" else [])
            places.append(p)
        places.sort(key=lambda p: (p["category"], p["name"].lower()))
        result[d] = places
    return result

# ---------------------------------------------------------------- Karte


def dp(pts, tol=0.00004):
    if len(pts) < 3:
        return pts
    (x1, y1), (x2, y2) = pts[0], pts[-1]
    dx, dy = x2 - x1, y2 - y1
    n = math.hypot(dx, dy)
    dmax, idx = 0, 0
    for i in range(1, len(pts) - 1):
        x, y = pts[i]
        d = abs(dy * x - dx * y + x2 * y1 - y2 * x1) / n if n > 0 else math.hypot(x - x1, y - y1)
        if d > dmax:
            dmax, idx = d, i
    return dp(pts[:idx + 1], tol)[:-1] + dp(pts[idx:], tol) if dmax > tol else [pts[0], pts[-1]]


def ring(r):
    m = len(r) // 2
    return dp(r[:m + 1])[:-1] + dp(r[m:])


def stitch(ways):
    rings, ways = [], [w[:] for w in ways if len(w) > 1]
    while ways:
        cur, changed = ways.pop(0), True
        while cur[0] != cur[-1] and changed:
            changed = False
            for i, w in enumerate(ways):
                if w[0] == cur[-1]: cur += w[1:]
                elif w[-1] == cur[-1]: cur += w[::-1][1:]
                elif w[-1] == cur[0]: cur = w[:-1] + cur
                elif w[0] == cur[0]: cur = w[::-1][:-1] + cur
                else: continue
                ways.pop(i); changed = True; break
        if cur[0] == cur[-1] and len(cur) >= 4:
            rings.append(cur)
    return rings


def area(r):
    return abs(sum(r[i][0] * r[i + 1][1] - r[i + 1][0] * r[i][1] for i in range(len(r) - 1))) / 2


def map_for(town):
    s, w, n, e = town["bbox"]
    b = f"({s},{w},{n},{e})"
    q = f"""[out:json][timeout:240];
(
  way["highway"~"^(motorway|motorway_link|trunk|trunk_link|primary|primary_link|secondary|secondary_link|tertiary|tertiary_link|unclassified|residential|living_street|pedestrian)$"]{b};
  way["highway"~"^(footway|cycleway|path|track|bridleway|steps)$"]{b};
  way["railway"="rail"]{b};
  way["waterway"~"^(stream|river|canal|ditch)$"]{b};
  way["natural"="water"]{b}; relation["natural"="water"]{b};
  way["landuse"="forest"]{b}; way["natural"="wood"]{b}; relation["landuse"="forest"]{b}; relation["natural"="wood"]{b};
  way["landuse"~"^(meadow|grass|recreation_ground|village_green|allotments|cemetery)$"]{b};
  way["leisure"~"^(park|garden)$"]{b}; relation["leisure"~"^(park|garden)$"]{b};
  way["landuse"~"^(residential|commercial|industrial|retail)$"]{b}; relation["landuse"~"^(residential|commercial|industrial|retail)$"]{b};
);
out geom;"""
    els = overpass(q)
    geom = lambda g: [[round(p["lon"], 5), round(p["lat"], 5)] for p in g]
    polys = {"settlement": [], "green": [], "wood": [], "water": []}
    lines = {"road": [], "path": [], "rail": [], "stream": []}
    for el in els:
        t = el.get("tags", {})
        h = t.get("highway")
        if h:
            key = "path" if h in ("footway", "cycleway", "path", "track", "bridleway", "steps") else "road"
            g = dp(geom(el.get("geometry", [])))
            if len(g) >= 2: lines[key].append(g)
            continue
        if t.get("railway") == "rail" or t.get("waterway"):
            g = dp(geom(el.get("geometry", [])))
            if len(g) >= 2: lines["rail" if t.get("railway") else "stream"].append(g)
            continue
        key = "water" if t.get("natural") == "water" else "wood" if (t.get("landuse") == "forest" or t.get("natural") == "wood") \
            else "settlement" if t.get("landuse") in ("residential", "commercial", "industrial", "retail") else "green"
        rs = []
        if el["type"] == "way":
            g = geom(el.get("geometry", []))
            if len(g) >= 4 and g[0] == g[-1]: rs = [g]
        else:
            rs = stitch([geom(m["geometry"]) for m in el.get("members", []) if m.get("role") == "outer" and m.get("geometry")])
        for r in rs:
            if area(r) < 2e-8: continue
            sr = ring(r)
            if len(sr) >= 4: polys[key].append(sr)
    result = {"attribution": "© OpenStreetMap-Mitwirkende (ODbL)", "fetchedAt": FETCHED,
              "land": [[[w, s], [e, s], [e, n], [w, n], [w, s]]], "polygons": polys, "buildings": [], "lines": lines}
    coast = coastline(b)
    if coast:
        # Insel: Land ist der Küstenumriss, außerhalb zeichnen die Apps Meer; dazu Watt und Strand.
        result["land"] = coast
        result["sea"] = True
        result["polygons"].update(shore(b))
    return result


def coastline(b):
    """Geschlossene Küstenringe (natural=coastline) im Ausschnitt, sonst [] (Binnenland)."""
    els = overpass(f"[out:json][timeout:120];way[\"natural\"=\"coastline\"]{b};out geom;")
    geom = lambda g: [[round(p["lon"], 5), round(p["lat"], 5)] for p in g]
    rings = [r for r in stitch([geom(el.get("geometry", [])) for el in els]) if len(r) >= 4 and r[0] == r[-1] and area(r) >= 2e-8]
    return [ring(r) for r in rings]


def shore(b):
    """Watt (wetland=tidalflat) und Strand/Sand (natural=beach|sand) als Flächen."""
    els = overpass(f"""[out:json][timeout:180];
(
  way["natural"="wetland"]["wetland"="tidalflat"]{b}; relation["natural"="wetland"]["wetland"="tidalflat"]{b};
  way["natural"~"^(beach|sand)$"]{b}; relation["natural"~"^(beach|sand)$"]{b};
);
out geom;""")
    geom = lambda g: [[round(p["lon"], 5), round(p["lat"], 5)] for p in g]
    out = {"tidalflat": [], "sand": []}
    for el in els:
        key = "tidalflat" if el.get("tags", {}).get("natural") == "wetland" else "sand"
        if el["type"] == "way":
            g = geom(el.get("geometry", []))
            rs = [g] if len(g) >= 4 and g[0] == g[-1] else []
        else:
            rs = stitch([geom(m["geometry"]) for m in el.get("members", []) if m.get("role") == "outer" and m.get("geometry")])
        for r in rs:
            if area(r) < 2e-8: continue
            sr = ring(r)
            if len(sr) >= 4: out[key].append(sr)
    return out

# ---------------------------------------------------------------- Bus


def vbn_search(term):
    body = get("https://fahrplaner.vbn.de/bin/ajax-getstop.exe/dn?getstop=1&REQ0JourneyStopsS0A=1&REQ0JourneyStopsS0G=" + urllib.parse.quote(term),
               pause=0.4, host_key="vbn")
    m = re.search(r"SLs\.sls=(\{.*\});", body)
    return json.loads(m.group(1)).get("suggestions", []) if m else []


def bus_stops_for(town, default_stop):
    q = f"""[out:json][timeout:120];
{area_clause(town)}
node["highway"="bus_stop"]["name"](area.a);
out;"""
    # je Name ein Punkt (Haltestellen haben meist zwei Masten)
    nodes = {}
    for el in overpass(q):
        nodes.setdefault(el["tags"]["name"], (el["lat"], el["lon"]))
    stops = {}
    for name, pos in sorted(nodes.items()):
        # VBN-Namen lauten „Ort Haltestelle“; ein Treffer zählt, wenn er nahe am OSM-Mast liegt
        for term in (name, f"{town['name']} {name}", name.split(",")[-1].strip()):
            best = None
            for h in vbn_search(term):
                if h.get("type") != "1":
                    continue
                lat, lon = int(h["ycoord"]) / 1e6, int(h["xcoord"]) / 1e6
                d = dist((lat, lon), pos)
                if d < 400 and (best is None or d < best[0]):
                    best = (d, h, lat, lon)
            if best:
                _, h, lat, lon = best
                stops[h["extId"]] = {"id": h["extId"], "name": h["value"], "latitude": round(lat, 6), "longitude": round(lon, 6)}
                break
    ordered = sorted(stops.values(), key=lambda x: (x["id"] != default_stop, x["name"]))
    return {"source": "VBN-Fahrplaner (ajax-getstop.exe), Haltestellen laut OpenStreetMap", "stops": ordered}

# ---------------------------------------------------------------- Abfuhr


def streets_for(town):
    def api(q):
        return json.loads(get("https://www.appfuhr.de/api/json.php?" + q, pause=0.5, host_key="appfuhr") or "[]") or []
    out = []
    for st in api(f"tbl=str&ort={town['ort']}"):
        item = {"id": st["id"], "name": st["bez"]}
        if int(st.get("cstrgr") or 1) > 1:
            item["sections"] = [{"id": g["id"], "label": g["grenze"]} for g in api(f"tbl=strgr&str={st['id']}")]
        if int(st.get("castgr") or 1) > 1:
            item["branchSections"] = [{"id": g["id"], "label": g["grenze"]} for g in api(f"tbl=astgr&str={st['id']}")]
        out.append(item)
    out.sort(key=lambda x: x["name"])
    return {"source": "appfuhr.de · Abfallwirtschaftsbetrieb Landkreis Ammerland", "fetchedAt": FETCHED,
            "townID": town["ort"], "town": town["name"], "streets": out}

# ---------------------------------------------------------------- Ehrenamtskarte (Ammerland-PDF, Stand 09/2026)

VOLUNTEER = {
    "apen": [
        ("Freibad Hengstforde", "Bad", "Ermäßigter Eintritt: Einzelkarten zum Preis für Kinder und Jugendliche.", "Hauptstraße 310, 26689 Apen", "04489 1250", "freibad@apen.de", "https://www.apen.de/page/cms/86_Freibad-Hengstforde.html"),
    ],
    "bad-zwischenahn": [
        ("Ceka-Kaufhaus", "Handel", "10 % Rabatt bei allen Einkäufen.", "Mühlenstraße 14, 26160 Bad Zwischenahn", "04403 3393", "badzwischenahn@ceka-kaufhaus.de", "http://ceka-kaufhaus.de/standorte-2/ceka-bad-zwischenahn/"),
        ("kvhs Ammerland, Außenstelle Bad Zwischenahn", "Bildung", "25 % Rabatt auf das gesamte Kursangebot (ausgenommen Langzeitfortbildungen).", "Schulstraße 5, 26160 Bad Zwischenahn", "04403 62377-20", "kvhs@kvhs-ammerland.de", "https://www.kvhs-ammerland.de"),
        ("Hallenbad Bad Zwischenahn", "Bad", "Einzeleintritt 1,50 € statt 2,00 €; Frühschwimmen und Warmbadetag 1,50 € statt 2,50 €.", "Humboldtstraße, 26160 Bad Zwischenahn", "04403 3473", None, "https://www.bad-zwischenahn.de/de/leben-in-bad-zwischenahn/freizeit-sport/Hallenbad.php"),
        ("Bibliothek am Meer", "Bildung", "Jahres-Service-Card für 7,00 € statt 15,00 €.", "Auf dem Hohen Ufer 20, 26160 Bad Zwischenahn", "04403 604460", "bibliothek@bad-zwischenahn.de", "https://www.bad-zwischenahn.de/de/leben-in-bad-zwischenahn/bildung/Bibliothek.php"),
        ("Shell Station Bad Zwischenahn", "Handel", "Zu jeder Fahrzeugwäsche eine Kaffeespezialität gratis.", "Westersteder Straße 1b, 26160 Bad Zwischenahn", "04403 7777", None, None),
        ("Ripken Textil- und Mode", "Handel", "10 % Rabatt auf den Einkauf bei Ripkens Mode.", "Reihdamm 2, 26160 Bad Zwischenahn", "04403 3355", "gerriet@ripken.de", "https://www.ripkensmode.de/"),
        ("Badepark Bad Zwischenahn", "Bad", "Einzeleintritt 1,50 € statt 3,50 €.", "Am Badepark, 26160 Bad Zwischenahn", "04403 1061", None, "https://www.bad-zwischenahn.de/de/leben-in-bad-zwischenahn/freizeit-sport/Badepark.php"),
        ("Hotel Rosmarin", "Übernachtung", "5 % Nachlass auf die Übernachtung.", "Rosmarinweg 12, 26160 Bad Zwischenahn", "04403 4448", "info@hotel-rosmarin.de", "https://www.hotel-rosmarin.de"),
    ],
    "edewecht": [
        ("Bad am Stadion – Frei- und Hallenbad", "Bad", "Vergünstigter Eintritt.", "Zum Stadion 6, 26188 Edewecht", "04405 5458", "hohnholt@edewecht.de", "https://edewecht.de/"),
        ("dm-drogeriemarkt Edewecht", "Handel", "Zu jedem Einkauf ein Balea Duschgel gratis.", "Friedrichsfehner Straße 1b, 26188 Edewecht", "04486 3049950", "servicecenter@dm.de", "https://www.dm.de/store/d54l/edewecht/friedrichsfehner-strasse-1b"),
        ("Prinz Scheune", "Handel", "Alle Sorten der Feinbrennerei Prinz kostenlos probieren und 1,50 € Rabatt auf alle 1,0-Liter-Flaschen.", "Kirchweg 2, 26188 Edewecht", "0160 99836593", "christian@prinz-scheune.de", "https://www.prinz-scheune.de"),
        ("Jeddeloher Zweibrückenbrauerei", "Handel", "Pils und Dunkel vorab als kostenloses 0,1-Liter-ProBier.", "Kirchweg 2, 26188 Edewecht", "04486 9147846", "info@jeddeloher.de", "https://www.jeddeloher.de"),
    ],
    "rastede": [
        ("kvhs Ammerland, Außenstelle Rastede", "Bildung", "25 % Rabatt auf das gesamte Kursangebot (ausgenommen Langzeitfortbildungen).", "Oldenburger Straße 205, 26180 Rastede", "04402 8633-100", "kvhs@kvhs-ammerland.de", "https://www.kvhs-ammerland.de"),
        ("Hallenbad Rastede", "Bad", "Erwachsene erhalten den Eintritt zum Kindertarif.", "Schloßstraße 11, 26180 Rastede", "04402 83540", "info@baeder-rastede.de", "https://www.baeder-rastede.de/"),
        ("Gemeindebücherei Rastede", "Bildung", "50 % Ermäßigung auf den Jahreskartenpreis.", "Oldenburger Straße 256, 26180 Rastede", "04402 83592", "buecherei-rastede@ewetel.net", "https://www.rastede.de/leben-in-rastede/buecherei/"),
    ],
    "wiefelstede": [
        ("Kinderbücherei Metjendorf", "Bildung", "12 Monate Mitgliedschaft für 7,00 €.", "Schulweg 11, 26215 Wiefelstede", "0441 96017351", "kinderbuecherei@wiefelstede.de", "https://www.wiefelstede.de/verzeichnis/mandat.php?mandat=188803&kategorie=1"),
        ("Gemeindebücherei Wiefelstede", "Bildung", "12 Monate Mitgliedschaft für 7,00 €.", "Kirchstraße 10, 26215 Wiefelstede", "04402 965241", "buecherei@wiefelstede.de", "https://www.wiefelstede.de/verzeichnis/visitenkarte.php?mandat=188802"),
        ("Freibad Neuenkruge", "Bad", "Eintritt 1,00 € statt 2,50 €.", "Buschstraße 4, 26215 Wiefelstede", "04402 1515", None, "https://www.wiefelstede.de/verzeichnis/visitenkarte.php?mandat=188810"),
        ("Swemmbad Wiefelstede", "Bad", "Eintritt 1,00 € statt 3,20 €.", "Alter Damm 11, 26215 Wiefelstede", "04402 6699", None, "https://www.wiefelstede.de/verzeichnis/visitenkarte.php?mandat=188807"),
    ],
}


def volunteer_for(slug_):
    places = []
    for i, (name, kind, text, addr, phone, mail, web) in enumerate(VOLUNTEER.get(slug_, [])):
        hits = nominatim("search", q=addr, limit=1, countrycodes="de")
        if not hits:
            hits = nominatim("search", q=name + ", " + addr.split(", ")[-1], limit=1, countrycodes="de")
        p = {"id": "ehrenamt-" + slug(name), "name": name, "category": kind, "teaser": text, "street": addr.split(",")[0],
             "seasonNote": "Nur mit der Ehrenamtskarte Niedersachsen/Bremen · Angaben ohne Gewähr"}
        if phone: p["phone"] = phone
        if mail: p["email"] = mail
        if web: p["website"] = web
        if hits:
            p["latitude"], p["longitude"] = round(float(hits[0]["lat"]), 5), round(float(hits[0]["lon"]), 5)
        places.append(p)
    return places

# ---------------------------------------------------------------- Ablauf


def write(slug_, name, data):
    folder = os.path.join(OUT, slug_)
    os.makedirs(folder, exist_ok=True)
    json.dump(data, open(os.path.join(folder, name), "w"), ensure_ascii=False, indent=None if name == "inselkarte.json" else 1,
              separators=(",", ":") if name == "inselkarte.json" else None)
