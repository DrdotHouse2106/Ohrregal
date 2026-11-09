# Ohrregal – Konzept

**Ohrregal** ist eine App für Musik und Hörbücher von den eigenen Servern, für das **iPhone** und für **Fire TV / Android TV**:

- **Musik** aus **Navidrome** (Subsonic- bzw. OpenSubsonic-API)
- **Hörbücher** aus **Audiobookshelf**

Der Name folgt dem Muster von Quallenkino (Jellyfin → *Jelly* → Qualle): Audiobookshelf → Regal, und für die Ohren ist beides.

Vorbild für Bedienung und Gefühl ist **Apple Music**. Die Optik und Wortwahl passen zu **Quallenkino**.

---

## 1. Grundsätze

1. **Eine App für beides.** Ein Player, ein CarPlay, eine Watch-App. Beide Server sind optional.
2. **Die eigenen Daten bleiben bei dir.** Das Hörverhalten wird auf dem iPhone ausgewertet. Nach außen geht nur das, was Navidrome ohnehin tut (Scrobbling an Last.fm).
3. **Schnell auch bei großen Bibliotheken.** Ziel sind über 50.000 Titel und 10.000 Alben. Daten werden seitenweise geladen und zwischengespeichert, nie die ganze Bibliothek auf einmal.
4. **Zuverlässig vor umfangreich.** Lieber weniger Funktionen, die immer funktionieren.
5. **Minimaler Code.** Systembausteine von Apple statt eigener Nachbauten.

## 2. Feste Pflichten (Lehren aus Subsonify)

| Nr. | Pflicht | Umsetzung |
|---|---|---|
| P1 | **Zurück an dieselbe Stelle.** Nach dem Zurückgehen steht jede Seite genau dort, wo sie war, auch die seitliche Position jeder Reihe. | Ansichten bleiben im `NavigationStack` erhalten, Daten werden nicht neu geladen; Scrollposition je Reihe über `scrollPosition(id:)` gemerkt. |
| P2 | **Antippen trifft das richtige Element.** In seitlich wischenden Reihen öffnet sich genau das angetippte Cover. | Jedes Cover ist ein eigener `Button`/`NavigationLink` mit fester ID; keine Gesten auf der ganzen Reihe. |
| P3 | **Hörbuch-Position geht nie verloren.** Auch offline und auch wenn zwischendurch Musik läuft. | Position wird lokal gespeichert und nachgetragen, sobald der Server erreichbar ist. Musik-Warteschlange und Hörbuch sind getrennt. |
| P4 | **CarPlay funktioniert von Anfang an.** | Gehört zur ersten Version, nicht „später“. |

Für P1, P2 und P3 gibt es automatische Oberflächentests.

## 3. Optik und Wortwahl

**Farben (aus Quallenkino):**

| Rolle | Farbe |
|---|---|
| Hintergrund | `#0b0e14` |
| Fläche (Karten, Leisten) | `#161b24` |
| Fläche hervorgehoben | `#1f2633` |
| Akzent Blau | `#2e96e0` |
| Akzent Violett | `#7f76d6` |
| Text | `#e8eaf0` |
| Text gedämpft | `#a9b1c2` |

Verläufe laufen von Blau nach Violett, zum Beispiel beim Fortschrittsbalken und beim Knopf „Spiel etwas für mich“.

**Aufbau wie Apple Music:**

- großer Titel oben
- Reihen, die seitlich wischen
- Mini-Player über der schwebenden Tab-Leiste
- Vollbild-Player mit Farbverlauf aus dem Cover

**Wortwahl:** Deutsch, „du“, kurz. Beispiele: „Weiterhören“, „Für dich“, „Lange nicht gehört“, „Vor einem Jahr hast du …“, „Spiel etwas für mich“, „Wer hört?“.

## 4. Aufbau der App

**Tabs:** Start · Musik · Hörbücher · Suchen

