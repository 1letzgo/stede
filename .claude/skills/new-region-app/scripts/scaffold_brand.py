#!/usr/bin/env python3
"""Code-Gerüst für eine neue Marke aus tools/regions/<region>.json — idempotent.

Aufruf: python3 scaffold_brand.py <region> [--dry-run]
Legt an bzw. ergänzt:
  iOS     AppBrand-Eintrag (StedeCore/Support/AppBrand.swift), Colorsets <Präfix><Rolle> (StedeUI),
          App-Hülle <id>/ (App.swift, Info.plist, Entitlements, AccentColor, StoreKit-Datei bei plus)
  Android Brand-Eintrag (data/Brand.kt), Palette (ui/Theme.kt), Flavor (app/build.gradle.kts),
          src/<id>/res/values/themes.xml und mipmap-Vorlage
Das Xcode-Target macht `add_ios_target.py`, die Icons `make_icons.py`.
"""
import json, os, re, sys

import spec as S

DRY = "--dry-run" in sys.argv


def swift_set(items):
    return "[" + ", ".join(f".{i}" for i in items) + "]"


def insert_before(path, marker, block, exists_pattern):
    """Block vor dem Marker einfügen, sofern exists_pattern noch nicht vorkommt."""
    text = open(path).read()
    if re.search(exists_pattern, text):
        return text
    i = text.index(marker)
    return text[:i] + block + text[i:]


def ios(spec):
    b = spec["brand"]
    enabled, places = S.features(spec)
    feats = swift_set(enabled)
    pl = "[" + ", ".join(f'"{p}"' for p in sorted(places)) + "]"
    privacy = f'URL(string: "{b["privacyURL"]}")' if b["privacyURL"] else "nil"
    p = S.path("Packages", "Stede", "Sources", "StedeCore", "Support", "AppBrand.swift")
    block = f'''    /// {spec["regionName"]} (Skill new-region-app).
    public static let {b["id"]} = AppBrand(
        id: "{b["id"]}", displayName: "{b["displayName"]}", region: "{spec["region"]}", regionName: "{spec["regionName"]}",
        defaultTenant: "{b["defaultTenant"]}", choosesTenant: {str(b["choosesTenant"]).lower()}, urlScheme: "{b["id"]}", palette: "{b["palettePrefix"]}",
        allowedFeatures: FeatureSet({feats}, places: {pl}),
        defaultFeatures: FeatureSet({feats}, places: {pl}),
        placesTitle: "{b["placesTitle"]}", bikesInShopping: {str(b["bikesInShopping"]).lower()}, privacyURL: {privacy}
    )

'''
    text = insert_before(p, "    public static let all: [AppBrand]", block, rf"static let {b['id']} = AppBrand\(")
    text = re.sub(r"public static let all: \[AppBrand\] = \[([^\]]*)\]",
                  lambda m: m.group(0) if f".{b['id']}" in m.group(1).split(", ") else f"public static let all: [AppBrand] = [{m.group(1)}, .{b['id']}]", text)
    S.write_if_changed(p, text, DRY)

    # Colorsets
    pal = S.palette(spec)
    root = S.path("Packages", "Stede", "Sources", "StedeUI", "Resources", "Colors.xcassets")
    for role, (light, dark) in pal.items():
        S.write_if_changed(os.path.join(root, f"{b['palettePrefix']}{role}.colorset", "Contents.json"), colorset(light, dark), DRY)

    # App-Hülle
    shell = S.path(b["id"])
    tpl = lambda n: open(os.path.join(os.path.dirname(__file__), "..", "templates", n)).read()
    push = "@UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate" if "groups" in enabled else "// Ohne Gruppen kein Push."
    app = tpl("App.swift").replace("__APP_NAME__", b["appName"]).replace("__ID__", b["id"]).replace("__STRUCT__", f"{b['id']}App").replace("__PUSH_DELEGATE__", push)
    S.write_if_changed(os.path.join(shell, f"{b['id']}App.swift"), app, DRY)
    aps = "\t<key>aps-environment</key>\n\t<string>development</string>\n" if "groups" in enabled else ""
    S.write_if_changed(os.path.join(shell, f"{b['id']}.entitlements"), tpl("entitlements.plist").replace("__APS__", aps), DRY)
    S.write_if_changed(os.path.join(shell, "Info.plist"), info_plist(b, enabled), DRY)
    S.write_if_changed(os.path.join(shell, "Assets.xcassets", "Contents.json"), json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n", DRY)
    S.write_if_changed(os.path.join(shell, "Assets.xcassets", "AccentColor.colorset", "Contents.json"), colorset(*pal["Ink"]), DRY)
    if "plus" in enabled:
        store = tpl("Plus.storekit").replace("__BUNDLE__", b["bundleId"]).replace("__NAME__", b["displayName"])
        S.write_if_changed(os.path.join(shell, f"{b['palettePrefix']}.storekit"), store, DRY)


def colorset(light, dark):
    def comp(h):
        r, g, b = (int(h.lstrip("#")[i:i + 2], 16) / 255 for i in (0, 2, 4))
        return {"color-space": "srgb", "components": {"alpha": "1.000", "red": f"{r:.3f}", "green": f"{g:.3f}", "blue": f"{b:.3f}"}}
    return json.dumps({"colors": [
        {"color": comp(light), "idiom": "universal"},
        {"appearances": [{"appearance": "luminosity", "value": "dark"}], "color": comp(dark), "idiom": "universal"},
    ], "info": {"author": "xcode", "version": 1}}, indent=2) + "\n"


def info_plist(b, enabled):
    parts = [f"\t<key>StedeBrand</key>\n\t<string>{b['id']}</string>"]
    if "groups" in enabled:
        parts.append(f"\t<key>CFBundleURLTypes</key>\n\t<array>\n\t\t<dict>\n\t\t\t<key>CFBundleURLName</key>\n\t\t\t<string>{b['bundleId']}</string>\n"
                     f"\t\t\t<key>CFBundleURLSchemes</key>\n\t\t\t<array>\n\t\t\t\t<string>{b['id']}</string>\n\t\t\t</array>\n\t\t</dict>\n\t</array>")
    if "tides" in enabled:
        parts.append(f"\t<key>BGTaskSchedulerPermittedIdentifiers</key>\n\t<array>\n\t\t<string>{b['bundleId']}.refresh-tides</string>\n\t</array>\n"
                     "\t<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>fetch</string>\n\t</array>")
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            '<plist version="1.0">\n<dict>\n' + "\n".join(parts) + "\n</dict>\n</plist>\n")


