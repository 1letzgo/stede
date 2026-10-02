#!/usr/bin/env python3
"""Orte aufwerten wie bei Loog: Fotos, Ruhetage, Fakten für längere Teaser — für den Skill `new-region-app`.

Aufruf (Arbeitsordner tools/out/<slug>/, dieselben Dateien, die content-import hochlädt):
  python3 tools/enrich_places.py <slug> export            Orte aus der Tabelle `places` holen (bestehende Gemeinde;
                                                          bei neuen Regionen liegen sie schon von region_data.py da)
  python3 tools/enrich_places.py <slug> collect [--web-images]
        - Ruhetag aus den Öffnungszeiten (Gastro): „Montag“, „Mo + Di“, „kein Ruhetag“
        - Fotos von Wikimedia Commons: OSM-Tags wikimedia_commons/image/wikidata (P18) am Ort, sonst
          Commons-Geosuche ≤ 80 m mit Namensbezug; Credit „Foto: Urheber · Lizenz · Wikimedia Commons“
        - mit --web-images zusätzlich og:image der eigenen Website (Credit „Foto: <domain>“) — nur nach
          Rücksprache mit dem Nutzer (Bildrechte liegen beim Betrieb)
        - Fakten je Ort in teaser-facts.json (Beschreibung der Website, Wikipedia-Einleitung, OSM-Merkmale)
        Fotos landen als JPEG (max. 1280 px) in tools/out/<slug>/images/, der Ort bekommt `image` + `imageCredit`.
  python3 tools/enrich_places.py <slug> teasers <datei>   {"<id>": "Teaser", …} in die JSONs übernehmen

Danach content-import (Skill Schritt 5) — er lädt die Fotos nach content/<slug>/places/ und setzt image_path.
"""
import hashlib, html, json, os, re, subprocess, sys, urllib.parse, urllib.request

import osm_content as oc

HERE = os.path.dirname(os.path.abspath(__file__))
SUPABASE = "https://fkzjlecsetbnumtqrnem.supabase.co"
KEY = "sb_publishable_5ptJm36r8qnhKrGoGOWd0A_5uOpaBmH"  # öffentlich lesbar, wie in den Apps
FILES = {"gastro": "gastronomie.json", "health": "gesundheit.json", "leisure": "freizeit.json", "sights": "sehenswuerdigkeiten.json",
         "playgrounds": "spielplaetze.json", "trips": "ausfluege.json", "volunteer": "ehrenamt.json", "bikes": "fahrradverleih.json"}
DAYS = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
LONG = {"Mo": "Montag", "Di": "Dienstag", "Mi": "Mittwoch", "Do": "Donnerstag", "Fr": "Freitag", "Sa": "Samstag", "So": "Sonntag"}
TOWN = ""
UA = {"User-Agent": "stede-content/1.0 (https://letzgo.de; goletz@gmail.com)"}