Ist nur ein Server eingerichtet, fällt der andere Tab weg.

### Start
- **Weiterhören** – angefangene Hörbücher und zuletzt gehörte Musik
- **Für dich** – Mixe (siehe Kapitel 5)
- **Spiel etwas für mich** – großer Knopf, startet sofort einen passenden Mix
- **Radio starten** – endlose Wiedergabe ab zuletzt gehörten Songs
- **Am häufigsten gespielt**, **Lange nicht gehört**, **Neuerscheinungen**, **Kürzlich hinzugefügt**
- **Vor einem Jahr hast du …**

Die Reihenfolge der Reihen hängt von der Tageszeit ab. Leere Reihen werden ausgeblendet.

### Musik
Künstler, Alben, Titel, Genres, Jahre, Playlists, „Gefällt mir“ (Songs, Alben, Künstler), Geladen (offline), Internetradio.

### Hörbücher
Weiterhören, Bibliothek, Serien, Autoren, Sammlungen, Geladen, Fertig gehört.

### Suchen
Eine Suche über beide Server, mit Filtern: Alle · Künstler · Alben · Songs · Playlists · Hörbücher · Autoren.

### Player
- **Mini-Player:** Cover, Titel, AirPlay, Pause, Fortschritt
- **Vollbild bei Musik:** Warteschlange (verschieben, löschen), Zufall, Wiederholen, Songtexte (synchron, falls vorhanden), „Gefällt mir“, „Radio ab diesem Song“
- **Vollbild bei Hörbüchern:** Kapitel, Geschwindigkeit (0,5×–3×), Schlaf-Timer (auch „Ende des Kapitels“), 30 s zurück und vor, Lesezeichen

## 5. Vorschläge (Musik)

Die Grundlage bilden Daten von Navidrome (mit Last.fm-Anbindung) und eine lokale Auswertung auf dem iPhone.

| Reihe / Mix | Quelle |
|---|---|
| Am häufigsten gespielt | `getAlbumList2?type=frequent` |
| Zuletzt gespielt | `getAlbumList2?type=recent` |
| Kürzlich hinzugefügt / Neuerscheinungen | `getAlbumList2?type=newest` bzw. nach Jahr |
| Lange nicht gehört | lokal: früher oft gehört, seit über 60 Tagen nicht mehr |
| Radio ab Song / Künstler | `getSimilarSongs2`, ergänzt durch `getTopSongs` |
| Täglicher Mix | lokal: Top-Künstler der letzten 30 Tage + ähnliche Künstler (`getArtistInfo2`), wechselt täglich |
| Mix pro Künstler / Genre | lokal gewichtet, Grundlage `getSimilarSongs2` und `getSongsByGenre` |
| Geliked-Mix | `getStarred2`, gemischt mit ähnlichen Titeln |
| Vor einem Jahr hast du … | lokaler Hörverlauf |

**Lokale Signale:**

- **Positiv:** Komplett gehört, „Gefällt mir“, mehrfach gehört
- **Negativ:** Übersprungen in den ersten 30 Sekunden
- **Kontext:** Tageszeit und Wochentag

Diese Signale beeinflussen Reihenfolge und Auswahl. Der Hörverlauf liegt nur auf dem Gerät und lässt sich in den Einstellungen löschen.

In Musik-Mixen landen keine Hörbücher.

## 6. Server-Schnittstellen

### Navidrome (OpenSubsonic)
- **Anmeldung:** Token und Salt (`t`, `s`), Passwort im Schlüsselbund
- **Bibliothek:** `getArtists`, `getArtist`, `getAlbum`, `getAlbumList2`, `search3`, `getPlaylists`, `getStarred2`, `getGenres`
- **Wiedergabe:**
  - `stream` (optional mit `maxBitRate`/`format` für mobile Daten)
  - `getCoverArt`
  - `scrobble` (Wiedergabe gestartet und fertig gehört)
