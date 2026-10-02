---
name: new-region-app
description: Neue Regions-App aus der stede-Codebase erzeugen (wie Loog für Langeoog) — Marke, iOS-Target, Android-Flavor, Tenants mit Bausteinen im Backend und Inhalte aus OpenStreetMap. Use when the user says /new-region-app, „neue App für <Ort/Region>“, „weitere Version der App“, „App für Juist/Landkreis X anlegen“ or wants another regional brand built from this repo.
---

# new-region-app

Legt eine weitere App an, die aus demselben Code wie stede und Loog gebaut wird. Hintergrund:
CLAUDE.md, Abschnitt „Brands & building blocks“, und `docs/plan-regionen.md` (Checkliste „Neue Region“).
Alle Skripte liegen in `.claude/skills/new-region-app/scripts/` und lesen eine Spec-Datei
`tools/regions/<region>.json`. Jedes Skript kennt `--dry-run` und ist idempotent.

## 1. Eingaben klären (AskUserQuestion, Vorschläge machen)

- **Region**: Slug (`juist`), Anzeigename („Juist“, für „Wähle deine Gemeinde im …“).
- **Gemeinden**: je Gemeinde Slug, Name und OSM-Grenze — Relations-ID (sicher) oder Name mit
  `admin_level` (Standard 8). Relation-ID per Nominatim/Overpass nachschlagen und zeigen.
- **Marke**: `id` (klein, = URL-Schema, Flavor, Target, Ordner), `displayName` (klein wie „loog“, in Leiste
  und „<name>+“), `appName` (Home-Screen, z. B. „Juist“), Bundle-ID (Standard `de.letzgo.<id>`),
  `placesTitle` („Stadt“/„Insel“), `bikesInShopping`, Datenschutz-URL (Pflicht bei `plus`).
- **Bausteine**: weather, calendar, train, bus, waste, ferry, tides, air, groups, plus und die
  Ortsverzeichnisse (gastro, health, leisure, sights, playgrounds, trips, bikes, volunteer).
  Nur anbieten, was es für die Region gibt:
  - `train`: Bahnhöfe mit EVA-Nummer + dbf-Namen (`stations`, `default_station`).
  - `bus`: nur im VBN-Gebiet (Haltestellen via VBN-Suche, `bus.default_stop`).
  - `waste`: nur appfuhr/Ammerland (`waste.ort`).
  - `ferry`/`tides`/`air`: Konfiguration wie bei Loog (`tenants.config` von `loog` als Vorlage lesen);
    Gezeiten brauchen eine Datei im Bucket + `sync-tides`-Anpassung, Pegel einen PEGELONLINE-Eintrag
    in `sync-water-levels` — sonst weglassen.
  - `calendar`: nur mit einer Quelle, die `sync-city-events` schon kann: `nolis` (URL-Vorlage),
    `destination_one` (experience, optional city), `langeoog`. Andernfalls Kalender aus und dem Nutzer sagen,
    dass eine neue Quelle Code in der Edge Function braucht.
  - `groups`: Push und Login hängen dran (siehe Schritt 8).
- **Farben**: `colors.bar` (Leiste/Marke) und `colors.accent` — oder eine ganze `palette` (Rollen siehe unten).
- **Icon**: PNG-Pfad (1024², randlos) oder generieren lassen.

## 2. Spec schreiben

`tools/regions/<region>.json`:

```json
{
  "region": "juist", "regionName": "Juist",
  "brand": {"id": "juist", "displayName": "juist", "appName": "Juist", "bundleId": "de.letzgo.juist",
            "placesTitle": "Insel", "bikesInShopping": false, "privacyURL": "https://…/datenschutz.html",
            "colors": {"bar": "#1B4182", "accent": "#1F7A8C"}, "icon": null},
  "features": {"weather": true, "calendar": true, "plus": true,
               "places": ["gastro", "health", "leisure", "sights", "trips", "bikes"]},
  "notes": {"health": "Notruf 112 · …", "events": "Quelle · …"},
  "external": [{"title": "Strandkörbe", "symbol": "beach.umbrella.fill", "url": "https://…"}],
  "municipalities": [
    {"slug": "juist", "name": "Juist", "relation": 1234567,
     "config": {"events_source": {"type": "destination_one", "experience": "…"}}}
  ]
}
```

Optional je Gemeinde: `bbox`, `center` (Ortskern statt Mitte der Grenze — bei Inseln oft nötig), `bus`,
`waste`, und in `config` alles Weitere aus `tenants.config` (`ferry`, `tides`, `air_station`, `stations`,
`default_station`, `bus_default_stop`, `waste_town_id`). Optional global: `trips` (Pfad zu einer
handgeschriebenen `ausfluege.json`). Palette-Rollen: Sand, Surface, Harbor, Dune, Sun, Sea, Deep, Bar, Ink,
Heather, Mudflat, je `["#hell", "#dunkel"]`.