def http(url, raw=False, timeout=20):
    req = urllib.request.Request(url, headers={**UA, "Accept-Language": "de"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = r.read()
    return body if raw else body.decode("utf-8", "replace")


def folder(slug):
    return os.path.join(HERE, "out", slug)


def load(slug):
    out = {}
    for d, f in FILES.items():
        p = os.path.join(folder(slug), f)
        if os.path.exists(p):
            out[d] = json.load(open(p))
    return out


def items(data, d):
    return data[d].get("providers" if d == "bikes" else "places", [])


def coords(p):
    if p.get("latitude") is not None:
        return p["latitude"], p["longitude"]
    st = (p.get("stations") or [{}])[0]
    return st.get("latitude"), st.get("longitude")

# ---------------------------------------------------------------- export


def export(slug):
    cols = ("tenants!inner(slug),directory,external_id,kind,name,teaser,street,phone,email,website,hours,rest_day,season_note,"
            "image_credit,image_path,extra_link_title,extra_link_url,features,lat,lon,stations,sort_order")
    q = urllib.parse.urlencode({"select": cols, "deleted_at": "is.null", "tenants.slug": f"eq.{slug}", "order": "directory,sort_order"})
    req = urllib.request.Request(f"{SUPABASE}/rest/v1/places?{q}", headers={"apikey": KEY, "Authorization": f"Bearer {KEY}"})
    rows = json.load(urllib.request.urlopen(req, timeout=60))
    dreq = urllib.request.Request(f"{SUPABASE}/rest/v1/place_directories?select=directory,source,fetched_at,tenants!inner(slug)&tenants.slug=eq.{slug}",
                                  headers={"apikey": KEY, "Authorization": f"Bearer {KEY}"})
    meta = {r["directory"]: r for r in json.load(urllib.request.urlopen(dreq, timeout=60))}
    by = {}
    for r in rows:
        p = {"id": r["external_id"], "name": r["name"], "category": r["kind"], "teaser": r["teaser"], "street": r["street"], "phone": r["phone"],
             "email": r["email"], "website": r["website"], "hours": r["hours"], "restDay": r["rest_day"], "seasonNote": r["season_note"],
             "imageCredit": r["image_credit"], "imagePath": r["image_path"], "extraLinkTitle": r["extra_link_title"],
             "extraLinkURL": r["extra_link_url"], "features": r["features"] or None, "latitude": r["lat"], "longitude": r["lon"],
             "stations": r["stations"]}
        by.setdefault(r["directory"], []).append({k: v for k, v in p.items() if v is not None})
    for d, ps in by.items():
        m = meta.get(d, {})
        head = {"source": m.get("source", ""), "fetchedAt": (m.get("fetched_at") or "")[:10]}
        if d == "bikes":
            provs = [{**{k: v for k, v in p.items() if k not in ("latitude", "longitude", "street", "stations", "category")},
                      "stations": p.get("stations") or [{"label": p["name"], "street": p.get("street", ""), "latitude": p.get("latitude"), "longitude": p.get("longitude")}]}
                     for p in ps]
            oc.write(slug, FILES[d], {**head, "providers": provs})
        else:
            oc.write(slug, FILES[d], {**head, "places": ps})
        print(f"  {d}: {len(ps)}")
    for d, f in FILES.items():  # Verzeichnisse ohne Orte im Backend: alte Dateien weg, sonst lädt content-import sie wieder hoch
        if d not in by and os.path.exists(os.path.join(folder(slug), f)):
            os.remove(os.path.join(folder(slug), f))
            print(f"  {d}: entfernt (nicht im Backend)")

# ---------------------------------------------------------------- Ruhetag


def day_set(hours):
    """Wochentage, die in einer Zeitangabe wie „Mo-Sa 11–14 Uhr · So 16–22 Uhr“ vorkommen; None = unklar."""
    if not hours or re.search(r"geschlossen|nach Vereinbarung|Saison|Feiertag|PH|\d{1,2}\.\d{1,2}\.", hours, re.I):
        return None
    if re.search(r"täglich|Mo[-–]So|rund um die Uhr|24/7", hours, re.I):
        return set(DAYS)
    found = set()
    for a, b in re.findall(r"\b(Mo|Di|Mi|Do|Fr|Sa|So)\b(?:\s*[-–]\s*\b(Mo|Di|Mi|Do|Fr|Sa|So)\b)?", hours):
        i = DAYS.index(a)
        j = DAYS.index(b) if b else i
        while True:
            found.add(DAYS[i])
            if i == j:
                break
            i = (i + 1) % 7
    return found or None


def rest_day(hours):
    s = day_set(hours)
    if s is None:
        return None
    off = [d for d in DAYS if d not in s]
    if not off:
        return "kein Ruhetag"
    if len(off) == 1:
        return LONG[off[0]]
    return " + ".join(off) if len(off) <= 3 else None

# ---------------------------------------------------------------- Fotos


def commons_info(title):
    q = urllib.parse.urlencode({"action": "query", "format": "json", "prop": "imageinfo", "titles": title, "iiprop": "url|extmetadata|mime",
                                "iiurlwidth": 1280})
    pages = json.loads(oc.get("https://commons.wikimedia.org/w/api.php?" + q, pause=0.5, host_key="commons"))["query"]["pages"]
    for pg in pages.values():
        ii = (pg.get("imageinfo") or [{}])[0]
        if ii.get("mime") not in ("image/jpeg", "image/png"):
            return None
        meta = ii.get("extmetadata", {})
        strip = lambda v: re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", "", (v or {}).get("value", "")))).strip()
        artist, lic = strip(meta.get("Artist"))[:60], strip(meta.get("LicenseShortName"))
        if not lic:
            return None
        return {"url": ii.get("thumburl") or ii["url"], "credit": f"Foto: {artist or 'unbekannt'} · {lic} · Wikimedia Commons"}
    return None


def wikidata(qid):
    j = json.loads(oc.get(f"https://www.wikidata.org/wiki/Special:EntityData/{qid}.json", pause=0.5, host_key="wikidata"))
    return j["entities"].get(qid, {})


def osm_refs(slug, data):
    """Ein Overpass-Abruf je Gemeinde: Elemente mit Namen und Bild-/Wikidata-Tags, Zuordnung über Name + ≤ 120 m."""
    global TOWN
    t = json.load(open(os.path.join(folder(slug), "tenant.json")))
    TOWN = t.get("municipality", "")
    s, w, n, e = t["bbox"]
    els = oc.overpass(f"""[out:json][timeout:120];
nwr({s},{w},{n},{e})[name][~"^(wikidata|wikimedia_commons|image|wikipedia)$"~"."];
out center tags;""")
    oc.save_cache()
    refs = {}
    for d in data:
        for p in items(data, d):
            lat, lon = coords(p)
            if lat is None:
                continue
            best = None
            for el in els:
                c = el.get("center", el)
                if "lat" not in c:
                    continue
                dist = oc.dist((lat, lon), (c["lat"], c["lon"]))
                if dist <= 120 and similar(p["name"], el["tags"]["name"], TOWN) and (best is None or dist < best[0]):
                    best = (dist, el["tags"])
            if best:
                refs[p["id"]] = best[1]
    return refs


GENERIC = {"alte", "alter", "altes", "neue", "neuer", "neues", "der", "die", "das", "den", "und", "zum", "zur", "haus", "hof", "insel",
           "café", "cafe", "restaurant", "hotel", "kirche", "file", "jpg", "jpeg", "png", "evangelische", "katholische", "spielplatz"}


def similar(a, b, town=""):
    """Gemeinsames markantes Wort (ohne Allerweltswörter und Ortsnamen) — „Alte Inselkirche“ ≠ „Das alte Inselhaus“."""
    norm = lambda s: {w for w in re.findall(r"[a-zäöüß0-9]{4,}", s.lower()) if w not in GENERIC and w not in town.lower()}
    A, B = norm(a), norm(b)
    return bool(A & B) or a.lower().strip() == b.lower().strip()


def commons_for(p, tags, d):
    if tags:
        f = tags.get("wikimedia_commons", "")
        if f.startswith("File:"):
            return commons_info(f)
        img = tags.get("image", "")
        m = re.search(r"commons\.wikimedia\.org/wiki/(File:[^?#]+)", img) or re.search(r"upload\.wikimedia\.org/.+/([^/]+\.(?:jpe?g|png))$", img, re.I)
        if m:
            return commons_info(urllib.parse.unquote(m.group(1) if m.group(1).startswith("File:") else "File:" + m.group(1)))
        if tags.get("wikidata"):
            p18 = wikidata(tags["wikidata"]).get("claims", {}).get("P18")
            if p18:
                return commons_info("File:" + p18[0]["mainsnak"]["datavalue"]["value"])
    if d not in ("sights", "leisure", "trips"):
        return None
    lat, lon = coords(p)
    q = urllib.parse.urlencode({"action": "query", "format": "json", "list": "geosearch", "gscoord": f"{lat}|{lon}", "gsradius": 80,
                                "gsnamespace": 6, "gslimit": 20})
    hits = json.loads(oc.get("https://commons.wikimedia.org/w/api.php?" + q, pause=0.5, host_key="commons"))["query"]["geosearch"]
    for h in hits:
        if similar(p["name"], h["title"], TOWN):
            return commons_info(h["title"])
    return None


def site_meta(url):
    try:
        page = http(url, timeout=12)[:300000]
    except Exception:
        return {}
    def meta(*names):
        for n in names:
            m = re.search(r'<meta[^>]+(?:property|name)=["\']%s["\'][^>]*content=["\']([^"\']+)' % re.escape(n), page, re.I) or \
                re.search(r'<meta[^>]+content=["\']([^"\']+)["\'][^>]*(?:property|name)=["\']%s["\']' % re.escape(n), page, re.I)
            if m:
                return html.unescape(m.group(1)).strip()
    img = meta("og:image", "twitter:image")
    return {"description": meta("og:description", "description"), "image": urllib.parse.urljoin(url, img) if img else None}


def looks_like_logo(path):
    """Eine Farbe deckt ≥ 35 % der Fläche → Logo/Grafik. Fängt nicht alles: Fotos danach trotzdem ansehen."""
    try:
        from PIL import Image
    except ImportError:
        return False
    from collections import Counter
    px = [(r // 24, g // 24, b // 24) for r, g, b in Image.open(path).convert("RGB").resize((64, 64)).getdata()]
    return Counter(px).most_common(1)[0][1] / len(px) >= 0.35


def save_image(slug, d, p, url):
    os.makedirs(os.path.join(folder(slug), "images"), exist_ok=True)
    name = f"{d}-{oc.slug(p['id'])[:40]}-{hashlib.sha1(url.encode()).hexdigest()[:10]}.jpg"
    path = os.path.join(folder(slug), "images", name)
    if not os.path.exists(path):
        raw = http(url, raw=True, timeout=30)
        if len(raw) < 8000:  # Logos, Platzhalter, Tracking-Pixel
            return None
        tmp = path + ".src"
        open(tmp, "wb").write(raw)
        r = subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "70", "-Z", "1280", tmp, "--out", path], capture_output=True)
        os.remove(tmp)
        if r.returncode != 0 or not os.path.exists(path):
            return None
        if looks_like_logo(path):  # Logo auf Weiß/Flächenfarbe statt Foto
            os.remove(path)
            return None
        w = subprocess.run(["sips", "-g", "pixelWidth", path], capture_output=True, text=True).stdout
        if int(re.search(r"pixelWidth: (\d+)", w).group(1)) < 500:  # zu klein für den Kartenkopf
            os.remove(path)
            return None
    return name


def wiki_extract(tags):
    title = (tags or {}).get("wikipedia", "")
    if not title and (tags or {}).get("wikidata"):
        title = "de:" + wikidata(tags["wikidata"]).get("sitelinks", {}).get("dewiki", {}).get("title", "")
    if not title.startswith("de:") or len(title) < 4:
        return None
    try:
        j = json.loads(oc.get("https://de.wikipedia.org/api/rest_v1/page/summary/" + urllib.parse.quote(title[3:].replace(" ", "_")), pause=0.5, host_key="wiki"))
        return j.get("extract")
    except Exception:
        return None


def collect(slug, web_images=False):
    data = load(slug)
    refs = osm_refs(slug, data)
    facts, stats = [], {"restDay": 0, "commons": 0, "web": 0}
    for d in data:
        for p in items(data, d):
            tags = refs.get(p["id"])
            if d == "gastro" and not p.get("restDay"):
                r = rest_day(p.get("hours"))
                if r:
                    p["restDay"] = r; stats["restDay"] += 1
            site = site_meta(p["website"]) if p.get("website") else {}
            if not p.get("imagePath") and not p.get("image") and d not in ("playgrounds", "volunteer"):
                try:
                    c = commons_for(p, tags, d)
                    name = save_image(slug, d, p, c["url"]) if c else None
                    if name:
                        p["image"], p["imageCredit"] = name, c["credit"]; stats["commons"] += 1
                    elif web_images and site.get("image"):
                        name = save_image(slug, d, p, site["image"])
                        if name:
                            p["image"], p["imageCredit"] = name, "Foto: " + urllib.parse.urlparse(p["website"]).netloc.removeprefix("www.")
                            stats["web"] += 1
                except Exception as e:
                    print(f"  ! Foto {p['name']}: {e}")
            facts.append({"directory": d, "id": p["id"], "name": p["name"], "kind": p.get("category"), "street": p.get("street"),
                          "teaser": p.get("teaser"), "website": p.get("website"), "siteDescription": site.get("description"),
                          "wikipedia": wiki_extract(tags), "osm": {k: v for k, v in (tags or {}).items()
                                                                   if k in ("cuisine", "description", "heritage", "start_date", "operator", "denomination")} or None})
            oc.save_cache()
        oc.write(slug, FILES[d], data[d])
    json.dump(facts, open(os.path.join(folder(slug), "teaser-facts.json"), "w"), ensure_ascii=False, indent=1)
    print(f"{slug}: Ruhetage {stats['restDay']} · Fotos Commons {stats['commons']} · Fotos Website {stats['web']} · "
          f"Fakten für {len(facts)} Orte in teaser-facts.json")


def teasers(slug, path):
    new = json.load(open(path))
    data, n = load(slug), 0
    for d in data:
        for p in items(data, d):
            if new.get(p["id"]):
                p["teaser"] = new[p["id"]]; n += 1
        oc.write(slug, FILES[d], data[d])
    print(f"{slug}: {n} Teaser übernommen")


if __name__ == "__main__":
    a = [x for x in sys.argv[1:] if not x.startswith("--")]
    if len(a) < 2 or a[1] not in ("export", "collect", "teasers"):
        raise SystemExit(__doc__)
    if a[1] == "export":
        export(a[0])
    elif a[1] == "collect":
        collect(a[0], web_images="--web-images" in sys.argv)
    else:
        teasers(a[0], a[2])