- **Zusatz:**
  - `getLyricsBySongId` (OpenSubsonic)
  - `getPlayQueue`/`savePlayQueue` (an anderen Geräten weiterhören)
  - `star`/`unstar`, `getInternetRadioStations`

### Audiobookshelf
- **Anmeldung:** `POST /login`, Token im Schlüsselbund
- **Bibliothek:** `/api/libraries`, `/api/libraries/{id}/items`, `/api/me/items-in-progress`
- **Wiedergabe:** `POST /api/items/{id}/play`, `POST /api/session/{id}/sync`, `POST /api/session/{id}/close`
- **Fortschritt:**
  - `PATCH /api/me/progress/{id}`
  - Offline-Sitzungen über `POST /api/session/local`

## 7. Technik

- **Sprache und Oberfläche:** Swift, SwiftUI
- **Mindestversion:** iOS 17, watchOS 10
- **Wiedergabe:** AVFoundation (`AVQueuePlayer` für lückenlose Wiedergabe), `MPNowPlayingInfoCenter` und `MPRemoteCommandCenter` für Sperrbildschirm, Kopfhörer, CarPlay und Watch
- **Zwischenspeicher:** SwiftData für Bibliothek, Hörverlauf und Offline-Liste; Bilder im Dateisystem-Cache
- **Downloads:** Hintergrund-`URLSession`, optional umgewandelt (z. B. AAC 256 kbit/s)
- **CarPlay:** `CPTemplateApplicationScene` mit Tabs Start · Musik · Hörbücher · Suchen
- **Apple Watch:** Steuerung des iPhones; später eigene Offline-Wiedergabe
- **Keine Fremdbibliotheken**, solange es ohne geht

### Aufteilung im Code

```
Ohrregal/
├── App/                  iPhone-App (SwiftUI)
├── CarPlay/              CarPlay-Szene
├── Watch/                Watch-App
└── Kern/                 Swift-Paket, von allen geteilt
    ├── Server/           NavidromeClient, AudiobookshelfClient
    ├── Wiedergabe/       Player, Warteschlange, Ausgabeziele
    ├── Daten/            SwiftData-Modelle, Zwischenspeicher, Hörverlauf
    ├── Vorschlaege/      Mixe und Reihen
    └── Design/           Farben, Cover-Karte, Reihe, Mini-Player
```

### Ausgabeziele (Grundstein für den Heim-Satelliten)

Die Wiedergabe läuft über ein Protokoll `Ausgabeziel`:

```swift
protocol Ausgabeziel {
    var name: String { get }
    func spiele(_ eintrag: Eintrag, ab: TimeInterval) async throws
    func pause() async
    func weiter() async
    func springe(zu: TimeInterval) async
}
```

Erste Umsetzung: **Dieses iPhone**. AirPlay läuft über das System. Später kommt der **Heim-Satellit** dazu, zum Beispiel Snapcast, Music Assistant oder ein eigener Empfänger auf einem Raspberry Pi oder ESP32, als Ersatz für die HomePods.

## 8. Lidarr – Musik wünschen

Ohrregal zeigt, was in der Bibliothek fehlt, und gibt es mit einem Tipp an **Lidarr** weiter. Das ist dasselbe Prinzip wie die fehlenden Welt-Titel mit Jellyseerr in Quallenkino.

**Grundregel: Gewünscht werden einzelne Alben, keine ganzen Diskografien.** Lidarr selbst fügt nichts mehr automatisch hinzu; Wünsche kommen aus Ohrregal.