def kotlin_set(items):
    names = {"weather": "Weather", "calendar": "Calendar", "train": "Train", "bus": "Bus", "waste": "Waste", "ferry": "Ferry",
             "tides": "Tides", "air": "Air", "groups": "Groups", "plus": "Plus"}
    return "setOf(" + ", ".join(f"Feature.{names[i]}" for i in items) + ")"


def android(spec):
    b = spec["brand"]
    enabled, places = S.features(spec)
    pl = "setOf(" + ", ".join(f'"{p}"' for p in sorted(places)) + ")"
    privacy = f'"{b["privacyURL"]}"' if b["privacyURL"] else "null"
    p = S.path("android", "app", "src", "main", "java", "de", "letzgo", "stede", "data", "Brand.kt")
    block = f'''        /** {spec["regionName"]} (Skill new-region-app). */
        val {b["id"]} = Brand("{b["id"]}", "{b["displayName"]}", "{spec["region"]}", "{spec["regionName"]}", "{b["defaultTenant"]}", {str(b["choosesTenant"]).lower()},
            FeatureSet({kotlin_set(enabled)}, {pl}),
            FeatureSet({kotlin_set(enabled)}, {pl}),
            "{b["placesTitle"]}", {str(b["bikesInShopping"]).lower()}, {privacy})

'''
    text = insert_before(p, "        val all = listOf(", block, rf"val {b['id']} = Brand\(")
    text = re.sub(r"val all = listOf\(([^)]*)\)", lambda m: m.group(0) if b["id"] in [x.strip() for x in m.group(1).split(",")] else f"val all = listOf({m.group(1)}, {b['id']})", text)
    S.write_if_changed(p, text, DRY)

    pal = S.palette(spec)
    tone = lambda r: f"Tone(0xFF{pal[r][0].lstrip('#')}, 0xFF{pal[r][1].lstrip('#')})"
    p = S.path("android", "app", "src", "main", "java", "de", "letzgo", "stede", "ui", "Theme.kt")
    block = f'''        /** {b["id"]}: Palette `{b["palettePrefix"]}*` (Skill new-region-app). */
        val {b["id"]} = Palette(
            sand = {tone("Sand")}, surface = {tone("Surface")}, harbor = {tone("Harbor")},
            dune = {tone("Dune")}, sun = {tone("Sun")}, sea = {tone("Sea")},
            deep = {tone("Deep")}, bar = {tone("Bar")}, ink = {tone("Ink")},
            heather = {tone("Heather")}, mudflat = {tone("Mudflat")},
        )
'''
    text = insert_before(p, "        val all = mapOf(", block, rf"val {b['id']} = Palette\(")
    text = re.sub(r"val all = mapOf\(([^)]*)\)", lambda m: m.group(0) if f'"{b["id"]}"' in m.group(1) else f'val all = mapOf({m.group(1)}, "{b["id"]}" to {b["id"]})', text)
    S.write_if_changed(p, text, DRY)

    p = S.path("android", "app", "build.gradle.kts")
    block = f'''        create("{b["id"]}") {{
            dimension = "brand"
            applicationId = "{b["bundleId"]}"
            versionCode = 1
            versionName = "1.0"
            buildConfigField("String", "BRAND", "\\"{b["id"]}\\"")
            resValue("string", "app_name", "{b["appName"]}")
            manifestPlaceholders["urlScheme"] = "{b["id"]}"
        }}
'''
    S.write_if_changed(p, insert_before(p, "        // brands: end", block, rf'create\("{b["id"]}"\)'), DRY)
    res = S.path("android", "app", "src", b["id"], "res")
    tpl = lambda n: open(os.path.join(os.path.dirname(__file__), "..", "templates", n)).read()
    S.write_if_changed(os.path.join(res, "values", "themes.xml"), tpl("themes.xml").replace("__BAR__", pal["Bar"][0]), DRY)
    S.write_if_changed(os.path.join(res, "mipmap-anydpi-v26", "ic_launcher.xml"), tpl("ic_launcher.xml"), DRY)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        raise SystemExit(__doc__)
    spec = S.load(args[0])
    ios(spec)
    android(spec)
