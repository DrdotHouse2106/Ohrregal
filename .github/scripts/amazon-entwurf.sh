#!/usr/bin/env bash
# Ohrregal TV: neue APK als Entwurf in die Amazon-Appstore-Version laden (App Submission API).
# Reicht NICHT ein – Freigabe von Hand in der Amazon-Developer-Konsole („Submit App“).
# Hinweis: Live App Testing lässt sich über die API nicht aktualisieren.
# Aufruf: bash amazon-entwurf.sh <APK>
# Umgebung: AMAZON_CLIENT_ID, AMAZON_CLIENT_SECRET (GitHub-Secrets), AMAZON_APP_ID
set -euo pipefail
APK="$1"
if [ -z "${AMAZON_CLIENT_ID:-}" ] || [ -z "${AMAZON_CLIENT_SECRET:-}" ]; then
  echo "::notice::Amazon-Secrets fehlen – Upload übersprungen"; exit 0
fi

API="https://developer.amazon.com/api/appstore/v1/applications/$AMAZON_APP_ID"
H="$(mktemp)"
TOKEN="$(curl -fsS https://api.amazon.com/auth/o2/token \
  --data-urlencode grant_type=client_credentials \
  --data-urlencode "client_id=$AMAZON_CLIENT_ID" \
  --data-urlencode "client_secret=$AMAZON_CLIENT_SECRET" \
  --data-urlencode scope=appstore::apps:readwrite | jq -r .access_token)"
echo "::add-mask::$TOKEN"

# api METHODE PFAD [curl-Optionen…] – Antwort auf stdout, Kopfzeilen in $H
api() { local m="$1" p="$2"; shift 2; curl -fsS -X "$m" -D "$H" -H "Authorization: Bearer $TOKEN" "$@" "$API$p"; }
etag() { api GET "$1" -o /dev/null; tr -d '\r' < "$H" | awk 'tolower($1)=="etag:"{print $2}'; }

# Offenes Edit nehmen oder neu anlegen
EDIT="$(api GET /edits | jq -r '.id // empty' || true)"
[ -n "$EDIT" ] || EDIT="$(api POST /edits | jq -r .id || true)"
# Ohne Edit geht nichts: Die erste Version muss einmal von Hand in der Konsole eingereicht werden
[ -n "$EDIT" ] || { echo "::warning::Kein Amazon-Entwurf möglich – erste Version zuerst von Hand in der Developer-Konsole einreichen"; exit 0; }
echo "Edit $EDIT"

# Die einzige APK ersetzen (Gerätezuordnung bleibt erhalten)
APK_ID="$(api GET "/edits/$EDIT/apks" | jq -r '.[0].id')"
api PUT "/edits/$EDIT/apks/$APK_ID/replace" -H "If-Match: $(etag "/edits/$EDIT/apks/$APK_ID")" \
  -H "Content-Type: application/vnd.android.package-archive" --data-binary "@$APK" | jq -c '{id, versionCode}'

# Prüfen – offene Punkte (z. B. Bildschirmfotos) nur melden
api POST "/edits/$EDIT/validate" | jq . || echo "::warning::Amazon meldet offene Punkte"
echo "::notice::Neue APK liegt als Entwurf bei Amazon – Freigabe in der Developer-Konsole"
