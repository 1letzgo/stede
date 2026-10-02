"""Gemeinsames für die Skripte des Skills `new-region-app`: Repo-Wurzel, Region-Spec, Palette."""
import colorsys, json, os, re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
ROLES = ["Sand", "Surface", "Harbor", "Dune", "Sun", "Sea", "Deep", "Bar", "Ink", "Heather", "Mudflat"]


def path(*parts):
    return os.path.join(ROOT, *parts)


def load(region):
    """tools/regions/<region>.json — siehe SKILL.md für das Format."""
    spec = json.load(open(path("tools", "regions", f"{region}.json")))
    b = spec["brand"]
    b.setdefault("bundleId", f"de.letzgo.{b['id']}")
    b.setdefault("palettePrefix", b["id"][:1].upper() + b["id"][1:])
    b.setdefault("defaultTenant", spec["municipalities"][0]["slug"])
    b.setdefault("choosesTenant", len(spec["municipalities"]) > 1)
    b.setdefault("placesTitle", "Stadt")
    b.setdefault("bikesInShopping", False)
    b.setdefault("privacyURL", None)
    if not re.fullmatch(r"[a-z][a-z0-9]*", b["id"]):
        raise SystemExit("brand.id: nur Kleinbuchstaben/Ziffern (wird URL-Schema, Flavor und Target)")
    if b["id"].startswith(("test", "androidtest")) or b["id"] in ("main", "debug", "release", "stede", "loog"):
        raise SystemExit(f"brand.id „{b['id']}“ geht nicht: Gradle verbietet Flavors mit „test…“, main/debug/release sind belegt.")
    return spec


def features(spec):
    f = spec["features"]
    enabled = [k for k, v in f.items() if k != "places" and v]
    return enabled, f.get("places", [])


# ---------------------------------------------------------------- Farben

def _rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def _hex(c):
    return "#" + "".join(f"{round(max(0, min(1, v)) * 255):02X}" for v in c)


def mix(a, b, t):
    """Farbe a mit Anteil t von b."""
    ra, rb = _rgb(a), _rgb(b)
    return _hex(tuple(x + (y - x) * t for x, y in zip(ra, rb)))


def lighten(h, amount):
    hh, l, s = colorsys.rgb_to_hls(*_rgb(h))
    return _hex(colorsys.hls_to_rgb(hh, min(1, l + amount), s))


def palette(spec):
    """Rollen → (hell, dunkel). Aus `brand.palette` (vollständig) oder abgeleitet aus `brand.colors`
    {"bar": Leiste/Marke, "accent": Akzent}; die übrigen Rollen nehmen bewährte Insel-Töne."""
    b = spec["brand"]
    if "palette" in b:
        return {r: tuple(b["palette"][r]) for r in ROLES}
    bar, accent = b["colors"]["bar"], b["colors"]["accent"]
    return {
        "Sand": (mix("#F6F3EE", bar, 0.03), mix("#0F141B", bar, 0.25)),
        "Surface": ("#FFFFFF", mix("#1B222C", bar, 0.30)),
        "Harbor": ("#C4453B", "#E88074"),
        "Dune": ("#3E7C4F", "#7FC08F"),
        "Sun": ("#D98E2B", "#F2B95C"),
        "Sea": (accent, lighten(accent, 0.25)),
        "Deep": (bar, mix(bar, "#000000", 0.25)),
        "Bar": (bar, mix(bar, "#000000", 0.25)),
        "Ink": (bar, lighten(bar, 0.55)),
        "Heather": ("#8B579C", "#CAA3DB"),
        "Mudflat": ("#8B6B4B", "#D5B793"),
    }


def write_if_changed(p, text, dry):
    old = open(p).read() if os.path.exists(p) else None
    if old == text:
        return False
    print(("~ " if old is not None else "+ ") + os.path.relpath(p, ROOT))
    if not dry:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w").write(text)
    return True
