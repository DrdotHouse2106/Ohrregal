# Hörbuchwunsch – Server-Dienst für Ohrregal

Ein kleiner Dienst für den eigenen Server, nur mit der Python-Standardbibliothek, fertig als Docker-Image. Er gehört zur App Ohrregal und erledigt alles, was der Server besser kann als das iPhone:

- **Hörbücher wünschen:** Er sucht sie über Prowlarr, lädt sie mit SABnzbd und sortiert sie in Audiobookshelf ein.
- **Reihe folgen:** Fehlende, schon erschienene Teile einer Reihe werden sofort gewünscht, neue Teile danach automatisch.
- **Hörspiele:** Erkannt werden sie über Audible, Hörspiel-Fassungen haben dann Vorrang.
- **Entdecken:** Vorschläge passend zum eigenen Hörverlauf in Audiobookshelf, mit Begründung („Weil du … gehört hast“).
- **Stöbern:** Bestseller und Neuheiten je Audible-Kategorie, dazu eine eigene Kategorie „Hörspiele“.
- **Musik wünschen** über Lidarr: einzelne Alben, Künstlerseite mit „Fehlt noch“, Künstlern folgen (nur neue Alben), Neuerscheinungen.
- **Push-Nachrichten** direkt in Ohrregal über Apple (APNs): „Hörbuch ist da“, „Album ist da“.
- **YouTube-Musik zuordnen:** Bei Titeln aus YouTube-Downloads findet der Dienst nachts den echten Künstler, über MusicBrainz und bei Nightcore über Last.fm. Ist kein bekanntes Lied dabei, gilt der Kanal als Künstler. Die Dateien bleiben unverändert.
- **Hörprotokoll** je Benutzer, nur zum Zuschneiden der Vorschläge. Einsehbar und löschbar.
- **Ruhezeiten:** Gerechnet wird nachts und nur, wenn niemand streamt. Tagsüber liefert der Dienst nur aus seinem Vorrat aus.

Die Schnittstelle für die App steht in [API.md](API.md).

Grundsätze:
- **Aus den Bibliotheken wird nie etwas gelöscht.** Zieht man einen Wunsch zurück, entfernt das nur den Listeneintrag bzw. beendet die Überwachung in Lidarr.
- Lidarr, Prowlarr und SABnzbd bleiben im Heimnetz, ihre Schlüssel bleiben auf dem Server.
- Die Datenbank von Audiobookshelf wird nur lesend geöffnet.
- Downloads sind gedrosselt: höchstens `WUNSCH_PARALLEL` Hörbücher gleichzeitig und 3 Albumsuchen pro Minute.

## So läuft ein Hörbuchwunsch

1. **Suchen** über Prowlarr in der Hörbuch-Kategorie (3030), mit mehreren Suchvarianten (Autor + Titel, Titel, Reihe + Teil).
2. **Bewerten:** Titel und Autor müssen passen. Bei Serienfolgen genügen Reihenname und Folgennummer. Bei Büchern zählt „Ungekürzt“ mehr als „gekürzt“, und Hörspiel-, Kinder- und Lesungsfassungen werden aussortiert. Bei Hörspielen ist es umgekehrt: Hörspiel-Fassungen werden bevorzugt. Die Größe muss zur Laufzeit passen, die Sprache zum Wunsch. Verlustfreie Releases (FLAC) sind erlaubt, kleinere kommen aber zuerst. Sammelpakete gelten nur als Notlösung.
3. **Laden** mit SABnzbd in eine eigene Kategorie, deren Ordner nicht in der Bibliothek liegt.
4. **Einsortieren** als `Autor/Reihe/Teil - Titel` in die Audiobookshelf-Bibliothek, mit `metadata.json` (inkl. ASIN) und Cover. Das Buch wird zuerst in einem versteckten Arbeitsordner zusammengesetzt und dann in einem Schritt verschoben. So liest Audiobookshelf nie ein halbes Buch ein.
5. **Melden:** Der Status wird `da`, und eine Push-Nachricht geht an alle Geräte der Benutzer, die das Buch gewünscht haben.

Was nicht gefunden wird, sucht der Dienst nachts erneut.

## Ruhezeiten und Vorrat

