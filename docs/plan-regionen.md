# Plan: eine Codebase, eigene Apps je Region

Stand 02.10.2026. Ziel: stede (Ammerland) und Loog (Langeoog) laufen 1:1 auf dem
Code dieses Repos. Jede Region ist eine eigene App im Store (eigene Bundle-ID,
eigener Name, eigenes Icon, eigene Farben). Welche Bausteine eine App zeigt,
entscheidet die Konfiguration — nicht der Code.

## Ausgangslage

| | stede | Loog |
|---|---|---|
| Code | Package `Packages/Stede` (StedeCore/StedeUI), ~14.000 Zeilen | eigenes Repo `../loog`, App-Ordner ohne Package, ~6.400 Zeilen |
| Backend | Supabase „lokalz“, 6 Tenants, Region `ammerland` | gleiches Projekt, Tenant `loog`, Region leer, nur lesend |
| Android | ja | nein |
| Bundle-ID | `de.letzgo.stede` | `de.letzgo.loog` (TestFlight 1.2.2, Build 16) |

**Nur in Loog:** Fähre (api.langeoog.de), Gezeiten (BSH via `content/loog/tides-781P.json`) mit
Wasserständen (`water_levels`) und Hintergrund-Refresh, Luftqualität (UBA), Tile „Strandkörbe“
(externer Anbieter), Ortsfotos mit `image_path`/`imageCredit`, Fahrradverleih mit mehreren
`stations`, Kalender-Extras (Treffpunkt, Anmeldung, Preis, ausgebucht, Thumbnail), loog+ (StoreKit).

**Nur in stede:** Bahn, Bus, Abfuhr, Gruppen/Account/Push/Admin, Einstellungen mit
„Startseite anpassen“, Gemeindewahl, Spielplätze, Ehrenamtskarte, importierte Termine als
Gruppentermine.

**Gemeinsam (Doppelcode heute):** IslandTime, DayCache, LoadState, FlexibleDecoding,
HTTPClient/upstream, ContentSync/ContentFiles, Wetter, Kalender, Ortskategorien
(`IslandCatalog`, `PlaceBrowsing`, Favoriten), Offline-Karte, Theme-Bausteine, RemoteImage.

## Zielbild

```
stede.xcodeproj
├─ stede/      App-Hülle stede  (Icon, Farben, Info.plist: StedeBrand = stede)
├─ loog/       App-Hülle Loog   (Icon, Farben, Info.plist: StedeBrand = loog, BG-Task)
└─ Packages/Stede
   ├─ StedeCore   Brand, Features, alle Clients/Stores (inkl. Fähre, Gezeiten, Luft)
   └─ StedeUI     alle Screens; zeigt nur, was Brand ∩ Features erlaubt
android/           Product Flavors stede / loog (später)
```

Zwei Ebenen der Konfiguration:

1. **Brand** (pro App, fest im Build): Name, Bundle-ID, URL-Schema, Push-Topic, Region,
   Standard-Tenant, ob es eine Gemeindewahl gibt, welche Bausteine die App überhaupt
   enthalten *darf*. Liegt als Codable-Struktur in StedeCore, ausgewählt über den
   Info.plist-Key `StedeBrand`.
2. **Features** (pro Tenant, aus dem Backend): `tenants.config.features`, z. B.
   ```json
   { "weather": true, "calendar": true, "places": ["gastro","sights","leisure","health","trips","bikes"],
     "train": false, "bus": false, "waste": false, "ferry": true, "tides": true,
     "air": true, "groups": false, "external": ["strandkorb"] }
   ```
   Wirksam ist immer **Brand ∩ Features**. Fehlt ein Schlüssel, ist der Baustein aus.
   Der Bundle-Fallback `Resources/tenants.json` trägt dieselben Flags, damit der erste
   Start offline gleich aussieht.

## Phasen

### Phase 1 — Brand-Schicht in stede (ohne sichtbare Änderung)

- `AppBrand` (StedeCore): `id`, `displayName`, `region`, `defaultTenant`,
  `choosesTenant`, `urlScheme`, `pushTopic`, `allowedFeatures`, `shareSuffix`.
  `AppBrand.current` liest `StedeBrand` aus `Bundle.main`.
- Fest verdrahtetes „stede“ ersetzen: `Tenants.defaultSlug`, `Backend.redirectURL`,
  Bar-Titel in `HomeView`, Share-Texte (`EventShare`, `CommunityDetailView`), Push-Topic,
  `OfflineIslandMap.reuseID` (egal, aber sauber).
- `Tenants.all` nach `AppBrand.region` filtern; Gemeindewahl nur bei `choosesTenant`.
- `Tenants.usesBundle`/`contentFolder` am Brand-Standard-Tenant festmachen statt an `"stede"`.
- **Farben aus der App-Hülle:** `StedeTheme` lädt die Colorsets aus `Bundle.main`
  (Namen ohne Präfix: `Sand`, `Surface`, `Bar`, …); die stede-Hülle bekommt die heutigen
  `Stede*`-Werte, das Package behält sie nur als Fallback. Gleiches Muster für Android
  (`C` je Flavor).
