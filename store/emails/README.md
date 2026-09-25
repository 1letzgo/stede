# Supabase-E-Mail-Vorlagen für stede

Eintragen im Supabase-Dashboard: Authentication → Emails → Templates. Betreff und Inhalt (HTML) je Vorlage ersetzen.

- **Magic Link** — Betreff: `Dein Anmeldelink für stede` — Inhalt: `magic-link.html`
- **Confirm signup** — Betreff: `Willkommen bei stede – bitte bestätigen` — Inhalt: `confirm-signup.html`
- **Change Email Address** — Betreff: `Neue E-Mail-Adresse für stede bestätigen` — Inhalt: `change-email.html`

Die Vorlagen nutzen nur `{{ .ConfirmationURL }}`. Das Projekt „lokalz“ ist für alle Gemeinde-Apps gemeinsam; derzeit meldet sich nur stede mit Konten an.
