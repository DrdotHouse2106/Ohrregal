# Ohrregal

Musik und Hörbücher von den eigenen Servern in einer iPhone-App, die sich anfühlt wie Apple Music.

- **Musik** aus [Navidrome](https://www.navidrome.org/) (Subsonic- bzw. OpenSubsonic-API)
- **Hörbücher und Hörspiele** aus [Audiobookshelf](https://www.audiobookshelf.org/)
- **CarPlay**, offline hören und Vorschläge aus deinem Hörverhalten
- Optik und Wortwahl passend zu Quallenkino

Stand: Version 0.16 (TestFlight). Plan und Fahrplan stehen in [KONZEPT.md](KONZEPT.md).

English version: [README.en.md](README.en.md)

## Funktionen

**Musik**
- Startseite mit Tagesgruß und „Für dich“: „Dein Mix“ und ein Mix pro Lieblingskünstler mit Cover-Collage. Dazu Schnellauswahl, Zuletzt gespielt, Am häufigsten gespielt, Lange nicht gehört, Kürzlich hinzugefügt, Alben mit „Gefällt mir“.
- Mediathek: Künstler, Alben, Playlists, „Gefällt mir“, Geladen. Suche über alles.
- Player: lückenlose Wiedergabe, Warteschlange (umsortieren, entfernen), Songtexte (synchron, antippbar), Herz für „Gefällt mir“, AirPlay, Sperrbildschirm.
- Titelmenü: Als Nächstes, Zur Warteschlange, Zur Playlist, Radio ab diesem Song.
- Playlists auf dem iPhone anlegen, bearbeiten und löschen. Alles landet in Navidrome.
- **Musik wünschen** über Lidarr: „Fehlt noch“ auf der Künstlerseite, Künstlern folgen (nur neue Alben), Neuerscheinungen deiner Künstler.

**Hörbücher**
- Weiterhören, Kürzlich hinzugefügt, Genres (deutsch), Bibliotheken mit Suche.
- Player mit Kapiteln, 15 s zurück und 30 s vor, Tempo 0,75× bis 2×, Schlaf-Timer (auch bis Kapitelende). Die Position wird mit Audiobookshelf abgeglichen.
- **Hörbuch wünschen:** Suche bei Audible, Detailseite mit Beschreibung und Hörprobe, Wünschen oder **ganze Reihe folgen**.
- **Entdecken** (passend zu deinem Hörverlauf) und **Stöbern** in Audible-Kategorien, auch Hörspiele.

**Überall**
- **CarPlay** mit Start, Musik und Hörbüchern.
- **Offline:** Gehörte Hörbücher werden automatisch geladen (auf Wunsch nur im WLAN). Alben und Playlists per Knopf. Hörpositionen werden offline gemerkt und später nachgetragen.
- **Vorrat:** Die Startseite erscheint sofort aus dem Speicher und wird nachts im Hintergrund erneuert.
- **Mitteilungen** „Hörbuch ist da“ und „Album ist da“.
- **Was Ohrregal über mich weiß:** das Hörprotokoll einsehen und löschen.

## Server-Dienst (optional)

Wünschen, Entdecken, Stöbern, Reihen, Mitteilungen und das Hörprotokoll laufen über einen kleinen eigenen Dienst neben Audiobookshelf, Navidrome, Lidarr, Prowlarr und SABnzbd. Beschreibung und Einrichtung: [Dienst/README.md](Dienst/README.md), Schnittstelle: [Dienst/API.md](Dienst/API.md).

Ohne den Dienst funktioniert alles andere: Musik, Hörbücher, CarPlay, Offline und die Mixe auf dem iPhone.

## Datenschutz

- Zugangsdaten bleiben auf dem iPhone, Passwörter im Schlüsselbund.
- Das Hörprotokoll (was du hörst, überspringst, markierst, suchst und wünschst, mit Uhrzeit, Gerät und Ausgabe) geht nur an deinen eigenen Server. Es dient allein den Vorschlägen und lässt sich in der App einsehen und löschen.
- Nach außen gehen nur die gehörten Titel über Navidrome an Last.fm (falls dort eingerichtet). Der Server-Dienst fragt außerdem den öffentlichen Audible-Katalog ab.

## Einrichten

1. App über TestFlight installieren.
2. Beim ersten Start Navidrome (Pflicht) und Audiobookshelf (optional) eintragen. Später geht das über **Start → Profil → Zugänge**.
3. **Profil → Mitteilungen** einmal antippen und erlauben.

## Probleme und Lösungen

- **„Benutzername oder Passwort falsch“, obwohl es stimmt:** Prüfe, ob hinter dem Benutzernamen ein Leerzeichen steht (die Tastatur fügt gern eins an). Ab 0.2.4 entfernt die App es selbst. Als Adresse nur die Domain angeben, ohne `/app`.
- **Suchfeld nicht zu sehen:** Ab 0.7.0 sind alle Suchfelder fest sichtbar. In älteren Versionen die Liste leicht nach unten ziehen.
- **Keine Mitteilung „Hörbuch/Album ist da“:** Einmal **Profil → Mitteilungen** antippen. Die Meldung danach nennt den Grund, falls es nicht klappt. In den iPhone-Einstellungen müssen Mitteilungen für Ohrregal erlaubt sein.
- **„Entdecken“ fehlt oder zeigt einen Hinweis:** Der Server war kurz nicht erreichbar oder rechnet gerade. Herunterziehen lädt neu. Hilft das nicht, den Hinweistext mit Uhrzeit melden.
- **Seiten springen beim Öffnen zurück:** In Versionen vor 0.3.2 behoben. Bitte aktualisieren.
- **Fehlende Teile einer Reihe kommen nicht sofort:** Gewollt. Der Server lädt sie nachts in Ruhezeiten.
- **Gewünschtes Album öffnet „Noch nicht in Navidrome“:** Navidrome hat es noch nicht eingelesen. Etwas später noch einmal versuchen.

## Bauen

GitHub baut und testet bei jedem Push automatisch (Reiter **Actions**) und lädt die App zu TestFlight hoch. Lokal auf dem Mac:

```sh
brew install xcodegen
xcodegen          # erzeugt Ohrregal.xcodeproj
open Ohrregal.xcodeproj
```