- Prüfen: stede baut und sieht exakt aus wie vorher.

### Phase 2 — Feature-Flags

- `TenantConfig.features` (Codable, alle Felder optional) + `Features.current`
  = Brand ∩ Tenant.
- Gating an einer Stelle je Ebene:
  - **Tabs** (`AppTab`): Gruppen nur mit `groups`; Einstellungen nur, wenn es etwas
    einzustellen gibt (Gemeinde, Bahn, Bus, Abfuhr, Gruppen, Push, Startseite).
  - **Start** (`HomeTileID`/`HomeSection`): neue Tiles `ferry`, `tides`, externe Anbieter;
    `isAvailable` prüft `Features`. Sektionen ohne sichtbare Tiles fallen weg.
    `HomeLayout`-Defaults pro Brand (Loog: „Meer & Fähre“ oben).
  - **Start der App**: `AuthStore`, `PushCenter`, Community-Cache, Abfuhr-/Bahn-Warmup
    nur bei aktivem Baustein; `ContentSync` holt nur die Verzeichnisse aus `places`.
  - **Einstellungen**: Abschnitte je Baustein.
  - **Kalender**: Filter „Gruppen“/„Öffentlich“ nur mit `groups`; ohne Gruppen zeigt er
    `city_events` direkt (heutiger Offline-Pfad wird Normalpfad).
- Backend: `features` für alle 7 Tenants setzen (Ammerland: alles außer Fähre/Gezeiten/Luft;
  `loog`: siehe oben), `loog.region = 'langeoog'`.
- Prüfen: stede unverändert; mit Debug-Override `-tenant loog` sieht stede schon „Loog-artig“ aus
  (ohne Fähre/Gezeiten).

### Phase 3 — Loog-Bausteine ins Package portieren

Reihenfolge nach Aufwand, je Baustein Modell + Client/Store in StedeCore, View in StedeUI,
Parser-Fixture + Test in `StedeCoreTests`:

1. **Fähre** — `FerryTrip`, Client über `upstream` (api.langeoog.de), `FerryView`
   (Hafen-Umschalter wie Bahn-Richtung), Tile + `HomeDestination.ferry`.
2. **Gezeiten + Wasserstände** — `TideModels`, `TideStore` (Datei aus `content_files`),
   `WaterLevelClient` (`water_levels`), `TideView`, Tile + `HomeDestination.tides`.
   Datei-/Station-IDs in `tenants.config` (`tides: {file, gauge}`), nicht im Code.
3. **Luftqualität** — `AirQuality` + Abschnitt im Wetter, nur mit `air`
   (Station in `config.air_station`).
4. **Orte** — `image_path` + `imageCredit` auf `GastroPlace`, Foto auf der Karte
   (stede zeigt dann automatisch Fotos, sobald welche im Backend liegen);
   `stations` für Fahrradverleih (Mehrfach-Pins). Abgleich der `IslandCatalog`-Kategorien:
   Kategorien kommen als Liste aus `features.places`, Titel/Farben/Symbole bleiben im Katalog.
5. **Kalender-Extras** — Treffpunkt, Anmeldung, Preis, ausgebucht, Thumbnail aus
   `city_events` in `StedeEvent` und Karte.
6. **Externe Anbieter** — generisches Tile (Titel, Symbol, URL) aus
   `features.external`, öffnet In-App-Browser.
7. **Hintergrund-Refresh Gezeiten** — `BGTaskScheduler` nur in der Loog-Hülle registriert
   (`#if os(iOS)`), Aufruf eines Package-APIs.
8. **loog+** — siehe offene Fragen.

### Phase 4 — Loog-Hülle im stede-Projekt

- Neuer App-Ordner `loog/` (filesystem-synchronisiert), Target + Scheme `loog`,
  Bundle-ID `de.letzgo.loog`, gleiches Team, Version **≥ 1.3, Build ≥ 17** (direkt über
  dem letzten TestFlight-Build, damit Tester ein Update bekommen).
- Icon, Colorsets (Loog-Palette aus `LoogTheme`), Info.plist (`StedeBrand = loog`,
  BG-Task-ID), Entitlements (nur network-client; kein Push, kein Sign in with Apple).
- Nutzerdaten-Übernahme: gleiche `UserDefaults`-Schlüssel wo möglich
  (`island.favorites`, `island.showsMap`, `island.selectedKinds.*` sind schon gleich);
  einmalige Migration für abweichende Schlüssel und Cache-Ordner (`content/` → Tenant-Ordner
  `loog`), sonst lädt der erste Start alles neu (vertretbar, kommt aus dem Backend).
- Prüfen: beide Schemes bauen; Loog-Build auf dem iPhone neben der alten Loog-App
  vergleichen (Screen für Screen), dann TestFlight (nur TestFlight, kein Review).

### Phase 5 — Backend sauber mehr-app-fähig

- `push_tokens.app` (bzw. Topic) und `push-send` nutzt das Topic pro Token statt fest
  `de.letzgo.stede`.