- **Album wünschen** (Standard): überall, wo ein Album fehlt – Künstlerseite, Suche, Neuerscheinungen.
- **Künstler folgen** (bewusste Zusatzaktion): nur künftige Alben werden überwacht, nie die ganze Diskografie.
- **Künstlerseite:** Reihe „Fehlt noch“ mit überwachten, aber fehlenden Alben, darunter weitere Alben zum Wünschen.
- **Für dich – Neue Künstler:** ähnliche Künstler von Last.fm, die noch nicht in der Bibliothek sind; angeboten werden ihre bekanntesten Alben zum Wünschen.
- **Neuerscheinungen deiner Künstler:** Lidarr-Kalender
- **Suche:** Wird etwas nicht gefunden, zeigt die Suche „Bei Lidarr suchen“. Liefert Lidarr nichts, steht dort „Bei Lidarr nicht gefunden“. Das kommt vor, weil MusicBrainz bei Nischenkünstlern Lücken hat.
- **Status:** „gewünscht“, „wird geladen“ oder „da“.

**Abläufe:**

| Fall | Aufrufe |
|---|---|
| Album suchen | `GET /api/v1/album/lookup?term=<Künstler Album>` |
| Künstler noch nicht in Lidarr | `POST /api/v1/album` mit dem Lookup-Album, `monitored=true`, `addOptions.searchForNewAlbum=true`; im eingebetteten `artist`: Qualitäts- und Metadatenprofil, Stammordner, `monitorNewItems="none"`, `addOptions.monitor="none"`. So wird nur dieses Album überwacht und sofort gesucht. |
| Künstler schon in Lidarr | Album über `album/lookup` bzw. `GET /api/v1/album?artistId=…` finden, dann `PUT /api/v1/album/monitor` und `POST /api/v1/command` mit `AlbumSearch` |
| Künstler folgen | nur neue Alben überwachen (`monitorNewItems="all"`, vorhandene Alben unverändert), **nie** die ganze Diskografie |
| Fehlt noch | `GET /api/v1/wanted/missing?monitored=true` |
| Status | `GET /api/v1/queue`, Album-Statistik (`statistics.trackFileCount`) |
| Neuerscheinungen | `GET /api/v1/calendar` |

Profile und Stammordner sind in den Einstellungen wählbar (aus `qualityprofile`, `metadataprofile`, `rootfolder`). Die Feldnamen vor dem Einbau gegen die Lidarr-Version des Servers prüfen.

**Erreichbarkeit und Sicherheit:**

- Lidarr ist nur im Heimnetz bzw. über VPN erreichbar und soll das auch bleiben.
- Wünsche von unterwegs landen in einer **Wunschliste** und werden geschickt, sobald Lidarr erreichbar ist.
- Der API-Schlüssel gibt vollen Zugriff auf Lidarr. Er liegt nur im Schlüsselbund. Ohne Schlüssel blendet die App alle Lidarr-Funktionen aus.

## 9. Hörbücher wünschen (Hörbuchwunsch)

Für Hörbücher gibt es kein gepflegtes Gegenstück zu Lidarr mehr. Ohrregal bekommt deshalb einen kleinen eigenen Dienst: **Hörbuchwunsch**. Er läuft als Container im Media-Stack. Audiobookshelf hat kein Plugin-System, eine Erweiterung direkt darin geht also nicht.

**Aufteilung:** Den Dienst baut die Server-Sitzung „Heimnetz“, die App-Seite entsteht hier. Beschlossen am 08.11.2026.

**Ablauf:**

1. **Suchen (in der App):** Audiobookshelf fragt seine Metadatendienste ab: `GET /api/search/books?provider=audible.de&title=…&author=…`, alternativ Google Books oder iTunes. Die App zeigt Cover, Titel, Autor, Sprecher, Länge, Serie und Teil. Was schon in Audiobookshelf liegt, ist als „da“ markiert.
2. **Wünschen:** Die App schickt den Treffer mit ASIN, Titel, Autor, Serie und Sprache an Hörbuchwunsch.
3. **Finden:** Hörbuchwunsch sucht über **Prowlarr** in der Hörbuch-Kategorie (3030) und bewertet die Ergebnisse:
   - Titel und Autor müssen passen.
   - Bevorzugt werden „Ungekürzt“, Deutsch und eine plausible Größe zur Laufzeit.
   - Verwechslungen mit Hörspiel- oder Kinderfassungen werden aussortiert.
