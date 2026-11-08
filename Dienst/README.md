# Hörbuchwunsch – Server-Dienst für Ohrregal

Ein kleiner Dienst für den eigenen Server. Er nimmt in Ohrregal gewünschte Hörbücher an und besorgt sie:

1. **Suchen** über Prowlarr in der Hörbuch-Kategorie (3030), mit mehreren Suchvarianten.
2. **Bewerten:** Titel und Autor müssen passen. „Ungekürzt“ zählt mehr als „gekürzt“. Hörspiel-, Kinder- und Lesungsfassungen werden aussortiert. Die Größe muss zur Laufzeit passen, die Sprache zum Wunsch. Sammelpakete gelten nur als Notlösung.
3. **Laden** mit SABnzbd in eine eigene Kategorie, deren Ordner nicht in der Bibliothek liegt.
4. **Einsortieren** als `Autor/Reihe/Teil - Titel` in die Audiobookshelf-Bibliothek, zusammen mit `metadata.json` (inkl. ASIN) und Cover. Das Buch wird erst in einem versteckten Arbeitsordner zusammengesetzt und dann in einem Schritt verschoben. So liest Audiobookshelf nie ein halbes Buch ein.
5. **Melden:** Der Status wird `da` und es kommt eine Push-Nachricht über ntfy (optional).

Was nicht gefunden wird, sucht der Dienst nach 24 Stunden erneut. Es laufen höchstens `WUNSCH_PARALLEL` Wünsche gleichzeitig. **Aus der Bibliothek wird nie etwas gelöscht.** Auch das Zurückziehen eines fertigen Wunsches entfernt nur den Listeneintrag.

Die Schnittstelle für die App steht in [API.md](API.md).

## Voraussetzungen

- Python 3.11 oder neuer, nur Standardbibliothek
- Prowlarr mit mindestens einem Usenet-Indexer, der Hörbücher (3030) kennt
- SABnzbd mit einer eigenen Kategorie, z. B. `hoerbuchwunsch`. Ihr Ordner muss **außerhalb** der Bibliothek liegen.
- Audiobookshelf mit eingeschaltetem Ordner-Watcher. Seine Datenbank wird nur lesend geöffnet, um „schon vorhanden“ und `absItemId` zu ermitteln.

## Einrichtung

```sh
install -d /opt/hoerbuch-wunsch /etc/hoerbuch-wunsch
cp hoerbuch_wunsch.py /opt/hoerbuch-wunsch/
cp beispiel.env /etc/hoerbuch-wunsch/zugang.env   # Werte eintragen, chmod 640
install -d -o medien -g medien -m 750 /var/lib/hoerbuch-wunsch
cp hoerbuch-wunsch.service /etc/systemd/system/    # Pfade anpassen
systemctl enable --now hoerbuch-wunsch
```

Den Dienst nur im Heimnetz oder über VPN erreichbar machen, nicht öffentlich.

## Token pro Benutzer

```sh
# gibt den Token einmal aus, gespeichert wird nur sein SHA-256-Hash
env WUNSCH_TOKENS=/var/lib/hoerbuch-wunsch/tokens.json python3 hoerbuch_wunsch.py token-neu <name>
env WUNSCH_TOKENS=/var/lib/hoerbuch-wunsch/tokens.json python3 hoerbuch_wunsch.py token-weg <name>
```

Den Token tragen Benutzer in Ohrregal unter Einstellungen → Hörbuchwunsch zusammen mit der Adresse ein.

## Suche testen, ohne etwas zu laden

```sh
env $(cat /etc/hoerbuch-wunsch/zugang.env | xargs) python3 hoerbuch_wunsch.py suche-test "<Autor>" "<Titel>" [laufzeitMin]
```

Zeigt die passenden Treffer mit Punkten und die Gründe für verworfene Treffer.

## Tests

```sh
python3 -m unittest test_bewertung.py
```