- Redirect-Allowlist um weitere URL-Schemata ergänzen, sobald eine zweite App Gruppen hat.
- `sync-city-events`: Quell-Typen bleiben; neue Region = neuer Tenant + Konfiguration.
- Doku in `tenants.config`: ein Muster-Tenant („Neue Region anlegen“-Checkliste unten).

### Phase 6 — Android

- Product Flavors `stede` / `loog` (applicationId, App-Name, Farben `C`, Icon, Brand-Konstante).
- Gleiche Feature-Gates wie iOS (`Features` in `data/Tenants.kt`).
- Fähre/Gezeiten/Luft portieren — Loog bekäme damit erstmals eine Android-App.
  Kann nach dem iOS-Umzug kommen.

### Phase 7 — Aufräumen

- `../loog` archivieren (README mit Verweis auf dieses Repo), keine Builds mehr von dort.
- CLAUDE.md/AGENTS.md: Abschnitt „Brands & Features“, Loog-Abschnitt aktualisieren,
  Checkliste „Neue Region“.
- Optional später: Package/Targets neutral umbenennen (`Stede` → z. B. `Lokal`). Nicht jetzt,
  bringt viel Churn und keinen Nutzen.

## Checkliste „Neue Region“ (Ziel nach Phase 5)

1. Tenant(s) anlegen: `slug`, `region`, `config` (center, bbox, events_source, features …).
2. Daten: `tools/ammerland_data.py`-Muster für POIs/Karte/Haltestellen, Upload in `places`/`content`.
3. Brand in `AppBrand` eintragen, App-Hülle kopieren (Icon, Farben, Info.plist, Bundle-ID).
4. App ID + TestFlight-App in App Store Connect anlegen.
5. Android-Flavor ergänzen.

## Risiken

- **Regressionen in stede** durch das Gating — jede Phase endet mit stede-Build, der
  identisch aussieht; Parser-Tests laufen weiter.
- **Loog-Nutzer verlieren Favoriten/Einstellungen**, wenn Schlüssel abweichen — Migration
  in Phase 4 vor dem ersten TestFlight-Build testen (alte App installiert → Update).
- **Supabase-SDK in Loog**: Loog lädt künftig das SDK mit, nutzt es aber ohne Login.
  Größer, sonst unkritisch.
- **Theme-Unterschiede**: Loog hat eigene Tile-Anordnung („Meer & Fähre“) — über
  `HomeLayout`-Defaults pro Brand lösen, nicht über Sonderwege in Views.

## Entscheidungen (02.10.2026)

- Eigene App je Region.
- **loog+ bleibt** und wird ein allgemeiner Baustein `plus` (andere Städte sollen ihn auch
  bekommen): Produkt-IDs je Marke (`de.letzgo.<app>.plus.*`), Name „<app>+“.
- **Loog bekommt Android** (Phase 6 ist fest eingeplant).

## Stand

- [x] Phase 1 — `AppBrand` (StedeCore/Support), Info.plist-Key `StedeBrand`, Farben über
      `AppBrand.palette`, Region/URL-Schema/Name aus der Marke.
- [x] Phase 2 — `Feature`/`FeatureSet`/`Features` (StedeCore/Support/Features.swift),
      `TenantConfig.features`/`region`, Gating in Start, Tabs, Einstellungen, Kalender;
      Migration `tenant_features` (alle 7 Tenants, `loog.region = 'langeoog'`, center/bbox).
- [x] Phase 3 — Loog-Bausteine (iOS): Fähre, Gezeiten + Pegel (`TideStore`, BG-Refresh),
      Luftqualität im Wetter, Ortsfotos (`image_path`) und Verleihstationen (`stations`,
      Snapshot-Version 2), Kalender-Extras (Preis, ausgebucht, Anmeldung, Vorschaubild),
      externe Anbieter, Hinweistexte, eigene Kachel „Fahrräder“, Baustein `plus`
      (`PlusStore`/`PlusView`, Tagessperre in DayNavigator und Kalender), Neu-Einlesen nach Sync.
      Konfiguration in `tenants.config` (Migrationen `loog_island_config`, `tenant_notes_external`).
- [x] Phase 4 — Loog-Hülle `loog/` als Target/Scheme `loog` (1.3, Build 17), im Simulator geprüft.
      Offen: Gerät, TestFlight-Upload, Migration alter Loog-Favoriten (Schlüssel gleich,
      Snapshots werden einmal neu geladen).
- [ ] Phase 5 — Backend mehr-app-fähig
- [x] Phase 6 — Android: Flavors `stede`/`loog`, `Brand`/`Features`, Gating, Fähre, Gezeiten,
      Luft, Ortsfotos/Stationen, Kalender-Extras, loog+ über Play Billing; Debug und Release
      beider Flavors im Emulator geprüft. Offen: Play-Console-App für Loog anlegen, Produkte
      `de.letzgo.loog.plus.lifetime` / `.plus.monthly` anlegen, Store-Texte/Screenshots.
- [ ] Phase 7 — Aufräumen