## 3. Inhalte erzeugen

```bash
python3 tools/region_data.py <region>
```

Schreibt `tools/out/<slug>/` (Orte, `inselkarte.json`, ggf. `bus-stops.json`/`abfuhr-strassen.json`,
`tenant.json` mit center/bbox). Overpass ist langsam und manchmal überlastet — im Hintergrund laufen lassen;
Antworten landen im Cache `tools/out/cache.json`. Danach dem Nutzer Anzahlen je Verzeichnis und je drei
Stichproben zeigen; offensichtlich falsche Einträge (Denkmäler, Schulhallen) in den JSONs entfernen.
`center` prüfen (liegt er im Ort?), sonst in der Spec setzen.

## 4. Backend (schreibt in Produktion — vorher bestätigen lassen)

```bash
python3 .claude/skills/new-region-app/scripts/tenant_sql.py <region>
```

gibt das SQL aus und ergänzt die Bundle-Datei `tenants.json` (iOS + Android-Kopie). Das SQL per Supabase-MCP
`apply_migration` (Name `tenant_<region>`) einspielen. `sync-city-events` greift neue Tenants mit
`events_source` beim nächsten stündlichen Lauf auf; zum Testen `…/sync-city-events?tenant=<slug>&days=30`
aufrufen (anon-JWT, wie der Cron-Job).

## 5. Inhalte hochladen

1. Einmal-Token erzeugen (`openssl rand -hex 16`), `supabase/functions/content-import/index.ts` mit
   eingesetztem Token (statt `__IMPORT_TOKEN__`) per MCP `deploy_edge_function` (`verify_jwt: true`) deployen.
2. `cloudflared tunnel --url http://localhost:8765` und `python3 -m http.server 8765 -d tools/out` im
   Hintergrund starten, Tunnel-URL aus der Ausgabe lesen.
3. Je Gemeinde: `curl -X POST "$SUPABASE_URL/functions/v1/content-import" -H "Authorization: Bearer <anon-JWT>"
   -H "Content-Type: application/json" -d '{"token":"…","slug":"<slug>","base":"<tunnel-url>"}'`
   (anon-JWT: MCP `get_publishable_keys`, Legacy-anon-Key). Antwort = Anzahlen.
4. Sofort `stub.ts` als `content-import` deployen, Server und Tunnel beenden.
5. Kontrolle per SQL: `places` je Verzeichnis, `content_files`, ggf. `bus_stops`.

## 6. Code-Gerüst

```bash
S=.claude/skills/new-region-app/scripts
python3 $S/scaffold_brand.py <region>    # Marke iOS/Android, Colorsets, Palette, App-Hülle, Flavor
python3 $S/make_icons.py <region>        # AppIcon + Android-Icon
python3 $S/add_ios_target.py <region>    # Xcode-Target + Scheme (Klon von loog)
```

Danach `git status` zeigen. Nichts davon verändert stede oder loog.

## 7. Prüfen

```bash
xcodebuild -project stede.xcodeproj -scheme <id> -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project stede.xcodeproj -scheme stede -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
cd android && ./gradlew assemble<Id>Debug assembleStedeDebug assembleLoogDebug
```

(Android braucht `JAVA_HOME`/`ANDROID_HOME` wie in CLAUDE.md.) Die neue App im iOS-Simulator starten
(`mcp__Claude_Code_iOS_Simulator__control` launch) und im Emulator (AVD `stede`): Start zeigt nur die
gewählten Bausteine, Orte mit Karte, Kalender, ggf. Plus-Tab. Screenshot zeigen.

## 8. Abschluss

- `docs/plan-regionen.md`: Region unter „Regionen“ eintragen; CLAUDE.md und AGENTS.md: eine Zeile zur Marke.
- Commit nur auf Nachfrage.
- Manuelle Restschritte dem Nutzer nennen:
  - App Store Connect: App mit der Bundle-ID anlegen (Capabilities: bei `groups` Push + Sign in with Apple),
    bei `plus` In-App-Käufe `<bundle>.plus.lifetime` und Abo `<bundle>.plus.monthly`.
  - Play Console: App `<bundle>` anlegen, bei `plus` Produkte mit denselben IDs.
  - Bei `groups`: Redirect `<id>://auth-callback` in Supabase → Authentication → URL Configuration erlauben;
    Push-Topic ist heute fest `de.letzgo.stede` in `push-send` (Phase 5 in `docs/plan-regionen.md`).
  - Store-Texte, Screenshots (`store/<id>/`), Datenschutzerklärung.
  - Builds: Skills `testflight-build` (Scheme `<id>`), `beta-android`.