4. **Laden:** Der beste Treffer geht an **SABnzbd**, in die Kategorie für Hörbücher.
5. **Einsortieren:**
   - Nach dem Download legt Hörbuchwunsch die Dateien im Audiobookshelf-Ordner als `Autor/Reihe/Titel/` ab.
   - Dazu speichert er die ASIN in den Metadaten, damit Audiobookshelf das Buch sicher zuordnet.
   - Danach stößt er einen Scan der Bibliothek an.
6. **Melden:** Eine Push-Nachricht „Dein Hörbuch ist da“ geht über ntfy. In der App wechselt der Status.

**Wunschliste:** Was noch nicht zu finden ist, bleibt auf der Liste. Hörbuchwunsch sucht täglich erneut. Bei Serien kann man „Serie folgen“ wählen, dann kommen neue Teile automatisch auf die Wunschliste.

**Status in der App:** `gewuenscht`, `nicht_gefunden`, `laedt`, `einsortieren`, `da` und `fehler`, jeweils mit Datum und bei Bedarf einem Hinweis, warum nichts gepasst hat. Fehlgeschlagene Downloads werden mit dem nächstbesten Treffer erneut versucht.

**Warum ein eigener Dienst statt nur der App:**

- Die API-Schlüssel für Prowlarr und SABnzbd bleiben auf dem Server.
- Wiederholte Suche und Einsortieren funktionieren auch, wenn das iPhone aus ist.
- Die TV-App und das iPhone nutzen dieselbe Wunschliste.

**Technik:**

- Kleiner Dienst mit einer Datei und SQLite für die Wunschliste, als Docker-Container.
- Der Code liegt im Ordner `Dienst/` in diesem Repo.
- Erreichbar zu Hause und unterwegs unter der Audiobookshelf-Adresse + `/wunsch-api` (gleicher Reverse-Proxy), die App leitet die Adresse selbst ab. Anmeldung mit dem Audiobookshelf-Token des Benutzers (`Authorization: Bearer …`), der Dienst prüft es bei Audiobookshelf. Einen eigenen Zugang braucht es nicht.
- Einstellungen nur über Umgebungsvariablen, keine Adressen oder Schlüssel im Repo.

**Schnittstelle für die App:** siehe [`Dienst/API.md`](Dienst/API.md). Unter anderem gibt es: Wünschen, Wunschliste mit Fortschritt, Zurückziehen (die Datei bleibt dabei immer erhalten) und Erneut suchen. Reihe folgen kommt in Version 2.

## 10. TV-App (Fire TV und Android TV)

Gleicher Name, gleiche Optik, gleiche Tabs, aber für die Fernbedienung gebaut. Gedacht für Fire TV Sticks und Android-TV-Sticks, nicht für Handys.

- **Bedienung mit dem Steuerkreuz:** große Cover, deutlicher Fokusrahmen in Quallen-Blau. P1 und P2 gelten genauso: Fokus und Position bleiben nach dem Zurückgehen erhalten.
- **Start, Musik, Hörbücher, Suchen** wie auf dem iPhone, Suche auch per Sprache, sofern die Fernbedienung das kann
- **Vollbild-Player:** großes Cover, Farbverlauf, Songtext, Bildschirmschoner mit Cover
- **Weiterhören zwischen den Geräten:** Hörbuch-Position über Audiobookshelf, Musik-Warteschlange über `savePlayQueue`/`getPlayQueue`. Was am iPhone läuft, kann am Fernseher weiterlaufen und umgekehrt.
- **Wiedergabe im Hintergrund**, Steuerung über die Fernbedienungstasten
- **Später als Ausgabeziel:** Das iPhone kann den Fernseher als Lautsprecher wählen, wie einen Heim-Satelliten.

