#!/bin/sh
# Schreibt config.js aus den Umgebungsvariablen, falls gesetzt.
set -e
if [ -n "$SUPABASE_URL" ] || [ -n "$SUPABASE_KEY" ]; then
  : "${SUPABASE_URL:=https://fkzjlecsetbnumtqrnem.supabase.co}"
  : "${SUPABASE_KEY:=sb_publishable_5ptJm36r8qnhKrGoGOWd0A_5uOpaBmH}"
  cat > /usr/share/nginx/html/config.js <<EOF
window.STEDE_CONFIG = { supabaseUrl: "$SUPABASE_URL", supabaseKey: "$SUPABASE_KEY" };
EOF
fi
