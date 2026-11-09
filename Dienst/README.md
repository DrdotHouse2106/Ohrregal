# Hörbuchwunsch – Server-Dienst für Ohrregal

Ein kleiner Dienst für den eigenen Server, nur mit der Python-Standardbibliothek. Er gehört zur App Ohrregal und erledigt alles, was der Server besser kann als das iPhone:

- **Hörbücher wünschen:** Er sucht sie über Prowlarr, lädt sie mit SABnzbd und sortiert sie in Audiobookshelf ein.
- **Reihe folgen:** Fehlende, schon erschienene Teile einer Reihe werden sofort gewünscht, neue Teile danach automatisch.
- **Hörspiele:** Erkannt werden sie über Audible, Hörspiel-Fassungen haben dann Vorrang.
- **Entdecken:** Vorschläge passend zum eigenen Hörverlauf in Audiobookshelf, mit Begründung („Weil du … gehört hast“).
- **Stöbern:** Bestseller und Neuheiten je Audible-Kategorie, dazu eine eigene Kategorie „Hörspiele“.
- **Musik wünschen** über Lidarr: einzelne Alben, Künstlerseite mit „Fehlt noch“, Künstlern folgen (nur neue Alben), Neuerscheinungen.
- **Push-Nachrichten** direkt in Ohrregal über Apple (APNs): „Hörbuch ist da“, „Album ist da“.
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

- Python 3.11 oder neuer, `curl` mit HTTP/2 und `openssl` (für Apple Push)
- Prowlarr mit mindestens einem Usenet-Indexer, der Hörbücher (3030) kennt
- SABnzbd mit einer eigenen Kategorie, z. B. `hoerbuchwunsch`. Ihr Ordner muss **außerhalb** der Bibliothek liegen.
- Audiobookshelf mit eingeschaltetem Ordner-Watcher
- Optional:
  - Lidarr (Musik wünschen)
  - Navidrome (Anmeldung für Musik-Nutzer)
  - Jellyfin (Leerlauf-Erkennung)
  - ein APNs-Schlüssel (.p8) aus dem Apple-Entwicklerkonto
- Internetzugang zum Audible-Katalog (Reihen, Hörspiel-Erkennung, Entdecken, Stöbern) und zu MusicBrainz (Künstlerseiten). Übertragen werden nur ASINs und MusicBrainz-IDs, keine Benutzerdaten.

## Einrichtung

```sh
install -d /opt/hoerbuch-wunsch /etc/hoerbuch-wunsch
cp hoerbuch_wunsch.py /opt/hoerbuch-wunsch/
cp beispiel.env /etc/hoerbuch-wunsch/zugang.env   # Werte eintragen, chmod 640
install -d -o medien -g medien -m 750 /var/lib/hoerbuch-wunsch
cp hoerbuch-wunsch.service /etc/systemd/system/    # Pfade anpassen
systemctl enable --now hoerbuch-wunsch
```

Alle Einstellungen stehen mit Erklärung in [beispiel.env](beispiel.env).

Von außen erreichbar wird der Dienst am besten über denselben Reverse-Proxy wie Audiobookshelf bzw. Navidrome, als Unterpfad. Beispiel für nginx:

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

Die IP des Proxys gehört in `WUNSCH_PROXYS`, damit die Fehlversuchssperre die echte Absender-IP sieht. Nach 10 Fehlversuchen in 10 Minuten ist eine IP für 15 Minuten gesperrt.

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

Hörprotokoll, Wunschlisten und Geräte liegen nur in der SQLite-Datenbank des Dienstes (`WUNSCH_DATENBANK`). Sie werden an niemanden weitergegeben. Jeder Benutzer sieht und löscht nur seine eigenen Daten. Wer den Server sichert, sichert diese Datenbank mit.

## Suche testen, ohne etwas zu laden

```sh
env $(cat /etc/hoerbuch-wunsch/zugang.env | xargs) python3 hoerbuch_wunsch.py suche-test "<Autor>" "<Titel>" [laufzeitMin]
```

Zeigt die passenden Treffer mit Punkten und die Gründe für verworfene Treffer.

## Probleme

- **App zeigt „nicht angemeldet“, obwohl ABS geht:** Das ABS-Token ist abgelaufen, die App holt ein neues. Kommt danach `429`, ist die IP nach vielen Fehlversuchen 15 Minuten gesperrt.
- **Wünsche hängen auf „gewuenscht“:** Prüfen, ob Prowlarr Indexer mit Kategorie 3030 hat (`suche-test`) und SABnzbd die Kategorie kennt. Teile aus „Reihe folgen“ werden absichtlich erst nachts geladen.
- **Entdecken bleibt leer:** Ohne Hörverlauf in Audiobookshelf nimmt der Dienst die zuletzt hinzugefügten Bücher als Grundlage. Ohne ASINs in der Bibliothek kann er auch damit nichts anfangen.
- **Keine Push-Nachrichten:** In der Tabelle `geraet` muss das Gerät stehen. `APNS_*` müssen gesetzt sein. Apple-Fehler stehen mit Grund im Log (`journalctl -u hoerbuch-wunsch`).
- Jede Anfrage steht mit Status und Dauer im Log, ohne Token.

## Tests

```sh
python3 -m unittest test_bewertung.py
```