**Technik:**

- Kotlin, Jetpack Compose for TV, Media3 (ExoPlayer) mit `MediaSessionService`
- Ab Android 7 (API 24), das deckt alle aktuellen Fire TV Sticks ab
- Gleiche Farben und Wortwahl; die Server-Zugriffe folgen Kapitel 6.
- Liegt im selben Repo im Ordner `TV/`.
- GitHub baut die APK kostenlos. Installation per „Downloader“-App über einen festen Link zur neuesten Version, ohne Entwicklerkonto.

## 11. Fahrplan und Stand

Stand: 09.11.2026, App 0.13.0, Hörbuchwunsch 2.3.0.

| Stufe | Inhalt | Stand |
|---|---|---|
| **1 – Grundversion Musik** | Anmeldung, Mediathek, Suche, Player, AirPlay, Sperrbildschirm, Scrobbling, P1, P2, CarPlay | fertig |
| **2 – Vorschläge** | Hörverlauf, Für dich mit Cover-Collagen, Dein Mix, Künstler-Mixe, Radio ab Song, Lange nicht gehört, Schnellauswahl | fertig |
| **2 – Player** | Gefällt mir, Playlists anlegen/bearbeiten (in Navidrome), Warteschlange, Songtexte | fertig |
| **2 – Offline und Vorrat** | Hörbücher automatisch laden (nur WLAN), Alben/Playlists laden, Hörposition offline, Startseite aus dem Vorrat, nächtliches Erneuern | fertig |
| **3 – Hörbücher** | Audiobookshelf, Kapitel, Tempo, Schlaf-Timer, P3, Hörbücher in CarPlay, Kürzlich hinzugefügt, Genres (deutsch) | fertig |
| **3b – Hörbuchwunsch** | Wünschen mit Detailseite und Hörprobe, Reihe folgen, Entdecken, Stöbern (inkl. Hörspiele), Push „Hörbuch ist da“, Vorrechnen in Ruhezeiten | fertig |
| **2b – Lidarr** | Einzelne Alben wünschen, Künstler folgen (nur neue Alben), Fehlt noch, Wunschliste | offen |
| **4 – Apple Watch** | Steuerung, danach eigene Offline-Wiedergabe | offen |
| **TV-App** | Fire TV / Android TV mit Musik und Hörbüchern | offen |
| **App Store** | Veröffentlichung, danach Smart-App-Banner auf der Hörbuch-Seite | offen |
| **6 – Heim-Satellit** | weitere Ausgabeziele, Raumauswahl | offen |
| **später** | Widgets, Siri-Kurzbefehle, Equalizer, Crossfade, „Wer hört?“, Weiterhören zwischen Geräten (savePlayQueue) | offen |

**Grundsatz Vorrat:** Was sich vorrechnen lässt, wird im Leerlauf gerechnet (Server: nachts 3–6 Uhr, nur wenn niemand streamt; App: Hintergrundaufgabe ab 3 Uhr) und tagsüber nur ausgeliefert. Was man hört, liegt auf dem iPhone.

## 12. Voraussetzungen

- Mac mit aktuellem Xcode zum Bauen
- Apple-Entwicklerkonto (vorhanden; für Gerät, TestFlight, CarPlay)
- **CarPlay-Freigabe** (Audio) bei Apple beantragen, möglichst früh
- Für die TV-App: nichts Zusätzliches; GitHub baut die APK. Amazon- und Google-Play-Entwicklerkonto sind vorhanden, falls die App später in die Stores soll.
- Optional: Lidarr-API-Schlüssel
- Für Hörbuchwunsch: Prowlarr mit Usenet-Indexern, die Hörbücher führen; SABnzbd mit eigener Kategorie; Schreibzugriff auf den Audiobookshelf-Ordner
- Navidrome mit Last.fm-Anbindung, optional Audiobookshelf
