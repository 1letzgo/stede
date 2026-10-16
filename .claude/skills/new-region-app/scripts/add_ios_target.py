#!/usr/bin/env python3
"""Neues App-Target + Scheme in stede.xcodeproj — Klon des Targets `loog` (Vorlage für App-Hüllen).

Aufruf: python3 add_ios_target.py <region> [--dry-run]
Übernimmt Build-Einstellungen, Synchronized-Folder, Package-Produkt StedeUI; ersetzt Name, Ordner,
Bundle-ID, Anzeigename, Version (1.0 / Build 1) und StoreKit-Datei. Idempotent (Target vorhanden → nichts).
Objekt-IDs werden deterministisch aus der Marken-ID abgeleitet.
"""
import hashlib, os, re, sys

import spec as S

# Objekte des Loog-Targets (siehe project.pbxproj)
LOOG = {
    "BF": "4C00600100000000000000BF", "FILE": "4C0060020000000000000001", "EXC": "4C0060030000000000000001",
    "GRP": "4C0060040000000000000001", "FW": "4C0060050000000000000001", "TGT": "4C0060060000000000000001",
    "SRC": "4C0060070000000000000001", "RES": "4C0060080000000000000001", "DBG": "4C0060090000000000000001",
    "REL": "4C00600A0000000000000001", "CFL": "4C00600B0000000000000001", "PROD": "4C00600C0000000000000001",
}


def new_id(brand, role):
    return hashlib.md5(f"{brand}:{role}".encode()).hexdigest()[:24].upper()


def block(text, oid):
    """Ganzer Objekteintrag (ein- oder mehrzeilig) einer ID."""
    m = re.search(rf"^\t\t{oid} /\*.*?\*/ = \{{.*?\}};\n", text, re.S | re.M)
    if not m or m.group(0).count("{") != m.group(0).count("}"):
        # mehrzeilig: bis zur schließenden Klammer auf gleicher Einrückung
        m = re.search(rf"^\t\t{oid} /\*.*?\*/ = \{{\n.*?^\t\t\}};\n", text, re.S | re.M)
    if not m:
        raise SystemExit(f"Objekt {oid} nicht gefunden — wurde das loog-Target verändert?")
    return m.group(0)


def main(region, dry):
    spec = S.load(region)
    b = spec["brand"]
    bid, prefix = b["id"], b["palettePrefix"]
    p = S.path("stede.xcodeproj", "project.pbxproj")
    text = open(p).read()
    if re.search(rf"/\* {bid} \*/ = {{\n\t\t\tisa = PBXNativeTarget;", text):
        print(f"Target {bid} existiert schon.")
    else:
        ids = {k: new_id(bid, k) for k in LOOG}
        swap = lambda s: re.sub("|".join(LOOG.values()), lambda m: ids[[k for k, v in LOOG.items() if v == m.group(0)][0]], s)
        has_storekit = os.path.exists(S.path(bid, f"{prefix}.storekit"))

        def rename(s):
            s = swap(s)
            s = s.replace("de.letzgo.loog", b["bundleId"]).replace("INFOPLIST_KEY_CFBundleDisplayName = Loog;", f'INFOPLIST_KEY_CFBundleDisplayName = "{b["appName"]}";')
            s = re.sub(r"CURRENT_PROJECT_VERSION = \d+;", "CURRENT_PROJECT_VERSION = 1;", re.sub(r"MARKETING_VERSION = [\d.]+;", "MARKETING_VERSION = 1.0;", s))
            s = s.replace("loog/loog.entitlements", f"{bid}/{bid}.entitlements").replace("loog/Info.plist", f"{bid}/Info.plist")
            s = s.replace("\t\t\t\tLoog.storekit,\n", f"\t\t\t\t{prefix}.storekit,\n" if has_storekit else "")
            s = s.replace('"loog"', f'"{bid}"').replace("loog.app", f"{bid}.app").replace("/* loog */", f"/* {bid} */")
            s = s.replace("name = loog;", f"name = {bid};").replace("productName = loog;", f"productName = {bid};").replace("path = loog;", f"path = {bid};")
            return s

        for key, oid in LOOG.items():
            src = block(text, oid)
            i = text.index(src) + len(src)
            text = text[:i] + rename(src) + text[i:]
        # Verweise in Listen (Gruppe, Produkte, Targets, TargetAttributes): neue Zeile direkt hinter loog —
        # loog muss nicht der letzte Eintrag sein (spoog steht dahinter).
        refs = [
            (f"\t\t\t\t{LOOG['GRP']} /* loog */,\n", f"\t\t\t\t{ids['GRP']} /* {bid} */,\n"),
            (f"\t\t\t\t{LOOG['FILE']} /* loog.app */,\n", f"\t\t\t\t{ids['FILE']} /* {bid}.app */,\n"),
            (f"\t\t\t\t{LOOG['TGT']} /* loog */,\n", f"\t\t\t\t{ids['TGT']} /* {bid} */,\n"),
            (f"\t\t\t\t\t{LOOG['TGT']} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.3;\n\t\t\t\t\t}};\n",
             f"\t\t\t\t\t{ids['TGT']} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.3;\n\t\t\t\t\t}};\n"),
        ]
        for old, new in refs:
            if old not in text:
                raise SystemExit(f"Verweis nicht gefunden: {old.strip()[:60]}")
            if new not in text:
                text = text.replace(old, old + new, 1)
        S.write_if_changed(p, text, dry)

    # Scheme
    schemes = S.path("stede.xcodeproj", "xcshareddata", "xcschemes")
    scheme = open(os.path.join(schemes, "loog.xcscheme")).read()
    scheme = scheme.replace(LOOG["TGT"], new_id(bid, "TGT")).replace('"loog.app"', f'"{bid}.app"').replace('BlueprintName = "loog"', f'BlueprintName = "{bid}"')
    if os.path.exists(S.path(bid, f"{prefix}.storekit")):
        scheme = scheme.replace("../../../loog/Loog.storekit", f"../../../{bid}/{prefix}.storekit")
    else:
        scheme = re.sub(r"\s*<StoreKitConfigurationFileReference[^>]*>\s*</StoreKitConfigurationFileReference>", "", scheme)
    S.write_if_changed(os.path.join(schemes, f"{bid}.xcscheme"), scheme, dry)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        raise SystemExit(__doc__)
    main(args[0], "--dry-run" in sys.argv)