- **Nachtfenster** (`NACHT_VON`–`NACHT_BIS`, Standard 3–6 Uhr): Nur dann rechnet der Dienst `/kategorien`, `/entdecken` und `/stoebern` neu. Außerdem prüft er Reihen, sucht nicht Gefundenes erneut und lädt Teile aus „Reihe folgen“.
- **Leerlauf:** Kein laufender Jellyfin-Stream, keine Live-TV-Aufnahme, keine Wiedergabe in Audiobookshelf. Streamt jemand, unterbricht der Dienst und macht später weiter.
- **Tagsüber** liefert er aus dem Vorrat (`vorrat.json`, übersteht Neustarts). Neu gerechnet wird nur auf ausdrücklichen Wunsch (`neu=1`) oder wenn noch nichts da ist.
- Neue, ausdrückliche Wünsche werden immer sofort bearbeitet.

## Voraussetzungen

- Prowlarr mit mindestens einem Usenet-Indexer, der Hörbücher (Kategorie 3030) kennt
- SABnzbd
- Audiobookshelf mit eingeschaltetem Ordner-Watcher (Standard)
- Optional:
  - Lidarr (Musik wünschen)
  - Navidrome (Anmeldung für Musik-Nutzer)
  - Jellyfin (Leerlauf-Erkennung)
  - ein Apple-Push-Schlüssel (.p8) für Nachrichten an Ohrregal
- Internetzugang zum Audible-Katalog (Reihen, Hörspiel-Erkennung, Entdecken, Stöbern) und zu MusicBrainz (Künstlerseiten). Übertragen werden nur ASINs und MusicBrainz-IDs, keine Benutzerdaten.

## Einrichtung mit Docker (empfohlen)

Ein fertiges Image liegt unter `ghcr.io/drdothouse2106/ohrregal-wunsch` (amd64 und arm64). Selbst bauen ist nicht nötig.

**1. SABnzbd vorbereiten**

In SABnzbd unter **Config → Categories** eine Kategorie `hoerbuchwunsch` anlegen, mit Ordner `hoerbuch-wunsch`. Der Ordner liegt dann im „Completed“-Ordner von SABnzbd, also **nicht** in der Hörbuch-Bibliothek. So sieht Audiobookshelf nie halbe Downloads.

**2. Dateien holen**

Im Ordner des Media-Stacks:
```sh
mkdir hoerbuch-wunsch
curl -o hoerbuch-wunsch.env https://raw.githubusercontent.com/DrdotHouse2106/Ohrregal/main/Dienst/beispiel.env
chmod 600 hoerbuch-wunsch.env
```

**3. Werte eintragen**

