# stede Admin

Webfrontend für Gemeinde-Admins (`tenant_admins`): Orte, Termine, Veranstalter, Gruppen-Freigaben und `tenants.config`.
Statische Seite, Schreibrechte allein über RLS (Migration `web_admin_policies`).

## Image

Die GitHub Action `admin-image` baut bei jedem Push auf `main`, der `web/admin/` ändert:

```
ghcr.io/1letzgo/stede-admin:latest
```

## Easypanel

1. App-Service anlegen → Quelle „Docker Image“ → `ghcr.io/1letzgo/stede-admin:latest`.
   Ist das GHCR-Paket privat: Registry-Zugang mit GitHub-Benutzer + Token (`read:packages`) eintragen – oder das Paket auf GitHub öffentlich stellen.
2. Domain → Port **80**.
3. Optional Umgebung: `SUPABASE_URL`, `SUPABASE_KEY` (Standard: Projekt „lokalz“, Publishable Key).
4. Supabase → Authentication → URL Configuration → Redirect URLs: `https://<domain>/**` ergänzen, sonst landet der Link aus „Passwort vergessen“ nicht auf der Seite. Anmeldung: E-Mail + Passwort; wer noch keins hat (Apple-Login, Magic Link), setzt es über „Passwort vergessen“.
5. Für Updates „Deploy“ in Easypanel (zieht `latest` neu) oder Auto-Deploy-Webhook der App in einen GitHub-Workflow eintragen.

## Lokal

```bash
cd web/admin && python3 -m http.server 8765
```

(Aus dem iCloud-Ordner heraus scheitert `http.server` mitunter an Rechten – dann die Dateien vorher nach `/tmp` kopieren.)
