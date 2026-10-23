# stede Admin: statische Seite hinter nginx (Port 80).
# SUPABASE_URL / SUPABASE_KEY überschreiben beim Start config.js (Standard: Projekt „lokalz“).
FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY 40-stede-config.sh /docker-entrypoint.d/40-stede-config.sh
COPY index.html app.js style.css config.js /usr/share/nginx/html/
RUN chmod +x /docker-entrypoint.d/40-stede-config.sh

EXPOSE 80