`hoerbuch-wunsch.env` ausfüllen, siehe [Wo finde ich die Werte?](#wo-finde-ich-die-werte). Mindestens nötig sind `PROWLARR_KEY`, `SAB_KEY` und `SAB_PFADE`.

**4. Dienst in die docker-compose.yml übernehmen**

Den Block aus [docker-compose.yml](docker-compose.yml) in die eigene `docker-compose.yml` kopieren und die Platzhalter in `<…>` ersetzen:

| Platzhalter | Was | Beispiel |
|---|---|---|
| `<hoerbuch-bibliothek>` | derselbe Ordner, den Audiobookshelf als Bibliothek eingebunden hat | `/srv/hoerbuecher` |
| `<sabnzbd-complete>` | der „Completed“-Ordner von SABnzbd auf dem Host | `/srv/downloads/complete` |
| `<audiobookshelf-config>` | der Config-Ordner von Audiobookshelf (mit `absdatabase.sqlite`) | `./config/audiobookshelf` |
| `<apns-schluessel>` | optional, der .p8-Schlüssel | `./geheim/apns` |
| `<youtube-musik>` | optional, Ordner mit YouTube-Musik | `/srv/youtube/music` |

`user: "1000:1000"` muss zur UID/GID passen, mit der Audiobookshelf seine Dateien schreibt (`ls -n` im Bibliotheksordner).
Steht der Dienst in derselben `docker-compose.yml` wie die anderen Container, entfällt der `networks:`-Block. Die Container finden sich dann über ihre Namen.

**5. Starten**

```sh
docker compose up -d hoerbuch-wunsch
docker compose logs -f hoerbuch-wunsch
```

**6. Funktioniert es?**

```sh
curl http://<server>:8097/status
# {"ok": true, "version": "…"}
curl http://<server>:8097/wunsch
# {"fehler": "nicht_angemeldet", …}  → richtig, ohne Anmeldung kommt 401
```

In Ohrregal dann **Hörbuch wünschen** öffnen. Die App nimmt automatisch die Adresse von Audiobookshelf + `/wunsch-api`. Dafür braucht es den Reverse-Proxy (unten). Im Heimnetz geht es auch direkt.

**Aktualisieren:** `docker compose pull hoerbuch-wunsch && docker compose up -d hoerbuch-wunsch`. Daten und Vorrat liegen in `./hoerbuch-wunsch` und bleiben erhalten.

## Wo finde ich die Werte?

| Wert | Wo |
|---|---|
| `PROWLARR_KEY` | Prowlarr → Settings → General → Security → API Key |
| `SAB_KEY` | SABnzbd → Config → General → Security → API Key |
| `SAB_PFADE` | links der Pfad, unter dem SABnzbd im **eigenen** Container den Kategorie-Ordner sieht (Config → Folders → Completed Download Folder + `/hoerbuch-wunsch`), rechts `/downloads` |
| `ABS_BIBLIOTHEK_PFAD` | Audiobookshelf → Einstellungen → Bibliotheken → Bibliothek bearbeiten → Ordner |
| `ABS_BIBLIOTHEK_ID` | Bibliothek in Audiobookshelf öffnen, die ID steht in der Adresse: `…/library/<ID>/…` |
| `LIDARR_KEY` | Lidarr → Settings → General → Security → API Key |
| `LIDARR_ORDNER` | Lidarr → Settings → Media Management → Root Folders |
| Lidarr-Profil-IDs | Lidarr → Settings → Profiles, Profil bearbeiten, die Zahl in der Adresse |
| `JELLYFIN_KEY` | Jellyfin → Dashboard → API-Schlüssel → + |
| `APNS_*` | developer.apple.com → Certificates, IDs & Profiles → Keys → + → „Apple Push Notifications service“. Key-ID beim Schlüssel, Team-ID unter Membership, Topic = Bundle-ID der App |
| `LASTFM_KEY` | last.fm/api/account/create |
| `WUNSCH_PROXYS` | IP, mit der der Reverse-Proxy beim Dienst ankommt (steht nach dem ersten Aufruf im Log) |

## Von außen erreichbar machen (Reverse-Proxy)

Der Dienst gehört unter dieselbe Adresse wie Audiobookshelf, als Unterpfad `/wunsch-api/`. Wer Musik ohne Audiobookshelf nutzt, richtet denselben Pfad zusätzlich unter der Navidrome-Adresse ein.

**nginx** (auch Plesk: Domain → Apache & nginx-Einstellungen → „Zusätzliche nginx-Anweisungen“, unten anhängen):
```nginx
location /wunsch-api/ {
    proxy_pass http://<dienst-adresse>:8097/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    client_max_body_size 100k;
}
```
Beim Einfügen in ein Formular wie Plesk den Block per Tastatur bzw. Zwischenablage einfügen und danach die Seite neu laden. Erst dann ist sicher, dass er gespeichert ist.

**Nginx Proxy Manager:** Beim Proxy-Host von Audiobookshelf → **Custom Locations** → Location `/wunsch-api/`, Forward Hostname `hoerbuch-wunsch` (bzw. Server-IP), Port `8097`. Im Zahnrad-Feld `proxy_pass http://hoerbuch-wunsch:8097/;` eintragen, damit der Pfad abgeschnitten wird.

**Test von außen:** `curl https://<abs-adresse>/wunsch-api/status` muss `{"ok": true, …}` liefern. Kommt stattdessen eine HTML-Seite von Audiobookshelf („Cannot GET“), greift der Block nicht.

Die IP des Proxys in `WUNSCH_PROXYS` eintragen, damit die Fehlversuchssperre die echte Absender-IP sieht. Nach 10 Fehlversuchen in 10 Minuten ist eine IP für 15 Minuten gesperrt.

## Alternative: ohne Docker (systemd)

Braucht Python 3.11 oder neuer, `curl` mit HTTP/2 und `openssl`. Für das Lesen der Tags von YouTube-Musik zusätzlich `ffprobe`.

```sh
install -d /opt/hoerbuch-wunsch /etc/hoerbuch-wunsch
cp hoerbuch_wunsch.py /opt/hoerbuch-wunsch/
cp beispiel.env /etc/hoerbuch-wunsch/zugang.env   # echte Pfade und Adressen eintragen, chmod 640
install -d -o medien -g medien -m 750 /var/lib/hoerbuch-wunsch
cp hoerbuch-wunsch.service /etc/systemd/system/    # Pfade anpassen
systemctl enable --now hoerbuch-wunsch
```

Bei systemd die Datenbank-Pfade (`WUNSCH_DATENBANK`, `WUNSCH_TOKENS`) in der env-Datei setzen und `SAB_PFADE` nur, wenn SABnzbd andere Pfade sieht als der Host.

## Anmeldung

Der Dienst hat keine eigenen Benutzer. Er übernimmt die Anmeldung der App:
- **Audiobookshelf:** `Authorization: Bearer <ABS-Token>`, geprüft über `ABS_URL/api/me`. Mit `ABS_BIBLIOTHEK_ID` dürfen nur Benutzer mit Zugriff auf diese Bibliothek wünschen.
- **Navidrome:** Kopfzeilen `X-Subsonic-U`, `-T`, `-S`, geprüft über `/rest/ping`.

Für Skripte gibt es zusätzlich eigene Tokens:

```sh
# gibt den Token einmal aus, gespeichert wird nur sein SHA-256-Hash
env WUNSCH_TOKENS=/var/lib/hoerbuch-wunsch/tokens.json python3 hoerbuch_wunsch.py token-neu <name>
env WUNSCH_TOKENS=/var/lib/hoerbuch-wunsch/tokens.json python3 hoerbuch_wunsch.py token-weg <name>
```

## Datenschutz

Hörprotokoll, Wunschlisten und Geräte liegen nur in der SQLite-Datenbank des Dienstes (Docker: `./hoerbuch-wunsch`, systemd: `WUNSCH_DATENBANK`). Sie werden an niemanden weitergegeben. Jeder Benutzer sieht und löscht nur seine eigenen Daten. Wer den Server sichert, sichert diese Datenbank mit.

## Suche testen, ohne etwas zu laden

```sh
docker compose exec hoerbuch-wunsch python3 /app/hoerbuch_wunsch.py suche-test "<Autor>" "<Titel>" [laufzeitMin]
# systemd:
env $(grep -v '^#' /etc/hoerbuch-wunsch/zugang.env | xargs) python3 hoerbuch_wunsch.py suche-test "<Autor>" "<Titel>"
```

Zeigt die passenden Treffer mit Punkten und die Gründe für verworfene Treffer.

## Probleme

- **App zeigt „nicht angemeldet“, obwohl ABS geht:** Das ABS-Token ist abgelaufen, die App holt ein neues. Kommt danach `429`, ist die IP nach vielen Fehlversuchen 15 Minuten gesperrt.
- **Wünsche hängen auf „gewuenscht“:** Prüfen, ob Prowlarr Indexer mit Kategorie 3030 hat (`suche-test`) und SABnzbd die Kategorie kennt. Teile aus „Reihe folgen“ werden absichtlich erst nachts geladen.
- **Entdecken bleibt leer:** Ohne Hörverlauf in Audiobookshelf nimmt der Dienst die zuletzt hinzugefügten Bücher als Grundlage. Ohne ASINs in der Bibliothek kann er auch damit nichts anfangen.
- **Keine Push-Nachrichten:** In der Tabelle `geraet` muss das Gerät stehen. `APNS_*` müssen gesetzt sein. Apple-Fehler stehen mit Grund im Log (`docker compose logs hoerbuch-wunsch` bzw. `journalctl -u hoerbuch-wunsch`).
- Jede Anfrage steht mit Status und Dauer im Log, ohne Token.

## Tests

```sh
python3 -m unittest test_bewertung.py
```
